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
- **Restart methods**: passenger (touch tmp/restart.txt) | touch | systemctl | docker | php | none/"" (skip)
- **DB backup**: `DB_BACKUP=yes` + DB_* set; keeps last 7 dumps; mysql + postgres supported
- **TOGGLE_FLAG/SKIP_WHEN_FLAG**: optional GitHub-vs-cron toggle (flag present + SKIP_WHEN_FLAG set → skip deploy)
- **SHA-based skip**: `.deployed_sha` — no new commit = no deploy (idle runs are instant)
- **Log rotation**: no — but LOG_FILE configurable (default `/home/$USER/deploy.log`)
- **Workspace clone** per branch: `WORKSPACE_BASE/<branch>` holds git history (rollback needs old SHAs)

## 3 setup methods (all kept)
- `setup.sh` — interactive Q&A (16 questions, hints, Enter=default)
- `setup-quick.sh` — paste `KEY=VALUE` lines, Ctrl+D → config.sh (validates APP_DIR+REPO_URL)
- manual — `cp config.example.sh config.sh && nano config.sh`

## Sync strategy (CRITICAL — 3 locations)
1. Standalone repo: `/run/media/ghazi/Data/coding/projects/deploy-kit` → `git@github.com:Gaazi/deploy-kit.git` (branch main, PRIVATE)
2. related repo folder `deploy-kit/` — work on `deploy` branch first, then sync to `dev`
3. User's server `~/deploy-kit/` (manual copy)
Any change → ALL 3. Verify with `diff -q`.

## History
- v1: generic auto_deploy.sh + rollback.sh + config.example.sh (git → rsync → optional steps)
- setup.sh interactive (16 Q&A) added — standalone repo created (PRIVATE)
- Fully dynamic config: TOGGLE_FLAG, DEFAULT_BRANCH, LOG_FILE — 0 hardcoded paths
- Everything-optional pass: only REPO_URL+APP_DIR required, HEALTH_URL config, curl -m timeout, restart/health skip when empty
- README "WHERE TO PUT WHAT" full table + setup.sh per-question hints
- Full English translation (all docs + script comments + prompts)
- setup-quick.sh (paste method) added — 3 setup methods total

## Troubleshooting quick
- `config.sh not found` → copy example first
- Health FAILED but deploy OK → site may need restart; run rollback.sh
- No new commit → `.deployed_sha` match, skip (normal)
- config.sh already exists → `rm config.sh` then re-run setup
