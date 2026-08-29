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

## 📁 Files (12 + .agents/)

| File | What it does |
|------|---------------|
| `config.example.sh` | **Settings template** — create `config.sh` and fill in your values |
| `setup.sh` | **Beginner setup wizard** — YES/NO questions, press Enter for recommended, creates config.sh itself |
| `setup-quick.sh` | **Paste setup** — paste all your values at once, no questions |
| `keygen.sh` | **SSH key helper** — creates the key + prints 3 ready-to-copy blocks for GitHub (~2 min) |
| `cron.sh` | **Zero GitHub Actions** — one command installs a cron job: deploy every N min, 0 Actions minutes |
| `auto_deploy.sh` | Deploy script — git → rsync → build → backup → migrate → restart → health → telegram |
| `rollback.sh` | Go back to the previous commit + DB restore |
| `test.sh` | **Self-test** — syntax check + full local deploy/rollback test (no network) |
| `.github/workflows/deploy.yml.example` | GitHub Actions trigger (fire-and-forget ~6s) |
| `README.md` | This guide |
| `AGENTS.md` + `.agents/` | Agent rules + memory (for AI agents / future developers) |
| `LICENSE` | MIT License — for a public repo |
| `.gitignore` | So `config.sh` / secrets are never committed |

---

## 🚀 Setup — Step by Step (5 min)

### Step 1: Put the kit on the server

```bash
# Option A — copy the files (FTP / file manager) into ~/deploy-kit/ ...
mkdir -p ~/deploy-kit

# Option B — download directly on the server (once the kit repo is public/forked):
cd ~/deploy-kit
for f in auto_deploy.sh rollback.sh setup.sh setup-quick.sh keygen.sh config.example.sh test.sh; do
  curl -fsSL -o "$f" "https://raw.githubusercontent.com/YOUR_USER/deploy-kit/main/$f"
done
chmod +x *.sh
```

### Step 2: Create the config (most important)

**3 ways:**

```bash
# Method A — Beginner Wizard (YES/NO questions, Enter = recommended, best for beginners):
/bin/bash setup.sh
#   → at the end it asks: "Set up SSH keys now?" → say yes → keygen.sh runs automatically

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
| `APP_TYPE` | Your stack | python/node/php/wordpress/ruby/java/go/static/docker | `python` |
| `PYTHON_BIN` | Python path on the server (virtualenv) | Python binary | `/home/cpuser/virtualenv/myapp/3.11/bin/python` |
| `BUILD_CMD` | Build command (Node/static) | Or leave empty `""` | `npm run build` |
| `MIGRATE_CMD` | DB migration command | Or leave empty `""` | `$PYTHON_BIN -m alembic upgrade head` |
| `RESTART_METHOD` | How the app restarts | passenger/touch/systemctl/pm2/supervisor/docker/php/none | `passenger` |
| `SERVICE_NAME` | systemctl: service name | `""` = uses `SITE_DOMAIN` | `myapp.service` |
| `PM2_APP` | pm2: app name (Node on VPS) | `all` restarts everything | `myapp` |
| `SUPERVISOR_APP` | supervisor: app name (VPS) | `all` | `myapp` |
| `WSGI_FILE` | The Passenger one (Python) | WSGI file | `passenger_wsgi.py` |
| `DOCKER_COMPOSE` | Docker project | Compose file path | `docker-compose.yml` |
| `PHP_FPM_SERVICE` | PHP project | php-fpm service name | `php8.2-fpm` |
| `APP_SUBDIR` | Monorepo: deploy only this subfolder | `""` = whole repo | `web/` |
| `DB_BACKUP` | Want a DB backup? | yes/no | `yes` |
| `DB_BACKUP_KEEP` | How many old dumps to keep (lighter disk = smaller) | Number | `7` |
| `DB_TYPE` / `DB_HOST` / `DB_USER` / `DB_PASS` / `DB_NAME` | Server DB panel (sqlite: `DB_NAME` = file path in app folder) | DB details | `mysql` / `localhost` / user / pass / name |
| `TELEGRAM_BOT_TOKEN` | From @BotFather (optional) | Token | `123:ABC...` |
| `TELEGRAM_CHAT_ID` | Message from the bot on Telegram (optional) | Chat ID | `-100123...` |
| `HEALTH_URL` | Health check URL (optional) | Full URL | `https://myapp.com/health` |
| `DEPLOY_KEY` | Path to the GitHub deploy key | Key file | `/home/cpuser/.ssh/deploy_key` |
| `TOGGLE_FLAG` / `SKIP_WHEN_FLAG` | Toggle system (optional) | Flag path + `1` | — |
| `DEFAULT_BRANCH` | Default deploy branch | Branch | `main` |
| `LOG_FILE` | Where to log | Path | `/home/cpuser/deploy.log` |
| `RSYNC_EXCLUDES` | Extra rsync excludes (space-separated) | `uploads/` | — |

