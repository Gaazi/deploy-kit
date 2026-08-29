# Deploy Kit — MEMORY.md

> Project knowledge index. Grep for keywords, never read whole file.

## What this is
- Standalone, generic, config-driven auto-deploy kit (public-ready, currently PRIVATE on GitHub)
- For shared hosting (cPanel) / VPS — Python / Node / PHP / static / Docker
- Pure bash + git + rsync + curl — no daemon, no Docker requirement, no root

## Deploy flow (what auto_deploy.sh does)
`git fetch → rsync (excludes) → [build] → [db backup] → [migrate] → [restart] → [health check] → [Telegram]` — `[ ]` = optional, empty config = skip

## Key design decisions (expensive to rediscover — remember these)
- **Everything optional** — only `REPO_URL` + `APP_DIR` required (clear error if missing)
- **Fire-and-forget**: GitHub Actions ~6s run, deploy runs on server via nohup; result via Telegram
- **curl `-m 15`** timeout on health check + telegram — never hangs
- **Restart methods**: passenger (touch tmp/restart.txt) | touch | systemctl (SERVICE_NAME) | pm2 | supervisor | docker | php | none/"" (skip) — all non-fatal (`|| true`)
- **DB backup**: `DB_BACKUP=yes` + DB_* set; keeps last 7; mysql (single-transaction) + postgres + sqlite (file copy)
- **TOGGLE_FLAG/SKIP_WHEN_FLAG**: optional GitHub-vs-cron toggle (flag present + SKIP_WHEN_FLAG set → skip deploy)
- **SHA-based skip**: `.deployed_sha` — no new commit = no deploy (idle runs are instant)
- **Deploy lock**: mkdir+pid at `$WORKSPACE_BASE/.deploy-lock` — concurrent runs skip, stale auto-cleaned; rollback shares it
- **BUILD/MIGRATE failure → abort + Telegram fail alert** (hint rollback) — app dir never half-updated silently
- **Log rotation**: 1 MB cap → `$LOG.1`
- **Workspace clone** per branch: `WORKSPACE_BASE/<branch>` holds git history (rollback needs old SHAs)
- **APP_SUBDIR** (monorepos): deploy only subfolder; missing → abort before touching app dir
- **RSYNC_EXCLUDES**: extra excludes (space-separated) on top of defaults — used by auto_deploy + rollback

## Setup methods (all kept)
- `setup.sh` — beginner YES/NO wizard (Enter = recommended; restart method auto-set from APP_TYPE; auto-runs keygen.sh at end)
- `setup-quick.sh` — paste `KEY=VALUE` lines, Ctrl+D → config.sh (validates APP_DIR+REPO_URL, parses ALL advanced keys)
- manual — `cp config.example.sh config.sh && nano config.sh`

## Self-test (run before committing)
`/bin/bash test.sh` — bash -n + missing-config/required errors + full local file:// integration (deploy → skip → new commit → rollback) + keygen + cron + detect checks. Currently 31 checks.

## Sync strategy (STANDALONE — 2 places only)
1. This repo (branch `main`) — commit + push here
2. User's server `~/deploy-kit/` (manual copy)
Any change → commit + push to `main`. Nothing else to sync — this is a fully standalone kit.

