# Deploy Kit — Generic Auto-Deployment Kit

> **Auto-deploy any project (Python / Node / PHP / Static) on a GitHub push.**
> This kit is **public-ready** — no secrets/data, everything is placeholder. Anyone can take it, fill in their own config, and run it.

---

## 📌 What this kit does

```
GitHub push (dev/demo/main)
   → GitHub Actions trigger (~6s, fire-and-forget)
   → On the server: auto_deploy.sh <branch>
   → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → health check → [Telegram]
   → Site live
```

**Fire-and-forget:** The GitHub run completes in ~6s. The deploy runs in the background on the server. You get the result via a **Telegram alert**.

---

## 📁 Files (7 + .agents/)

| File | What it does |
|------|---------------|
| `config.example.sh` | **Settings template** — create `config.sh` and fill in your values |
| `setup.sh` | **Interactive setup** — creates config.sh itself through questions & answers |
| `setup-quick.sh` | **Paste setup** — paste all your values at once, no questions |
| `auto_deploy.sh` | Deploy script — git → rsync → build → backup → migrate → restart → health → telegram |
| `rollback.sh` | Go back to the previous commit + DB restore |
| `.github/workflows/deploy.yml.example` | GitHub Actions trigger (fire-and-forget ~6s) |
| `README.md` | This guide |
| `AGENTS.md` + `.agents/` | Agent rules + memory (for AI agents / future developers) |
| `LICENSE` | MIT License — for a public repo |
| `.gitignore` | So `config.sh` / secrets are never committed |

---

## 🚀 Setup — Step by Step (5 min)

### Step 1: Put the kit on the server

```bash
# Create a folder on the server and copy the kit files into it:
mkdir -p ~/deploy-kit
# ... copy the 6 files of this folder into ~/deploy-kit/ ...
# (or: git clone your-repo → the deploy-kit/ folder already exists)

cd ~/deploy-kit
```

### Step 2: Create the config (most important)

**3 ways:**

```bash
# Method A — Interactive (setup.sh — questions & answers, creates it itself):
/bin/bash setup.sh

# Method B — Paste (setup-quick.sh — paste all values at once, no questions):
/bin/bash setup-quick.sh
#   → paste KEY=VALUE lines (SERVER_USER=cpuser, REPO_URL=git@..., ...), then Ctrl+D

# Method C — Manual (copy + edit config.example.sh):
cp config.example.sh config.sh
nano config.sh
```

#### 📋 `config.sh` — WHERE TO PUT WHAT (full detail)

