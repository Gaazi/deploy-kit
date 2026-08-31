# Deploy Kit — MEMORY.md

> Project knowledge index. **Grep for keywords — never read whole file.** This index is for fast lookup: most-used facts at the top.

## ⚡ Quick Reference (fastest lookup)

- **What:** config-driven auto-deploy kit for ANY project (Python/Node/PHP/WordPress/Ruby/Java/Go/static/Docker) on cPanel or VPS
- **MAIN GOAL:** server + GitHub resource = minimum, so free limits never run out
- **Trigger options:** hosted Actions (~1 min) · self-hosted runner (~6s, `runner.sh`, VPS) · webhook (~1-2s, `webhook.sh`, VPS — native = 0 runner) · cron (`cron.sh`, 0 Actions) — all call the SAME `auto_deploy.sh`
- **Resource principle:** runner does ONLY the ~6s trigger; ALL deploy work runs on the server. Never add deploy logic to a workflow.
- **Resource budget (GitHub):** hosted ~1 min/deploy · native webhook 0 · cron 0 · self-hosted 0 · docs push 0 (paths-ignore)
- **Resource budget (server):** `--single-branch` clone · SHA-skip instant · log 1MB rotation · DB_BACKUP_KEEP · deploy lock · optional steps only when configured
- **Required config:** only `REPO_URL` + `APP_DIR`. Everything else optional — empty = skip, never crash.
- **Test:** `/bin/bash test.sh` — 43 checks, run before committing. CI runs it on every push to main.
- **Deploy flow:** git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → health → notifications (Telegram/Discord/Slack/Email)

## File map (what each script does)

| File | Role |
|------|------|
| `auto_deploy.sh` | The deploy — fetch → rsync → optional steps → health → notifications |
| `rollback.sh` | Roll back to previous commit + optional DB restore |
| `doctor.sh` | Preflight check — diagnose server environment, config, tools, and permissions |
| `setup.sh` | Beginner YES/NO wizard → creates config.sh (auto-runs keygen at end) |
| `setup-quick.sh` | Paste `KEY=VALUE` lines, Ctrl+D → config.sh |
| `keygen.sh` | SSH key (one pair, both ways) + 3 GitHub copy-paste blocks |
| `detect.sh` | Reads the repo → auto-sets APP_TYPE/BUILD/MIGRATE/RESTART in config.sh |
| `cron.sh` | Install cron job → deploy every N min, 0 GitHub Actions |
| `runner.sh` | Self-hosted runner install (VPS) → ~6s deploys, 0 Actions minutes |
| `webhook.sh` | socat HTTP listener (VPS) → GitHub POST triggers deploy, ~1-2s, secret-verified |
| `quickstart.sh` | **1 command — everything** (setup + keygen + detect + test) |
| `test.sh` | Self-test: syntax + missing-config + full local file:// integration |

## Config key categories (grep `reference_config.md` for full detail)

- **Required:** `REPO_URL`, `APP_DIR`
- **Server:** SERVER_USER, SERVER_HOST, SSH_PORT
- **App/Stack:** APP_TYPE, PYTHON_BIN, NODE_BIN, BUILD_CMD, MIGRATE_CMD, RESTART_METHOD, SERVICE_NAME, PM2_APP, SUPERVISOR_APP, WSGI_FILE, DOCKER_COMPOSE, PHP_FPM_SERVICE, APP_SUBDIR, HEALTH_URL, HEALTH_WAIT, HEALTH_RETRY, AUTO_ROLLBACK_ON_FAIL
- **DB:** DB_BACKUP, DB_BACKUP_KEEP, DB_TYPE, DB_HOST, DB_USER, DB_PASS, DB_NAME
- **Notify:** TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, DISCORD_WEBHOOK_URL, SLACK_WEBHOOK_URL, ALERT_EMAIL
- **Webhook (VPS):** DEPLOY_WEBHOOK_SECRET, WEBHOOK_PORT
- **Git/Advanced:** DEPLOY_KEY, WORKSPACE_BASE, TOGGLE_FLAG, SKIP_WHEN_FLAG, DEFAULT_BRANCH, LOG_FILE, RSYNC_EXCLUDES