**Rule:** Anything that is **not** in your project → leave it as `""` (empty). The script will skip it automatically.
**Only 2 are required:** `REPO_URL` + `APP_DIR`. Everything else is **optional** — backup, build, migrate, restart, health check, Telegram, toggle — whatever is empty gets skipped.

#### 🧰 Every stack — what to put in config (cheat sheet)

| Stack | `BUILD_CMD` | `MIGRATE_CMD` | `RESTART_METHOD` |
|-------|------------|--------------|------------------|
| **Python** (Django/Flask/FastAPI) | `pip install -r requirements.txt` (optional) | `$PYTHON_BIN -m alembic upgrade head` | `passenger` (cPanel) |
| **Node** (Express/Nest/Nuxt/Next) | `npm install && npm run build` | — | `passenger` (cPanel) / `pm2` (VPS) |
| **PHP** (Laravel/CodeIgniter) | `composer install --no-dev` (optional) | `php artisan migrate` (optional) | `php` (or `none`) |
| **WordPress** | — (wp-content only via `APP_SUBDIR` if monorepo) | — | `php` (or `none`) |
| **Ruby on Rails** | `bundle install` | `bundle exec rails db:migrate` | `passenger` |
| **Java** (Spring Boot) | `mvn package -DskipTests` (then run the jar) | — | `systemctl` |
| **Go** | `go build -o app .` | — | `systemctl` |
| **Docker** (any) | — (compose builds it) | — | `docker` |
| **Static HTML / SPA** | `npm run build` (if SPA) | — | `none` |

> `BUILD_CMD` runs before the app starts — anything can go there (deps install, compile, collectstatic...).
> Monorepo? Set `APP_SUBDIR="web/"` to deploy only that folder. Database SQLite? `DB_TYPE=sqlite` + `DB_NAME=path/to/app.db`.

### Step 3: Permissions + Test

```bash
chmod +x auto_deploy.sh rollback.sh test.sh

# Optional — verify the kit itself (syntax + full local deploy test, no network):
/bin/bash test.sh

# Manual test (first time — confirm everything works):
/bin/bash auto_deploy.sh main
```

**If the manual deploy works → do the GitHub setup.**

### Step 4: SSH keys (1 command — copy-paste ready)

```bash
# On the server, inside ~/deploy-kit/:
/bin/bash keygen.sh
```

It creates the SSH key, sets `DEPLOY_KEY` in `config.sh`, and prints **3 copy-paste blocks**:

1. **Public key** → GitHub repo → **Settings → Deploy keys → Add deploy key** (title: `deploy-kit`)
2. **Private key** → GitHub repo → **Settings → Secrets → Actions → New repository secret** → name `SSH_PRIVATE_KEY`, paste everything from `-----BEGIN` to `-----END`
3. **`SERVER_HOST` / `SERVER_USER` / `SSH_PORT`** → same Secrets page, 3 more secrets (values from your config)

That's it — one key pair works both ways (server → GitHub clone + GitHub → server trigger). For each new repo, repeat only block 1.

### Step 5: GitHub Actions setup

```bash
# In your project repo:
mkdir -p .github/workflows
cp ~/deploy-kit/.github/workflows/deploy.yml.example .github/workflows/deploy.yml
```

