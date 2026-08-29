# Deploy Kit — reference_deploy_flow.md

> Full deploy flow, toggle, rollback, GitHub Actions wiring, troubleshooting. Read on demand.

## How a deploy happens (end to end)

```
git push (any branch)
  → GitHub Actions workflow (deploy.yml.example) triggers (~6s)
      - no checkout, no Docker — direct ssh fire-and-forget:
        ssh user@server "nohup /bin/bash ~/deploy-kit/auto_deploy.sh <branch> &"
  → server: auto_deploy.sh <branch> runs in background (nohup)
  → git fetch workspace → rsync to APP_DIR → optional steps → health → Telegram
```

## auto_deploy.sh steps (numbered)

0. **Flag check** — if `TOGGLE_FLAG` file exists AND `SKIP_WHEN_FLAG` set → exit 0 (toggle mode)
1. **Workspace** — clone if missing, else `git fetch origin <branch>`; `reset --hard origin/<branch>`
2. **SHA skip** — compare `.deployed_sha`; same SHA → exit 0 (no work)
3. **Rsync** — `-az --delete` with excludes: `.git/`, `.env`, `*.db`, `*.sqlite3`, `__pycache__/`, `*.pyc`, `node_modules/`, `venv/`, `.venv/`, `*.log`, `media/`, `backups/`, `tests/`
4. **Build** — if `BUILD_CMD` set → run in APP_DIR
5. **DB backup** — if `DB_BACKUP=yes` + DB_* set → mysqldump/pg_dump to `$APP_DIR/backups/predeploy/`, keep 7
6. **Migrate** — if `MIGRATE_CMD` set → run in APP_DIR
7. **Restart** — per `RESTART_METHOD` (passenger → touch tmp/restart.txt; systemctl → restart $SITE_DOMAIN; docker → compose down/up; php → reload fpm; none/"" → skip)
8. **Record SHA** — write `.deployed_sha` in workspace
9. **Health check** — sleep 8 → `curl -m 15 HEALTH_URL` (or `https://$SITE_DOMAIN/`); OK → success alert, fail → warning alert
10. **Telegram** — start/success/fail alerts via `notify()` (only if token+chat set)

## Rollback (rollback.sh)

```
/bin/bash rollback.sh <branch> [commit-sha]
```
- No sha → uses last deployed SHA from `.deployed_sha`
- Fetches, checks out target SHA, rsyncs to APP_DIR
- Restores latest pre-migration dump if DB_* set and dump exists
- Restarts per RESTART_METHOD

## Toggle (GitHub vs Cron) — optional

- `TOGGLE_FLAG=""` → no toggle, always deploys
- `TOGGLE_FLAG=/path/flag` + `SKIP_WHEN_FLAG=1` → flag present = skip (e.g. cron disabled when GitHub active)
- Example: cron runs every 2 min; GitHub Runner active → user touches flag → cron skips

## GitHub Actions wiring (deploy.yml.example)

- Triggers on push to configured branches; `paths-ignore` for md/docs
- `concurrency` group — overlapping runs cancel (save minutes)
- No checkout (fastest); SSH with private key from secrets; `BatchMode=yes`; `ConnectTimeout=10`
- Fire-and-forget: `nohup ... &` — run completes in ~6s, deploy continues on server
- GitHub Secrets needed: `SERVER_IP`, `SERVER_USER`, `SSH_PORT`, `SSH_PRIVATE_KEY`

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `config.sh not found` | Config missing | `cp config.example.sh config.sh` |
| Health FAILED | App down after deploy | Check log, run `rollback.sh`, check restart method |
| No new commit — skip | `.deployed_sha` same | Normal — no changes on branch |
| Deploy started but no Telegram | Token/chat empty | Set `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` |
| `config.sh already exists` | Re-running setup | `rm config.sh` first |
| Deploy slow/hang | curl without timeout | Health check uses `-m 15` — shouldn't hang |
