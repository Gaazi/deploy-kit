# Deploy Kit — reference_deploy_flow.md

> Full deploy flow, toggle, rollback, GitHub Actions wiring, troubleshooting. Read on demand.

## How a deploy happens (end to end)

```
git push (any branch)
  → GitHub Actions workflow (deploy.yml.example) triggers (~6s)      ← RUNNER: sirf trigger
      - no checkout, no build, no migrate — only the SSH fire-and-forget
        ssh user@server "nohup /bin/bash ~/deploy-kit/auto_deploy.sh <branch> &"
  → server: auto_deploy.sh <branch> runs in background (nohup)       ← SERVER: sara kaam
  → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → health → Telegram
```

**Resource principle (keep):** the runner does ONLY the ~6s trigger — every real step
(fetch, rsync, build, backup, migrate, restart, health, Telegram) runs on the server.
Never add deploy work to the workflow — it belongs in auto_deploy.sh (or rollback.sh).

## auto_deploy.sh steps (numbered)

0. **Flag check** — if `TOGGLE_FLAG` file exists AND `SKIP_WHEN_FLAG` set → exit 0 (toggle mode)
0.5 **Deploy lock** — mkdir-based `$WORKSPACE_BASE/.deploy-lock` (+ PID file): second concurrent deploy skips (the running one fetches latest anyway); stale lock (dead PID) auto-cleaned; released via trap on EXIT. Rollback uses the same lock and errors out if a deploy is running.
1. **Workspace** — clone if missing, else `git fetch origin <branch>`. **Safety guard: if `origin/<branch>` can't be resolved (clone/fetch failed, wrong branch) → abort BEFORE rsync — the app dir is never touched.**
2. **SHA skip** — compare `.deployed_sha`; same SHA → exit 0 (no work, prints "No new commit" on stdout too)
3. **Rsync** — `-az --delete` with excludes: `.git/`, `.env`, `*.db`, `*.sqlite3`, `__pycache__/`, `*.pyc`, `node_modules/`, `venv/`, `.venv/`, `*.log`, `media/`, `backups/`, `tests/` + any extra `RSYNC_EXCLUDES` (space-separated). **`APP_SUBDIR` set → only that subfolder is deployed** (monorepos); missing subfolder → abort before touching app dir.
4. **Build** — if `BUILD_CMD` set → run in APP_DIR. **Failure → Telegram fail alert + abort** (app may be partially updated → hint rollback).
5. **DB backup** — if `DB_BACKUP=yes` + DB_* set → mysqldump/pg_dump to `$APP_DIR/backups/predeploy/`, keep `DB_BACKUP_KEEP` (default 7); sqlite = file copy, keep 7
6. **Migrate** — if `MIGRATE_CMD` set → run in APP_DIR. **Failure → Telegram fail alert + abort** (hint: restore DB dump then rollback).
7. **Restart** — per `RESTART_METHOD` (passenger → touch tmp/restart.txt; systemctl → restart `$SERVICE_NAME` or `$SITE_DOMAIN`; pm2 → `pm2 restart $PM2_APP`; supervisor → `supervisorctl restart $SUPERVISOR_APP`; docker → compose down/up; php → reload fpm; none/"" → skip). All restart failures are non-fatal (`|| true`) — deploy never crashes because a service binary is missing.
8. **Record SHA** — write `.deployed_sha` in workspace
9. **Health check** — only if HEALTH_URL resolves (empty → skip, **no sleep**); `sleep $HEALTH_WAIT` (default 8) → `curl -m 15`; OK → success alert, fail → warning alert
10. **Telegram** — start/success/fail alerts via `notify()` (only if token+chat set)

Log rotation: `$LOG` rotated to `$LOG.1` when it exceeds 1 MB (kept light).

## Rollback (rollback.sh)

```
/bin/bash rollback.sh <branch> [commit-sha]
```
- No sha → uses last deployed SHA from `.deployed_sha`
- Uses `DEFAULT_BRANCH` too (same default logic as auto_deploy.sh)
- Fetches, **safety guard: target SHA must resolve locally → else abort before rsync**, checks out target SHA
- Rsyncs to APP_DIR with the **same excludes** as auto_deploy.sh (+ RSYNC_EXCLUDES)
- **Rebuilds** if `BUILD_CMD` set (Node/static rollbacks stay working)
- Restores latest pre-migration dump if DB_* set and dump exists
- Restarts per RESTART_METHOD (same methods as auto_deploy.sh)
- Writes rollback line to the same LOG_FILE

## Self-test (test.sh)

```
/bin/bash test.sh
```
- bash -n on every script; missing-config error; missing-required-vars error
- Full local integration test: real file:// git repo → deploy → idempotent skip → new commit → rollback
- No network needed; everything in a temp dir. Run before committing changes.

## Toggle (GitHub vs Cron) — optional

- `TOGGLE_FLAG=""` → no toggle, always deploys
- `TOGGLE_FLAG=/path/flag` + `SKIP_WHEN_FLAG=1` → flag present = skip (e.g. cron disabled when GitHub active)
- Example: cron runs every 2 min; GitHub Runner active → user touches flag → cron skips

## GitHub Actions wiring (deploy.yml.example)

- Triggers on push to configured branches; `paths-ignore: ["*.md", "**/*.md", "docs/**"]` — doc-only pushes cost 0 runner time (workflow doesn't even start)
- `permissions: {}` — minimal: no unnecessary GITHUB_TOKEN (faster + safer)
- `concurrency` group — overlapping runs cancel (save minutes)
- No checkout (fastest); SSH with private key from secrets; `BatchMode=yes`; `ConnectTimeout=10`
- Fire-and-forget: `nohup ... &` — run completes in ~6s, deploy continues on server
- GitHub Secrets needed: `SERVER_HOST`, `SERVER_USER`, `SSH_PORT`, `SSH_PRIVATE_KEY`
- **`keygen.sh` prints all 4 secret values + the Deploy key — pure copy-paste, no manual key work**

## Zero GitHub Actions (cron.sh) — optional, free-plan friendly

- Free GitHub = **2,000 Actions min/month**; each deploy ≈ 1 min (VM boot + ~6s job) → ~2,000 deploys/mo
- **`cron.sh`** installs a server cron job (`*/N * * * * /bin/bash .../auto_deploy.sh <branch>`) — **0 Actions minutes**, deploy within N min. SHA check = idle runs are instant no-ops.
- If `crontab` is unavailable (cPanel), `cron.sh` prints the exact line for **cPanel → Cron Jobs**.

## Webhook trigger (~1-2s, VPS only)

- `webhook.sh` — socat HTTP listener (start/stop/status). GitHub POSTs to `http://SERVER:PORT/webhook/deploy/` with `X-Deploy-Secret` header → handler verifies secret → `auto_deploy.sh <branch>` in background. ~1-2s from push to deploy start, 0 Actions minutes.
- Depends on `socat` (apt install socat). Pair with `deploy-webhook.yml.example`.
- GitHub secrets needed: `DEPLOY_WEBHOOK_SECRET` (same value as server's config.sh), `DEPLOY_WEBHOOK_URL` (the public URL).
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