| Setting | Where to get it | What to write | Example |
|---------|-------------|---------------|---------|
| `SERVER_USER` | Server panel (cPanel username) | Login user | `cpuser` |
| `SERVER_HOST` | Server IP or domain | Host | `123.45.67.89` or `server.com` |
| `SSH_PORT` | SSH port (cPanel: 22) | Port | `22` |
| `SITE_DOMAIN` | Your live domain | Domain (without https://) | `myapp.com` |
| `APP_DIR` | Full app folder path on the server | App directory | `/home/cpuser/myapp` |
| `REPO_URL` | GitHub repo (Settings → SSH clone) | Repo SSH URL | `git@github.com:user/repo.git` |
| `APP_TYPE` | Your stack | python/node/php/static/docker | `python` |
| `PYTHON_BIN` | Python path on the server (virtualenv) | Python binary | `/home/cpuser/virtualenv/myapp/3.11/bin/python` |
| `BUILD_CMD` | Build command (Node/static) | Or leave empty `""` | `npm run build` |
| `MIGRATE_CMD` | DB migration command | Or leave empty `""` | `$PYTHON_BIN -m alembic upgrade head` |
| `RESTART_METHOD` | How the app restarts | passenger/touch/systemctl/docker/php/none | `passenger` |
| `WSGI_FILE` | The Passenger one (Python) | WSGI file | `passenger_wsgi.py` |
| `DOCKER_COMPOSE` | Docker project | Compose file path | `docker-compose.yml` |
| `PHP_FPM_SERVICE` | PHP project | php-fpm service name | `php8.2-fpm` |
| `DB_BACKUP` | Want a DB backup? | yes/no | `yes` |
| `DB_TYPE` / `DB_HOST` / `DB_USER` / `DB_PASS` / `DB_NAME` | Server DB panel | DB details | `mysql` / `localhost` / user / pass / name |
| `TELEGRAM_BOT_TOKEN` | From @BotFather (optional) | Token | `123:ABC...` |
| `TELEGRAM_CHAT_ID` | Message from the bot on Telegram (optional) | Chat ID | `-100123...` |
| `HEALTH_URL` | Health check URL (optional) | Full URL | `https://myapp.com/health` |
| `DEPLOY_KEY` | Path to the GitHub deploy key | Key file | `/home/cpuser/.ssh/deploy_key` |
| `TOGGLE_FLAG` / `SKIP_WHEN_FLAG` | Toggle system (optional) | Flag path + `1` | — |
| `DEFAULT_BRANCH` | Default deploy branch | Branch | `main` |
| `LOG_FILE` | Where to log | Path | `/home/cpuser/deploy.log` |

**Rule:** Anything that is **not** in your project → leave it as `""` (empty). The script will skip it automatically.
**Only 2 are required:** `REPO_URL` + `APP_DIR`. Everything else is **optional** — backup, build, migrate, restart, health check, Telegram, toggle — whatever is empty gets skipped.

### Step 3: Permissions + Test

```bash
chmod +x auto_deploy.sh rollback.sh

# Manual test (first time — confirm everything works):
/bin/bash auto_deploy.sh main
```

**If the manual deploy works → do the GitHub setup.**

### Step 4: GitHub Actions setup

```bash
# In your project repo:
mkdir -p .github/workflows
cp ~/deploy-kit/.github/workflows/deploy.yml.example .github/workflows/deploy.yml
```

Edit your **branch names** in `deploy.yml` (default: dev/demo/main).

### Step 5: GitHub Secrets

```
GitHub → Repo → Settings → Secrets and variables → Actions → New repository secret
```

| Secret | Value |
|--------|-------|
| `SSH_PRIVATE_KEY` | The server's **private key** (content of `~/.ssh/id_ed25519` on the server) |
| `SERVER_HOST` | Server IP/domain |
| `SERVER_USER` | Server user |
| `SSH_PORT` | `22` (or custom) |

### Step 6: Push it 🎉

```
Push (dev/demo/main) → GitHub Actions (~6s) → server deploy → Telegram alert
```

---

## 🎛️ auto_deploy.sh — deploy flow (every step)

| Step | What | When |
|------|-----|-----|
| 1 | Load `config.sh` | Always |
| 2 | Check GitHub-mode flag (`~/.deploy_github`) | If the flag is set up |
| 3 | Git clone/fetch workspace | First time / every push |
| 4 | Check for new commit (same SHA = skip) | Every push |
| 5 | Rsync files → app dir (excludes .env/db/media) | Every deploy |
| 6 | Build (if `BUILD_CMD` is set) | According to config |
| 7 | DB backup (if `DB_BACKUP=yes`) | Before migrate |
| 8 | Migrate (if `MIGRATE_CMD` is set) | Every deploy |
| 9 | Restart (`RESTART_METHOD`) | Every deploy |
| 10 | Record deployed SHA | Every deploy |
| 11 | Health check (is the site live?) | Every deploy |
| 12 | Telegram alert (start/success/fail) | If a token exists |

---

## ⏪ Rollback (if something breaks)

```bash
# On the server:
/bin/bash ~/deploy-kit/rollback.sh main              # back to the last SHA
/bin/bash ~/deploy-kit/rollback.sh main <COMMIT_SHA>  # to a specific SHA
```

It automatically: pins → restores the DB dump (if present) → syncs files → restarts.

---

## 🔄 Toggle (GitHub vs Cron — optional)

If you also have a cron deploy:

```bash
touch ~/.deploy_github   # GitHub mode (cron skip)
rm    ~/.deploy_github   # cron mode (GitHub skip)
```

In `auto_deploy.sh`, set `SKIP_WHEN_FLAG=1` and it will skip when the flag is present.

---

## 🔍 Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `config.sh not found` | config wasn't created | `cp config.example.sh config.sh` |
| SSH fail (GitHub) | Wrong secret | Check GitHub Secrets |
| Deployed but site is down | Health check failed | Run `rollback.sh` |
| Deploy skipped ("No new commit") | Same SHA | Make a new push |
| No DB backup | `DB_BACKUP` is no or DB_* is empty | Check the config |

---

## 🛡️ Safety Notes

- **Never commit `config.sh`** — it's in `.gitignore`, but still be careful
- Never **share `SSH_PRIVATE_KEY`** with anyone
- Everything is optional — whatever is empty in the config gets skipped. Only `REPO_URL` + `APP_DIR` are required
- It's better to keep DB backup `yes` on production (safe deploy)

---

## ✅ Checklist (for completing the setup)

- [ ] `~/deploy-kit/` on the server (7 files)
- [ ] Created `config.sh` + your values
- [ ] `chmod +x auto_deploy.sh rollback.sh`
- [ ] Manual test: `/bin/bash auto_deploy.sh main` ✅
- [ ] `.github/workflows/deploy.yml` in your repo
- [ ] GitHub Secrets (4) set
- [ ] Push → Actions run ✅ → Telegram alert ✅

---

**This kit is public-ready. None of your data/secrets. Anyone can take any project and run it.**
