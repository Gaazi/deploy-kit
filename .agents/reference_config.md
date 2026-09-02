# Deploy Kit — reference_config.md

> Every config key in `config.sh` explained. Read on demand when working on config/scripts.

## Required (script errors if missing)
| Key | What | Example |
|-----|------|---------|
| `REPO_URL` | Git repo SSH URL (GitHub → Code → SSH) | `git@github.com:user/repo.git` |
| `APP_DIR` | Full app folder path on server | `/home/cpuser/myapp` |

## Server / SSH
| Key | What | Default |
|-----|------|---------|
| `SERVER_USER` | Server login user (cPanel username) | `cpuser` |
| `SERVER_HOST` | Server IP or domain | `your-server.com` |
| `SSH_PORT` | SSH port | `22` |

## Site / App
| Key | What | Example |
|-----|------|---------|
| `SITE_DOMAIN` | Live domain (no https://) | `myapp.com` |
| `APP_TYPE` | python \| node \| php \| wordpress \| ruby \| java \| go \| static \| docker | `python` |
| `PYTHON_BIN` | Python binary (virtualenv) | `/home/cpuser/virtualenv/myapp/3.11/bin/python` |
| `NODE_BIN` | Node binary (node type) | `""` |
| `BUILD_CMD` | Build command (Node/static) — `""` = skip | `npm run build` |
| `MIGRATE_CMD` | Migration command — `""` = skip | `$PYTHON_BIN -m alembic upgrade head` |
| `RESTART_METHOD` | passenger \| touch \| systemctl \| pm2 \| supervisor \| docker \| php \| none/`""` | `passenger` |
| `SERVICE_NAME` | systemctl: service name — `""` = `SITE_DOMAIN` | `myapp.service` |
| `PM2_APP` | pm2: app name — `all` restarts everything (missing pm2 = no crash) | `all` |
| `SUPERVISOR_APP` | supervisor: app name — `all` (missing supervisorctl = no crash) | `all` |
| `WSGI_FILE` | WSGI entry (passenger, Python) | `passenger_wsgi.py` |
| `DOCKER_COMPOSE` | docker-compose path (docker type; `""` = default) | `docker-compose.yml` |
| `PHP_FPM_SERVICE` | php-fpm service name (php type; `""` = skip) | `php8.2-fpm` |
| `APP_SUBDIR` | Monorepo: deploy only this subfolder — `""` = whole repo. Missing subfolder → deploy aborts safely | `web/` |

## Database (optional — used only when DB_BACKUP=yes)
| Key | What | Example |
|-----|------|---------|
| `DB_BACKUP` | yes \| no (backup before migrate) | `yes` |
| `DB_BACKUP_KEEP` | How many old dumps to keep — lighter disk = smaller | `7` |
| `DB_TYPE` | mysql \| postgres \| sqlite | `mysql` |
| `DB_HOST` | DB host (not for sqlite) | `localhost` |
| `DB_USER` / `DB_PASS` | DB credentials (not for sqlite). If empty, auto-read from app's `.env` DATABASE_URL (mysql://user:pass@host/db) so the password isn't duplicated | — |
| `DB_NAME` | DB name (sqlite: file path inside APP_DIR) | `myapp_db` |

Backup behavior: dumps to `$WORKSPACE_BASE/backups/<branch>/` (OUTSIDE the app dir — web-safe), keeps `DB_BACKUP_KEEP` fresh (default 7) + older dumps are gzip-COMPRESSED, never deleted (archive also capped at DB_BACKUP_KEEP; oldest compressed removed only when 21+ already archived). sqlite = copy of the `.db` file.

Backup verification: every dump is validated (non-empty + correct signature — `MySQL dump` / `PostgreSQL database dump` / `SQLite format 3`). If the backup is empty/invalid AND `MIGRATE_CMD` is set, the deploy ABORTS before migrating (a failed migration with a broken backup would make rollback impossible = data loss). Without a migration, it warns and continues.

## Notifications (optional — multi-channel alerts)
| Key | What |
|-----|------|
| `TELEGRAM_BOT_TOKEN` | @BotFather token — `""` = no alerts. If empty, auto-read from app's `.env` (same variable name) |
| `TELEGRAM_CHAT_ID` | Chat ID — `""` = no alerts. If empty, auto-read from app's `.env` |
| `DISCORD_WEBHOOK_URL` | Discord webhook URL — `""` = no alerts. If empty, auto-read from app's `.env` |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL — `""` = no alerts. If empty, auto-read from app's `.env` |
| `ALERT_EMAIL` | Email address for alerts (uses `mail`/`sendmail`) — `""` = no alerts |

## Webhook trigger (optional, VPS only)
| Key | What | Default |
|-----|------|---------|
| `DEPLOY_WEBHOOK_SECRET` | Random string — must match GitHub secret `DEPLOY_WEBHOOK_SECRET`; `""` = webhook disabled | `""` |
| `WEBHOOK_PORT` | Port the socat listener binds to | `9000` |

Webhook listener: `webhook.sh start|stop|status`. Needs socat (VPS only).

## Health check & Safety (optional)
| Key | What |
|-----|------|
| `HEALTH_URL` | Full URL to check after deploy — `""` = skip. Default fallback `https://$SITE_DOMAIN/`. Uses `curl -m 15` (never hangs). |
| `HEALTH_WAIT` | Seconds to sleep after restart before checking — `""` = 8. |
| `HEALTH_RETRY` | How many times to retry health check (app may need a moment) — `""` = 3. |
| `AUTO_ROLLBACK_ON_FAIL` | `yes` \| `no` — automatically rollback to previous working commit if health check fails |
| `RESTORE_ON_FAIL` | `yes` → if migration FAILS, auto-restore DB from THIS deploy's verified backup (never stale backups; no backup = alert only, never touches DB) | `no` |

## Git / Advanced (optional)
| Key | What | Default |
|-----|------|---------|
| `DEPLOY_KEY` | Path to SSH deploy key — `""` = default ssh. **Run `keygen.sh` to create it + get GitHub copy-paste blocks** | `~/.ssh/deploy_key` |
| `WORKSPACE_BASE` | Clone workspace base | `/home/$USER/deploy-workspace` |
| `TOGGLE_FLAG` | Flag path for toggle system (affects cron deploys only) | `/home/$USER/.deploy_github` |
| `SKIP_WHEN_FLAG` | If set + flag exists → **cron-fired** deploy skipped (`DEPLOY_TRIGGER=cron`) | `""` |
| `KIT_SELF_UPDATE` | `yes` → auto-pull kit updates from own git repo (if `$SCRIPT_DIR/.git` exists; config.sh gitignored, never touched; failure non-fatal) | `""` |
| `DEFAULT_BRANCH` | Branch when none passed (auto_deploy + rollback) | `main` |
| `LOG_FILE` | Log path | `/home/$USER/deploy.log` |
| `RSYNC_EXCLUDES` | Extra rsync excludes, space-separated (added to defaults) | `""` |

## Golden rule
**Golden rule: if your project doesn't have something → leave it `""` — the script skips it automatically. Only `REPO_URL` + `APP_DIR` are required.**
