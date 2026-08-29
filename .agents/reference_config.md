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
| `DB_TYPE` | mysql \| postgres \| sqlite | `mysql` |
| `DB_HOST` | DB host (not for sqlite) | `localhost` |
| `DB_USER` / `DB_PASS` | DB credentials (not for sqlite) | — |
| `DB_NAME` | DB name (sqlite: file path inside APP_DIR) | `myapp_db` |

Backup behavior: dumps to `$APP_DIR/backups/predeploy/`, keeps last 7, `--single-transaction` for mysql. sqlite = copy of the `.db` file.

## Notifications (optional)
| Key | What |
|-----|------|
| `TELEGRAM_BOT_TOKEN` | @BotFather token — `""` = no alerts |
| `TELEGRAM_CHAT_ID` | Chat ID — `""` = no alerts |

## Health check (optional)
| Key | What |
|-----|------|
| `HEALTH_URL` | Full URL to check after deploy — `""` = skip. Default fallback `https://$SITE_DOMAIN/`. Uses `curl -m 15` (never hangs). |

## Git / Advanced (optional)
| Key | What | Default |
|-----|------|---------|
| `DEPLOY_KEY` | Path to SSH deploy key — `""` = default ssh. **Run `keygen.sh` to create it + get GitHub copy-paste blocks** | `~/.ssh/deploy_key` |
| `WORKSPACE_BASE` | Clone workspace base | `/home/$USER/deploy-workspace` |
| `TOGGLE_FLAG` | Flag path for toggle system | `/home/$USER/.deploy_github` |
| `SKIP_WHEN_FLAG` | If set + flag exists → deploy skipped | `""` |
| `DEFAULT_BRANCH` | Branch when none passed (auto_deploy + rollback) | `main` |
| `LOG_FILE` | Log path | `/home/$USER/deploy.log` |
| `RSYNC_EXCLUDES` | Extra rsync excludes, space-separated (added to defaults) | `""` |

## Golden rule
**Golden rule: if your project doesn't have something → leave it `""` — the script skips it automatically. Only `REPO_URL` + `APP_DIR` are required.**