## Key design decisions (expensive to rediscover)

- **Fire-and-forget:** GitHub Actions ~6s run → server deploys via nohup → result via Telegram
- **curl `-m 15`** timeout on health + telegram — never hangs
- **Restart methods:** passenger | touch | systemctl | pm2 | supervisor | docker | php | none — all non-fatal (`|| true`)
- **DB backup:** mysql (single-transaction) + postgres + sqlite (file copy); keeps `DB_BACKUP_KEEP` (default 7)
- **TOGGLE_FLAG/SKIP_WHEN_FLAG:** GitHub-vs-cron toggle (flag present + SKIP_WHEN_FLAG set → skip)
- **SHA skip:** `.deployed_sha` — same SHA = no deploy (idle runs instant)
- **Deploy lock:** mkdir+pid at `$WORKSPACE_BASE/.deploy-lock` — concurrent runs skip, stale auto-cleaned
- **Build/migrate failure → abort + Telegram fail alert** — never silently deploy broken code
- **Log rotation:** 1 MB → `$LOG.1`
- **Workspace per branch:** `WORKSPACE_BASE/<branch>` — holds git history (rollback needs old SHAs); cloned `--single-branch` (min network/disk)
- **APP_SUBDIR** (monorepos): deploy only that subfolder; missing → abort before touching app dir
- **RSYNC_EXCLUDES:** extra excludes (space-separated) added to defaults; used by auto_deploy + rollback

## Setup methods (all kept)

- `setup.sh` — YES/NO wizard (Enter = recommended; restart auto-set from APP_TYPE; auto-runs keygen)
- `setup-quick.sh` — paste `KEY=VALUE`, Ctrl+D (parses ALL advanced keys)
- manual — `cp config.example.sh config.sh && nano config.sh`

## When you change something — files to touch

| Change | Also update |
|--------|-------------|
| A config key | config.example.sh + setup.sh + setup-quick.sh + README table + reference_config.md |
| A script | run test.sh (covers syntax + integration) |
| Workflow YAML | the `.example` file + reference_deploy_flow.md |
| README.md | AGENTS.md file structure (keep file counts in sync) |
| Behavior/flow | reference_deploy_flow.md + MEMORY.md history |
| test.sh | .github/workflows/test.yml (CI name mentions check count) |

## History (latest first)

- **Doctor & Multi-Channel Alerts (NEW):** Added `doctor.sh` preflight system diagnostic check. Added multi-channel notification support in `auto_deploy.sh` and `rollback.sh` (Telegram, Discord webhook, Slack webhook, and Email alerts). Enhanced notifications with commit author, commit message, and deploy duration timer. Added `AUTO_ROLLBACK_ON_FAIL` auto-rollback if health check fails. Test suite upgraded to 43 checks.
- **Resource principle:** runner trigger only, server all work; `--single-branch` clone; documented in AGENTS.md + README + references
- **Trigger choice:** hosted / self-hosted (`runner.sh`) / webhook (`webhook.sh`) / cron — README "Choose your trigger" table
- **Webhook mode (NEW):** `webhook.sh` (socat HTTP listener, VPS only, start/stop/status) + `deploy-webhook.yml.example` + `DEPLOY_WEBHOOK_SECRET`/`WEBHOOK_PORT` keys — ~1-2s deploys, 0 Actions minutes. Supports BOTH native GitHub webhook (Settings → Webhooks, HMAC `X-Hub-Signature-256` verified, branch from `refs/heads/...`) AND custom `X-Deploy-Secret` header. Native = 0 runner at all.
- **Resource budget (MAIN GOAL):** documented in AGENTS.md + README + MEMORY — GitHub budget (hosted ~1min, webhook/cron/self-hosted 0) + server budget (single-branch, SHA-skip, log rotation, DB_BACKUP_KEEP, lock). Never add deploy work to a workflow.
- **Confusion cleanup:** workflow .example headers now say WHO should use each (deploy.yml = default/all, deploy-selfhosted = only if runner.sh, deploy-webhook = only if webhook.sh). README Step 5 "which workflow to copy?" table. Health check now retries (`HEALTH_RETRY`, default 3) — app boot time tolerant.
- **Runner-lite:** paths-ignore `docs/**`, `permissions: {}`, CI installs rsync only if missing
- **Fully dynamic:** `detect.sh` auto-detects stack; `HEALTH_WAIT` key; zero hardcoded values
- **Zero-Actions:** `cron.sh`; `DB_BACKUP_KEEP`
- **STANDALONE:** fully its own project, sync = push to main only
- **Better+lite:** deploy lock, build/migrate abort, log rotation, paths-ignore `*.md`
- **All-stacks:** pm2/supervisor, SERVICE_NAME, APP_SUBDIR, sqlite, 9 app types
- **Beginner:** YES/NO wizard, `keygen.sh`
- **LITE workflow:** no checkout/build, 1 tiny SSH job
- **test.sh:** self-test (37 checks)
- **RSYNC_EXCLUDES** config key; setup-quick parses all keys
- **Robustness:** git-failure guard, rollback rebuild, postgres prune
- **Dynamic config:** TOGGLE_FLAG, DEFAULT_BRANCH, LOG_FILE — 0 hardcoded paths
- v1: generic auto_deploy + rollback + config.example (git → rsync → optional steps)