Edit your **branch names** in `deploy.yml` (default: dev/demo/main).

### Step 6: Push it 🎉

```
Push (dev/demo/main) → GitHub Actions (~6s) → server deploy → Telegram alert
```

---

## ⚡ GitHub free limits — never run out

GitHub **free plan** gives you **2,000 Actions minutes / month**. Each deploy costs ~1 min
(VM boot + the ~6s job). So Actions mode handles roughly **2,000 deploys/month** — enough for
most projects. Doc-only pushes cost **0** (the workflow ignores `*.md`).

**Want to use ZERO Actions minutes?** Use the cron mode instead — the server checks the repo
itself every few minutes and deploys when there's a new commit:

```bash
# On the server, inside ~/deploy-kit/:
/bin/bash cron.sh 2            # deploy every 2 minutes, 0 GitHub Actions
/bin/bash cron.sh 5            # ... or every 5 minutes
```

- No new commit → instant skip (SHA check) — idle checks cost nothing
- Build / DB backup / migrate / restart / health / Telegram all work the same
- Free plan = **unlimited cron** — the limit can never run out
- Not on a VPS? cPanel users: `cron.sh` prints the exact line for **cPanel → Cron Jobs**

> **Toggle:** running both? `touch ~/.deploy_github` + `SKIP_WHEN_FLAG=1` → cron skips
> and GitHub Actions takes over. Remove the flag → cron deploys again.

---

## 🎛️ auto_deploy.sh — deploy flow (every step)

| Step | What | When |
|------|-----|-----|
| 1 | Load `config.sh` | Always |
| 2 | Check GitHub-mode flag (`~/.deploy_github`) | If the flag is set up |
| 3 | **Deploy lock** (concurrent pushes can't clash; stale lock auto-cleaned) | Always |
| 4 | Git clone/fetch workspace | First time / every push |
| 5 | Check for new commit (same SHA = skip) | Every push |
| 6 | Rsync files → app dir (excludes .env/db/media; `APP_SUBDIR` = subfolder) | Every deploy |
| 7 | Build (if `BUILD_CMD` is set — **failure aborts the deploy**) | According to config |
| 8 | DB backup (if `DB_BACKUP=yes`) | Before migrate |
| 9 | Migrate (if `MIGRATE_CMD` is set — **failure aborts**) | Every deploy |
| 10 | Restart (`RESTART_METHOD`) | Every deploy |
| 11 | Record deployed SHA | Every deploy |
| 12 | Health check (is the site live?) | Every deploy |
| 13 | Telegram alert (start/success/fail) | If a token exists |

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
| "Another deploy is running" | Two pushes at once | Normal — the running deploy picks up the latest commit |
| "Build FAILED" / "Migrate FAILED" | Build/migrate command error | Check the log, fix, push again; run `rollback.sh` if the site broke |

---

## 🛡️ Safety Notes

- **Never commit `config.sh`** — it's in `.gitignore`, but still be careful
- Never **share `SSH_PRIVATE_KEY`** with anyone
- Everything is optional — whatever is empty in the config gets skipped. Only `REPO_URL` + `APP_DIR` are required
- It's better to keep DB backup `yes` on production (safe deploy)

---

## ✅ Checklist (for completing the setup)

- [ ] `~/deploy-kit/` on the server (8 files)
- [ ] Created `config.sh` (wizard: `/bin/bash setup.sh`)
- [ ] `chmod +x auto_deploy.sh rollback.sh test.sh keygen.sh`
- [ ] SSH keys + copy-paste: `/bin/bash keygen.sh` ✅
- [ ] GitHub Deploy key added (keygen block 1)
- [ ] GitHub Secrets (4) added (keygen blocks 2 + 3)
- [ ] `.github/workflows/deploy.yml` in your repo
- [ ] Manual test: `/bin/bash auto_deploy.sh main` ✅
- [ ] Push → Actions run ✅ → Telegram alert ✅

---

**This kit is public-ready. None of your data/secrets. Anyone can take any project and run it.**
