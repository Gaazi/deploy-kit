# Deploy Kit — reference_deploy_flow.md

> Full deploy flow, toggle, rollback, GitHub Actions wiring, troubleshooting. Read on demand.

## How a deploy happens (end to end)

```
git push (any branch)
  → GitHub Actions workflow (deploy.yml.example) triggers (~6s)      ← RUNNER: trigger only
      - no checkout, no build, no migrate — only the SSH fire-and-forget
        ssh user@server "nohup /bin/bash ~/deploy-kit/auto_deploy.sh <branch> &"
  → server: auto_deploy.sh <branch> runs in background (nohup)       ← SERVER: sara kaam
  → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → health → Telegram
```

**Resource principle (keep):** the runner does ONLY the ~6s trigger — every real step
(fetch, rsync, build, backup, migrate, restart, health, Telegram) runs on the server.
Never add deploy work to the workflow — it belongs in auto_deploy.sh (or rollback.sh).

## auto_deploy.sh steps (numbered)

0. **Config load & Branch Config** — loads `config.<branch>.sh` if it exists, otherwise `config.sh` (allows multi-environment staging & production).
0.2 **Flag check** — if `DEPLOY_TRIGGER=cron` (set by cron.sh's line) AND `TOGGLE_FLAG` file exists AND `SKIP_WHEN_FLAG` set → exit 0. Only CRON deploys skip — Actions/webhook/runner deploys never carry the trigger marker and always run.
0.5 **Deploy lock** — mkdir-based `$WORKSPACE_BASE/.deploy-lock` (+ PID file): second concurrent deploy skips (the running one fetches latest anyway); stale lock (dead PID) auto-cleaned; released via trap on EXIT. Rollback uses the same lock and errors out if a deploy is running.
1. **Workspace** — clone if missing, else `git fetch origin <branch>`. Clone, fetch, checkout and reset must succeed, and `origin/<branch>` must resolve. Any failure aborts before rsync, even when a stale remote reference exists.
2. **SHA skip** — compare `.deployed_sha`; same SHA → exit 0 (no work, prints "No new commit" on stdout too)
2.5 **Pre-deploy hook** — if `PRE_DEPLOY_HOOK` set → run in APP_DIR (or WORKSPACE if first deploy). **Failure → Telegram fail alert + abort** BEFORE rsync touches APP_DIR (safe, app untouched).
3. **Rsync** — `-az --delete` with excludes: `.git/`, `.env`, `*.db`, `*.sqlite3`, `__pycache__/`, `*.pyc`, `node_modules/`, `venv/`, `.venv/`, `*.log`, `media/`, `backups/`, `tests/`, `deploy_kit/`, `deploy-kit/`, `config.sh`, `config.*.sh`, `.htaccess`, `.htaccess.` + any extra `RSYNC_EXCLUDES` (space-separated). `.htaccess` is excluded on purpose (a real deployment lesson: `--delete` wiped the server's web-server config → 404) — so a `.htaccess` that lives in the REPO is never deployed either; keep server rewrites on the server. **`APP_SUBDIR` set → only that subfolder is deployed** (monorepos); missing subfolder → abort before touching app dir.
   Rsync failure aborts before build, migration and SHA recording; fix the error and retry. The app may be partially synced.
4. **Build** — if `BUILD_CMD` set → run in APP_DIR. **Failure → Telegram fail alert + abort** (app may be partially updated → hint rollback).
5. **DB backup** — if `DB_BACKUP=yes` + DB_* set → mysqldump/pg_dump (or `db-dump.py` when the CLI is missing) to `$WORKSPACE_BASE/backups/<branch>/` (outside the app dir — web-safe), keep `DB_BACKUP_KEEP` fresh (default 7); older dumps are gzip-compressed, never deleted (the `.gz` archive is capped at `DB_BACKUP_KEEP` and pruned only once 21+ archives exist); sqlite = file copy. Backup filenames include the timestamp and deploy PID to avoid overwriting dumps from fast consecutive deploys. A dump tool that FAILS is flagged (`DB backup INVALID (failed)`) even when it left a valid-looking header behind.
6. **Migrate** — if `MIGRATE_CMD` set → run in APP_DIR. **Failure → Telegram fail alert + abort** (hint: restore DB dump then rollback).
7. **Restart** — per `RESTART_METHOD` (passenger → touch tmp/restart.txt; systemctl → restart `$SERVICE_NAME` or `$SITE_DOMAIN`; pm2 → `pm2 restart $PM2_APP`; supervisor → `supervisorctl restart $SUPERVISOR_APP`; docker → compose down/up; php → reload fpm; none/"" → skip). All restart failures are non-fatal (`|| true`) — deploy never crashes because a service binary is missing.
7.5 **Post-deploy hook** — if `POST_DEPLOY_HOOK` set → run in APP_DIR after restart and before health check (e.g. cache clear, CDN purge, maintenance off).
8. **Record SHA** — write `.deployed_sha` in workspace
9. **Health check** — only if HEALTH_URL resolves (empty → skip, **no sleep**); `sleep $HEALTH_WAIT` (default 8) → `curl -m 15` retried `$HEALTH_RETRY` (default 3) times with 5s gaps; OK → success alert, fail → warning alert
   Auto-rollback is reported as completed only when rollback.sh succeeds. On failure, deploy exits non-zero, restores the previous deploy marker for retry, and does not write the failed-SHA skip marker.
10. **Notifications** — start/success/fail alerts via `notify()` (Telegram/Discord/Slack/Email). If `NOTIFY_ON_SUCCESS=no`, success alerts are suppressed (failure/rollback alerts only).

Log rotation: `$LOG` rotated to `$LOG.1` when it exceeds 1 MB (kept light).

## Rollback (rollback.sh)

```
/bin/bash rollback.sh <branch> [commit-sha]
```
- No sha → rolls back to `.previous_sha` (the version live before the current deploy); if that is missing/equal to `.deployed_sha`, it re-syncs the current `.deployed_sha`
- Uses `DEFAULT_BRANCH` too (same default logic as auto_deploy.sh)
- Fetches, **safety guard: target SHA must resolve locally → else abort before rsync**, checks out target SHA
- checkout / rsync / build failures **abort with a non-zero exit** (never prints "✅ Rolled back" for a no-op)
- Rsyncs to APP_DIR with the **same excludes** as auto_deploy.sh (+ RSYNC_EXCLUDES)
- **Rebuilds** if `BUILD_CMD` set (Node/static rollbacks stay working)
- Restores the latest fresh (uncompressed) dump when DB_* is set and a dump exists; DB creds missing from config.sh are auto-read from the app `.env` `DATABASE_URL` (same fallback as auto_deploy.sh), the `mysql` CLI falling back to `db-dump.py restore`, and every failure is reported instead of being silent
- Restarts per RESTART_METHOD (same methods as auto_deploy.sh)
- Writes rollback line to the same LOG_FILE

## Self-test (test.sh)

```
/bin/bash test.sh
```
- bash -n on every script; missing-config error; missing-required-vars error
- Full local integration test: real file:// git repo → deploy → idempotent skip → new commit → rollback (explicit SHA **and** no-SHA "previous version")
- Backup rotation + failed-dump verdict, notification gate (stub `mail`), KIT_SNAP early-exit, deploy-lock, hooks, branch config, cron/webhook/doctor checks
- Six command-failure checks in `tests/deploy-failures.sh`; CI runs the 80 core checks and four consistency checks on `dev` and `main` pushes and pull requests.
- No host state is touched: `cron.sh` runs against a fake `crontab` (the real crontab is NEVER replaced). Everything lives in a temp dir; the only outbound calls are the notification mocks, which now time out.

## Quickstart (quickstart.sh) — 1 command, everything

```
/bin/bash quickstart.sh
```
- Chained runner: `setup.sh` (config) → `keygen.sh` (SSH keys) → `detect.sh` (auto-detect) → `test.sh` (self-test)
- User presses Enter for recommended values; ends with "copy workflow + push" instructions
- The minimum-reading path — full detail only in README for those who need it

## Preflight doctor (doctor.sh)

```
/bin/bash doctor.sh [config.sh]
```
- Checks shell/tools (git rsync curl ssh tar sed awk), config presence + permissions + required keys
- Checks workspace/app dirs writable, SSH key, webhook deps
- Exit 1 if config missing; summary of PASS/WARN/FAIL at the end

## Toggle (GitHub vs Cron) — optional

- `TOGGLE_FLAG=""` → no toggle, always deploys
- `TOGGLE_FLAG=/path/flag` + `SKIP_WHEN_FLAG=1` → flag present = **cron** deploys skip (Actions/webhook/runner always run — cron.sh marks its line with `DEPLOY_TRIGGER=cron`)
- Example: cron runs every 2 min; GitHub Runner active → user touches flag → cron skips

## GitHub Actions wiring (deploy.yml.example)

- Triggers on push to configured branches; `paths-ignore: ["*.md", "**/*.md", "docs/**"]` — doc-only pushes cost 0 runner time (workflow doesn't even start)
- `permissions: {}` — minimal: no unnecessary GITHUB_TOKEN (faster + safer)
- `concurrency` group — overlapping runs cancel (save minutes)
- No checkout (fastest); SSH with private key from secrets; `BatchMode=yes`; `ConnectTimeout=10`
- Fire-and-forget: `nohup ... &` — run completes in ~6s, deploy continues on server
- GitHub Secrets needed: `SERVER_HOST`, `SERVER_USER`, `SSH_PORT`, `SSH_PRIVATE_KEY`, `SERVER_DEPLOY_PATH` (optional)
- **`keygen.sh` prints all 5 secret values + the Deploy key — pure copy-paste, no manual key work**
- **`SERVER_DEPLOY_PATH`** — full path to `auto_deploy.sh` on the server. Default (if unset): `~/deploy-kit/auto_deploy.sh`. If your kit lives elsewhere (e.g. `~/lq_auto_deploy.sh`), set this secret — otherwise the workflow fails with "No such file or directory" in the server log. Used by deploy.yml + deploy-selfhosted.yml.
- **Bootstrap (deploy.yml only):** before firing, the workflow checks if `auto_deploy.sh` exists on the server; if missing, it clones the kit (HTTPS, public repo — no key needed) to `$KIT_DIR` and copies `config.example.sh` → `config.sh`. So the FIRST deploy auto-installs the kit on the server — no manual server setup. User then fills `config.sh` secrets once.

## Zero GitHub Actions (cron.sh) — optional, free-plan friendly

- Free GitHub = **2,000 Actions min/month**; each deploy ≈ 1 min (VM boot + ~6s job) → ~2,000 deploys/mo
- **`cron.sh`** installs a server cron job (`*/N * * * * /bin/bash .../auto_deploy.sh <branch>`) — **0 Actions minutes**, deploy within N min. SHA check = idle runs are instant no-ops.
- If `crontab` is unavailable (cPanel), `cron.sh` prints the exact line for **cPanel → Cron Jobs**.

## Webhook trigger (~1-2s, VPS only)

- `webhook.sh` — socat HTTP listener (start/stop/status). GitHub POSTs to `http://SERVER:PORT/webhook/deploy/` → handler verifies → `auto_deploy.sh <branch>` in background. ~1-2s from push to deploy start, 0 Actions minutes.
- Depends on `socat` + `openssl` (apt install socat). Pair with `deploy-webhook.yml.example`.
- **2 auth modes (both supported):**
  - **Native GitHub webhook** (0 runner): repo → Settings → Webhooks → payload URL + secret. Handler verifies `X-Hub-Signature-256` (HMAC-SHA256) and reads branch from `"ref":"refs/heads/<branch>"`.
  - **Custom header** (from `deploy-webhook.yml.example`): `X-Deploy-Secret` matches `DEPLOY_WEBHOOK_SECRET`; branch from `{"branch":"..."}`.
- **Branch validation:** extracted branch must match `[A-Za-z0-9._/-]+` with no `..` — anything else → 403 (branch becomes a path component `WORKSPACE/$BRANCH`).
- GitHub secrets needed (Actions path): `DEPLOY_WEBHOOK_SECRET` (same value as server's config.sh), `DEPLOY_WEBHOOK_URL` (the public URL).
- Toggle: with Actions + cron both present, `touch ~/.deploy_github` + `SKIP_WHEN_FLAG=1` → cron skips (Actions handles it). Remove flag → cron deploys again.

## Self-hosted runner (~6s deploys, VPS only)

- `runner.sh` downloads/registers/installs a GitHub self-hosted runner on the server (needs systemd → VPS)
- **No VM boot** → GitHub run finishes in ~5-6s; self-hosted minutes are free (0 Actions minutes)
- Pair with `deploy-selfhosted.yml.example` (`runs-on: self-hosted`); runs `auto_deploy.sh` directly (no SSH)
- ⚠️ Install as the SAME user that owns `~/deploy-kit/`; not for shared hosting

## SSH keys (keygen.sh)

- ONE key pair, works both ways:
  - server → GitHub: private key = `DEPLOY_KEY` (config), public key → repo **Deploy keys** (allows clone)
  - GitHub → server: private key → Actions secret `SSH_PRIVATE_KEY`, public key appended to `~/.ssh/authorized_keys` (allows the SSH trigger)
- cPanel note: if `authorized_keys` write is blocked, import/authorize the public key via cPanel SSH Access UI
- Deploy keys are per-repo — for each new repo repeat only the Deploy-key step

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `config.sh not found` | Config missing | `cp config.example.sh config.sh` |
| Health FAILED | App down after deploy | Check log, run `rollback.sh`, check restart method |
| No new commit — skip | `.deployed_sha` same | Normal — no changes on branch |
| Deploy started but no Telegram | Token/chat empty | Set `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` |
| `config.sh already exists` | Re-running setup | `rm config.sh` first |
| Deploy slow/hang | curl without timeout | Health check uses `-m 15` — shouldn't hang |
| "No such file or directory" in `~/deploy.log` | Workflow calls wrong path | Set `SERVER_DEPLOY_PATH` GitHub Secret to the real path |
| Duplicate cron deploys (double-fire) | Old unquoted cron line + new quoted line both present | `cron.sh` re-install filters BOTH formats (`auto_deploy.sh' 'main` AND `auto_deploy.sh main `) — re-run cron.sh |
| Nothing deploys when flag file exists | Toggle blocks ALL triggers | Now cron-only: `DEPLOY_TRIGGER=cron` marks cron lines; Actions/webhook/runner always run |
| `/tmp/kit-deploy.*` leaking | EXIT trap overwritten | Combined trap cleans `LOCK_DIR` + `KIT_SNAP` together; snapshot only when `KIT_SELF_UPDATE=yes` |

## Security & robustness notes (read these before editing)

- **Snapshot guard:** `KIT_SELF_UPDATE=yes` → `auto_deploy.sh` re-execs from a `/tmp` snapshot BEFORE running git pull, so the live file is never rewritten while bash is reading it (shared-hosting corruption risk). Guard runs AFTER `source config.sh` — never move it before config load (it reads `KIT_SELF_UPDATE` from config).
- **Doctor web-access check:** uses `case "$SCRIPT_DIR" in "$APP_DIR"/*)` — the trailing `/*` matters (avoids `/home/user/app2` matching `/home/user/app`). If `APP_DIR` is set and kit is inside it, `.htaccess` must exist or doctor FAILs.
- **Branch safety:** webhook.sh validates BRANCH (only `[A-Za-z0-9._/-]`, rejects `..`) before it becomes a path. Workflows pass branch via env + `tr -cd` sanitize — never inline `'${{ github.ref_name }}'` in a shell string.
- **`.htaccess`:** ships with the kit, denies all web access — protects `config.sh` when the kit lives inside a web-accessible app dir. Do not delete.

## Stable kit update/release flow

Installation lock serializes kit updates, app deploys and rollbacks. Auto deploys
use a script snapshot. update.sh always snapshots itself and its libraries before
replacement. Default daily cached checks only notify; patch auto-update is opt-in
(KIT_UPDATE_MODE=auto, or legacy KIT_SELF_UPDATE=yes with MODE unset). Minor/major
changes require manual apply; major apply requires --allow-major. Config, keys,
local edits and application files are protected. Checks work only after the new
checker is installed; idle servers need an explicitly configured check cron.

update.sh apply validates a tagged package and stages a recoverable backup.
Failure attempts restoration; a pending journal blocks later deployments.
update.sh rollback restores managed files and Git metadata and blocks auto retry
of the failed version. State lives privately in .kit-update (ignored).

release.sh prepare creates version/checksums locally; package runs full tests and
creates deterministic tar.gz from committed explicit paths; publish runs on synced
main, tests, pushes an immutable stable tag and creates a GitHub Release.
.github/workflows/release.yml is a manual package/publish gate on main.
Only main stable releases are distributed; prereleases are ignored. Private Git
upstreams need normal credentials. No workflow deploys a live website here.