## Troubleshooting quick

- `config.sh not found` → copy example first
- Health FAILED but deploy OK → site may need restart; run rollback.sh
- No new commit → `.deployed_sha` match, skip (normal)
- config.sh already exists → `rm config.sh` then re-run setup
- "Branch not found on remote" → wrong branch or clone/fetch failed
- Rsync didn't pick up a change → same size + same mtime (same-second pushes) — rsync quick-check limit, re-push

## CURRENT STATUS (2026-08-29)

- Standalone repo pushed to origin/main ✅ — public-ready, zero related-project references anywhere (files, git history, refs)
- Server `~/deploy-kit/`: manual copy still pending (user's job) + first live test
- BUGFIX (auto-rollback loop): after AUTO_ROLLBACK_ON_FAIL, `.deployed_sha` is set back to the broken NEW_SHA (not PREV_SHA) so cron/Actions don't re-deploy the broken commit on every trigger (was an infinite loop). rollback.sh skips its own notify when called via ROLLBACK_AUTO=1 (no double alert).
- Quickstart pass: quickstart.sh (1 command: setup+keygen+detect+test), README top Quickstart section + Worked Example (generic), reference_deploy_flow now documents quickstart + doctor.sh. Goal: minimum reading for setup.
- **SERVER_DEPLOY_PATH (LQP lesson):** workflow had hardcoded `~/deploy-kit/auto_deploy.sh` → silent "No such file or directory" on servers where kit lives elsewhere. Now a GitHub Secret (`SERVER_DEPLOY_PATH`, optional; default `~/deploy-kit/auto_deploy.sh`). Used by deploy.yml + deploy-selfhosted.yml. Keygen prints 5 secrets now. **Gotcha:** in deploy.yml (hosted runner → SSH) the default MUST be `~/deploy-kit/auto_deploy.sh` (tilde → expanded by the remote shell). Never use `$HOME` there — that is the GitHub runner's home, wrong on the server. Self-hosted keeps `$HOME` (runner IS on the server).
- **Secret count:** 5 (SSH_PRIVATE_KEY, SERVER_HOST, SERVER_USER, SSH_PORT, SERVER_DEPLOY_PATH) — keep in sync across README/keygen/reference.
- **KIT_SELF_UPDATE (LQP self-update lesson):** optional config key — `yes` → auto_deploy pulls latest kit scripts from its own git repo (if `$SCRIPT_DIR/.git` exists). config.sh is gitignored so it is never touched; pull failure is non-fatal. LQP's self-update was copying to the wrong path (~/auto_deploy.sh instead of the actual trigger script) — deploy-kit avoids this by pulling in SCRIPT_DIR itself.