## History
- v1: generic auto_deploy.sh + rollback.sh + config.example.sh (git → rsync → optional steps)
- setup.sh interactive (16 Q&A) added — standalone repo created (PRIVATE)
- Fully dynamic config: TOGGLE_FLAG, DEFAULT_BRANCH, LOG_FILE — 0 hardcoded paths
- Everything-optional pass: only REPO_URL+APP_DIR required, HEALTH_URL config, curl -m timeout, restart/health skip when empty
- README "WHERE TO PUT WHAT" full table + setup.sh per-question hints
- Full English translation (all docs + script comments + prompts)
- setup-quick.sh (paste method) added — 3 setup methods total
- Robustness pass: git-failure guard (abort BEFORE rsync --delete if branch/HEAD unresolved — protects app dir), safety guard in rollback too, `sleep 8` only when health check configured, rollback now rebuilds (BUILD_CMD) + uses same excludes + DEFAULT_BRANCH + logs to LOG_FILE, postgres backups pruned (keep 7) like mysql
- `RSYNC_EXCLUDES` config key added (extra excludes, space-separated) — used by auto_deploy + rollback; setup-quick.sh now parses ALL advanced keys (DEPLOY_KEY, TOGGLE_FLAG, DEFAULT_BRANCH, LOG_FILE, WSGI_FILE, DOCKER_COMPOSE, PHP_FPM_SERVICE, DB_TYPE/DB_HOST/DB_PASS, RSYNC_EXCLUDES...)
- `test.sh` self-test added: bash -n + missing-config/required errors + full local file:// integration test (deploy → skip → new commit → rollback). Run before committing. NOTE: rsync quick-check = size+mtime — test keeps file sizes different between commits to stay deterministic.
- LITE workflow: deploy.yml.example trimmed — no checkout, no build, no echo/rm noise; 1 tiny SSH job (fire-and-forget, ~6s job time). Runner cost = VM boot (~1 min) + 6s per push. Zero-Actions alternative already exists: cron mode (TOGGLE_FLAG/SKIP_WHEN_FLAG).
- Beginner pass: setup.sh rewritten as YES/NO wizard (Enter = recommended; restart method auto-set from APP_TYPE; DB_PASS now asked; auto-runs keygen.sh at the end). NEW keygen.sh — ONE key pair both ways (server→GitHub deploy key + GitHub→server authorized_keys), sets DEPLOY_KEY in config.sh, prints 3 copy-paste blocks (Deploy key, SSH_PRIVATE_KEY, SERVER_HOST/USER/PORT secrets). test.sh now covers keygen too (15 checks).
- All-stacks pass: restart methods +pm2/+supervisor (non-fatal `|| true`), SERVICE_NAME for systemctl (default SITE_DOMAIN), APP_SUBDIR for monorepos (abort if missing), sqlite DB backup/restore (file copy), wizard covers 9 app types (python/node/php/wordpress/ruby/java/go/static/docker) with per-type build/migrate hints; test.sh = 18 checks.
- Better+lite pass: deploy lock (mkdir+pid, stale auto-clean, rollback shares it), BUILD/MIGRATE failure → abort + Telegram fail alert, log rotation at 1MB, workflow paths-ignore for *.md (0 runner time on doc pushes), README server-download one-liner; test.sh = 22 checks.
- STANDALONE (2026-08-29): kit is 100% its own project — no external repo folder, no multi-branch sync. Sync = commit + push to main only.
- Zero-Actions pass: cron.sh (server cron deploy every N min = 0 GitHub Actions minutes; free-plan 2000min/mo never runs out; cPanel fallback prints the Cron Jobs line). DB_BACKUP_KEEP config key (default 7, smaller = lighter disk). README "GitHub free limits" section. test.sh covers cron.sh.
- Fully dynamic pass: detect.sh — clones the workspace, auto-detects app type + build/migrate/restart commands from repo files (package.json, manage.py, Dockerfile, etc.), applies to config.sh on confirmation. HEALTH_WAIT config key replaces hardcoded sleep 8. No hardcoded values left.
- Runner-lite pass: deploy.yml paths-ignore expanded (docs/**), `permissions: {}` (no token), kit's own CI installs rsync only if missing; README free-limits section recommends cron.sh for zero-cost.
- Trigger-choice pass: ALL trigger options kept (user picks) — hosted Actions (~1 min), self-hosted runner (~6s, NEW runner.sh + deploy-selfhosted.yml.example, VPS only), cron (0 Actions), cron. All call the same auto_deploy.sh. README "Choose your deploy trigger" table.

## Troubleshooting quick
- `config.sh not found` → copy example first
- Health FAILED but deploy OK → site may need restart; run rollback.sh
- No new commit → `.deployed_sha` match, skip (normal)
- config.sh already exists → `rm config.sh` then re-run setup
- Deploy aborted "Branch not found on remote" → wrong branch name or clone/fetch failed (git log for details)
- Rsync didn't pick up a change → same file size + same mtime (two pushes within the same second) — standard rsync quick-check limitation, re-push or touch file

## CURRENT STATUS (2026-08-29)
- Standalone repo: pushed to origin/main ✅ — kit is its own standalone project, public-ready
- Server `~/deploy-kit/`: manual copy still pending (user's job) + first live test.
