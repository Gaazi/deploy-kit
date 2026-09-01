# Deploy Kit — Generic Auto-Deployment Kit

> **Auto-deploy any project (Python / Node / PHP / Static) on a GitHub push.**
> This kit is **public-ready** — no secrets/data, everything is placeholder. Anyone can take it, fill in their own config, and run it.

---

## ✨ At a Glance

| | |
|---|---|
| **Stacks** | Python · Node · PHP · WordPress · Ruby · Java · Go · Docker · Static |
| **Hosting** | cPanel (shared) · VPS · Docker |
| **Triggers** | GitHub Actions (hosted/self-hosted) · Webhook · Cron |
| **Resource** | runner = ~6s trigger only · 0-min options (webhook/cron) |
| **Setup** | `quickstart.sh` — 1 command, no reading needed |
| **License** | MIT — free, public-ready |

**Key ideas:** config-driven (1 `config.sh`, everything optional) · server does all the work · free GitHub limits never run out.

---

## ⚡ Quickstart (1 command — no reading needed)

```bash
# On the server, in ~/deploy-kit/:
/bin/bash quickstart.sh
```

This one command does everything:
1. **setup** → creates config.sh (press Enter = recommended)
2. **keygen** → SSH keys + GitHub copy-paste blocks
3. **detect** → detects your project automatically
4. **test** → verifies the kit itself

Then just copy the workflow to GitHub + push. **Done — 5 min.**

> Everything below is detailed — read it only when you need it.

---

## 📌 What this kit does

```
GitHub push (dev/demo/main)
   → GitHub Actions trigger (~6s, fire-and-forget)      ← RUNNER: trigger only
   → On the server: auto_deploy.sh <branch>             ← SERVER: all work here
   → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → health check → [Telegram]
   → Site live
```

**Fire-and-forget:** The GitHub run completes in ~6s. The deploy runs in the background on the server. You get the result via a **Telegram alert**.

## 🖥️ Runner vs Server — who does what (minimum resource)

> **Principle: all work happens on the server. The runner only does what can't be done
> without it — the push notification (SSH trigger).**

| Task | Where it happens |
|------|-----------------|
| Detect push | **Runner** (that's its job — it tells GitHub's systems) |
| SSH trigger (nohup) | **Runner** (~6s, then done) |
| git fetch / clone | **Server** |
| Files sync (rsync) | **Server** |
| Build (`BUILD_CMD`) | **Server** |
| DB backup | **Server** |
| **Migrate** (`MIGRATE_CMD`) | **Server** — only if set in config |
| **Restart** (`RESTART_METHOD`) | **Server** — after sync |
| Health check | **Server** |
| Telegram alert | **Server** |

Order (on the server, every deploy): **sync files → [backup] → [migrate] → [restart] → health**.
The runner does nothing else — no checkout, no build, no migrate. All the work stays on the server, the runner stays light.

---

## 📁 Files (21 + .agents/)

| File | What it does |
|------|---------------|
| `quickstart.sh` | ⚡ **1 command — everything** (setup + keygen + detect + test) |
| `config.example.sh` | **Settings template** — create `config.sh` and fill in your values |
| `setup.sh` | **Beginner setup wizard** — YES/NO questions, press Enter for recommended, creates config.sh itself |
| `setup-quick.sh` | **Paste setup** — paste all your values at once, no questions |
| `doctor.sh` | **Preflight doctor** — diagnose server environment, tools, permissions, and config |
| `keygen.sh` | **SSH key helper** — creates the key + prints 3 ready-to-copy blocks for GitHub (~2 min) |
| `detect.sh` | **Fully dynamic** — reads your repo and auto-sets APP_TYPE / build / migrate / restart by itself |
| `cron.sh` | **Zero GitHub Actions** — one command installs a cron job: deploy every N min, 0 Actions minutes |
| `runner.sh` | **~6s deploys (VPS)** — installs a self-hosted GitHub runner on the server: no VM boot, 0 Actions minutes |
| `webhook.sh` | **~1-2s deploys (VPS)** — HTTP listener: GitHub POST → auto_deploy.sh, 0 Actions minutes |
| `auto_deploy.sh` | Deploy script — git → rsync → build → backup → migrate → restart → health → notifications |
| `rollback.sh` | Go back to the previous commit + DB restore |
| `test.sh` | **Self-test** — syntax check + full local deploy/rollback test (no network) |
| `.github/workflows/deploy.yml.example` | GitHub Actions trigger (hosted runner, ~1 min) |
| `.github/workflows/deploy-selfhosted.yml.example` | GitHub Actions trigger (self-hosted runner, ~6s) |
| `.github/workflows/deploy-webhook.yml.example` | GitHub Actions trigger (webhook, ~1-2s) |
| `.github/workflows/test.yml` | CI self-test (runs test.sh on push/PR) |
| `README.md` | This guide |
| `AGENTS.md` + `.agents/` | Agent rules + memory (for AI agents / future developers) |
| `LICENSE` | MIT License — for a public repo |
| `.gitignore` | So `config.sh` / secrets are never committed |

---

## 🚀 Setup — Step by Step (5 min)

### Step 1: Put the kit on the server

**Where to put the kit — your choice:**

| Location | How | Notes |
|---|---|---|
| **Home level** (recommended) | `~/deploy-kit/` | Kit is separate from the app — simplest, survives every deploy |
| **Inside the project** | `~/ilm.esabaq.com/deploy_kit/` | All in one folder — `auto_deploy.sh` + `rollback.sh` already exclude `deploy_kit/` / `deploy-kit/` so rsync never wipes it |

> If you put the kit **inside the project folder**, set the `SERVER_DEPLOY_PATH` GitHub Secret to that path (e.g. `~/ilm.esabaq.com/deploy_kit/auto_deploy.sh`).

```bash
# Option A — copy the files (FTP / file manager) into ~/deploy-kit/ ...
mkdir -p ~/deploy-kit

# Option B — download directly on the server (once the kit repo is public/forked):
cd ~/deploy-kit
for f in auto_deploy.sh rollback.sh setup.sh setup-quick.sh keygen.sh detect.sh cron.sh test.sh config.example.sh; do
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
| `NODE_BIN` | Node binary path (if build uses a custom node) | Path or `""` | `/home/cpuser/bin/node` |
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
| `DISCORD_WEBHOOK_URL` | Discord channel webhook URL (optional) | URL | `https://discord.com/api/webhooks/...` |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (optional) | URL | `https://hooks.slack.com/services/...` |
| `ALERT_EMAIL` | Email address for deploy/failure alerts | Email | `alerts@myapp.com` |
| `DEPLOY_WEBHOOK_SECRET` | Webhook trigger (VPS only) — random string, match in GitHub secrets | `""` = disabled | `abc...` |
| `WEBHOOK_PORT` | Webhook listener port | Number | `9000` |
| `HEALTH_URL` | Health check URL (optional) | Full URL | `https://myapp.com/health` |
| `HEALTH_WAIT` | Seconds to wait after restart before checking | Number | `8` |
| `HEALTH_RETRY` | How many times to retry health check | Number | `3` |
| `AUTO_ROLLBACK_ON_FAIL` | Auto-rollback if health check fails | yes/no | `yes` |
| `DEPLOY_KEY` | Path to the GitHub deploy key | Key file | `/home/cpuser/.ssh/deploy_key` |
| `WORKSPACE_BASE` | Where the git workspace lives | Path | `/home/cpuser/deploy-workspace` |
| `TOGGLE_FLAG` / `SKIP_WHEN_FLAG` | Toggle system (optional) | Flag path + `1` | — |
| `KIT_SELF_UPDATE` | `yes` = auto-pull kit updates from its own git repo (if cloned; `config.sh` is gitignored, never touched) | yes/no | `""` |
| `DEFAULT_BRANCH` | Default deploy branch | Branch | `main` |
| `LOG_FILE` | Where to log | Path | `/home/cpuser/deploy.log` |
| `RSYNC_EXCLUDES` | Extra rsync excludes (space-separated) | `uploads/` | — |

**Rule:** Anything that is **not** in your project → leave it as `""` (empty). The script will skip it automatically.
**Only 2 are required:** `REPO_URL` + `APP_DIR`. Everything else is **optional** — backup, build, migrate, restart, health check, Telegram, Discord, Email, toggle — whatever is empty gets skipped.

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

### Step 3: Diagnostics + Permissions + Test

```bash
chmod +x auto_deploy.sh rollback.sh setup.sh setup-quick.sh doctor.sh keygen.sh detect.sh cron.sh test.sh

# Run system doctor (checks tools, permissions, config before first deploy):
/bin/bash doctor.sh

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

**GitHub Secrets needed (5):**

| Secret | Value |
|--------|-------|
| `SSH_PRIVATE_KEY` | Server's private key (keygen block 2) |
| `SERVER_HOST` | Server IP/domain |
| `SERVER_USER` | Server user |
| `SSH_PORT` | `22` (or custom) |
| `SERVER_DEPLOY_PATH` | **Full path to `auto_deploy.sh` ON THE SERVER** (e.g. `~/deploy-kit/auto_deploy.sh` or wherever you put the kit). Not set → defaults to `~/deploy-kit/auto_deploy.sh`. Wrong path = "No such file or directory" in `~/deploy.log`. |

### Step 4b: Auto-detect your project (fully dynamic — optional but recommended)

```bash
# Reads your repo and fills APP_TYPE / build / migrate / restart by itself:
/bin/bash detect.sh
#   → says "Apply these to config.sh? (yes/no)" → yes
#   → no technical knowledge needed
```

### Step 5: GitHub Actions setup — which workflow to copy?

**3 workflow files exist — you only need 1. Most users use this one:**

| File | When to use | Extra setup needed? |
|------|--------------|---------------------|
| **`deploy.yml.example`** ✅ | **MOST USERS** — GitHub's free hosted runner (2000 min/mo) | only 5 Secrets |
| `deploy-selfhosted.yml.example` | only if you ran `runner.sh` on a VPS | runner.sh (VPS) |
| `deploy-webhook.yml.example` | only if you ran `webhook.sh start` on a VPS | webhook.sh (VPS) |

**Default (if unsure): copy `deploy.yml.example`:**

```bash
# In your project repo:
mkdir -p .github/workflows
cp ~/deploy-kit/.github/workflows/deploy.yml.example .github/workflows/deploy.yml
```

Edit your **branch names** in `deploy.yml` (default: dev/demo/main).
If you use self-hosted/webhook, copy that file instead — otherwise deploy.yml is the right choice.

### Step 6: Push it 🎉

```
Push (dev/demo/main) → GitHub Actions (~6s) → server deploy → Telegram alert
```

---

## 🎬 Worked Example (generic — fill in your own project values)

Imagine you are deploying a **Node app**. Here is the full flow, top to bottom:

### 1. Run `quickstart.sh` (on the server)

```bash
cd ~/deploy-kit
/bin/bash quickstart.sh
```

You only answer these questions (Enter = recommended):

```
Server login username [cpuser]: cpuser
Server host or IP [your-server.com]: myhost.com
Live domain [myapp.com]: myapp.com
App folder [/home/cpuser/myapp]: /home/cpuser/myapp
GitHub repo SSH URL [git@github.com:user/repo.git]: git@github.com:you/myapp.git
App type [python]: node          ← detect.sh will also confirm this later
... (press Enter for the rest)
```

### 2. `config.sh` looks like this (example — no real data)

```bash
SERVER_USER="cpuser"
SERVER_HOST="myhost.com"
SITE_DOMAIN="myapp.com"
APP_DIR="/home/cpuser/myapp"
REPO_URL="git@github.com:you/myapp.git"

APP_TYPE="node"
BUILD_CMD="npm install && npm run build"   # suggested by detect.sh
RESTART_METHOD="passenger"                 # cPanel

DB_BACKUP="no"         # leave empty if not needed
HEALTH_URL="https://myapp.com/"            # optional
TELEGRAM_BOT_TOKEN=""  # leave empty → no alerts
```

> **Rule:** if your project doesn't have something → leave it `""`. The script skips it automatically. Only `REPO_URL` + `APP_DIR` are required.

### 3. Workflow + push on GitHub

```bash
# in your PROJECT repo (myapp):
mkdir -p .github/workflows
cp ~/deploy-kit/.github/workflows/deploy.yml.example .github/workflows/deploy.yml
# edit branch names (dev/demo/main) + set 5 Secrets (from keygen)
git add . && git commit -m "deploy setup" && git push
```

### 4. What happens (deploy log)

```
🚀 Deploy started (myapp.com · main)
abc1234 → def5678
✅ Deploy successful (myapp.com · main) — health OK
   Time: 34s
```

### 5. Rollback (if something breaks)

```bash
/bin/bash ~/deploy-kit/rollback.sh main        # back to the last version
/bin/bash ~/deploy-kit/rollback.sh main <SHA>  # back to a specific commit
```

---

## 🎯 Choose your deploy trigger (all included)

| Trigger | Deploy speed | GitHub Actions minutes | Runner used? | Works on | Setup |
|---------|-------------|------------------------|--------------|----------|-------|
| **Hosted Actions** | ~1 min (VM boot + ~6s) | ~1 / deploy | yes (VM) | cPanel + VPS | `deploy.yml.example` |
| **Self-hosted runner** ⚡ | **~5-6s** (no VM boot) | **0** | yes (self-hosted) | VPS only | `runner.sh` + `deploy-selfhosted.yml.example` |
| **Webhook (native)** ⚡⚡ | **~1-2s** | **0** | **NO runner at all** | VPS only | `webhook.sh` + GitHub Settings → Webhooks |
| **Webhook (Actions)** ⚡⚡ | **~1-2s** | ~1 / deploy | yes (VM) | VPS only | `webhook.sh` + `deploy-webhook.yml.example` |
| **Cron** | within N min | **0** | no | cPanel + VPS | `cron.sh` |

- **Small project, few pushes** → Hosted Actions is fine (simple).
- **You want 5-6s and have a VPS** → Self-hosted runner (`runner.sh`), zero VM boot.
- **Fastest (~1-2s) + ZERO runner** → **Native webhook**: GitHub POSTs directly, no runner at all.
- **You never want to worry about the limit** → Cron (`cron.sh`), unlimited.

All of them call the **same `auto_deploy.sh`** — switch anytime, nothing else changes.

### 🌐 Native webhook (0 runner) — recommended for VPS

Deploy using GitHub's **built-in webhook** — **no Actions runner runs at all**, GitHub POSTs directly to your server (~1-2s, 0 Actions minutes):

```bash
# 1. Start the listener on the server (VPS only):
/bin/bash webhook.sh start
# 2. Set a secret in config.sh (long random string):
#    DEPLOY_WEBHOOK_SECRET="<random-string>"
# 3. GitHub → repo → Settings → Webhooks → Add webhook:
#    Payload URL:  http://SERVER_IP:9000/webhook/deploy/
#    Content type: application/json
#    Secret:       <the same random string>
#    Which events: Just the push event
```

Now every push is sent directly from GitHub to your server — HMAC-secret verified, the branch is read from `refs/heads/...`, and `auto_deploy.sh` runs. **Runner = 0, limit = 0.**

---

## ⚡ GitHub free limits — never run out

GitHub **free plan** gives you **2,000 Actions minutes / month**. Each deploy costs ~1 min
(VM boot + the ~6s job). The workflow is already **minimum-resource**:

- No checkout, no build on the runner — one tiny SSH job
- Doc-only pushes (`*.md` / `docs/**`) → **0 runner time** (workflow doesn't even start)
- `permissions: {}` — no unnecessary token, faster + safer
- Overlapping pushes auto-cancel (`concurrency`) — no wasted minutes

So Actions mode handles roughly **2,000 deploys/month** — enough for most projects.

**Want ZERO Actions minutes?** Three ways — pick one:

| Mode | How | Runner? | Speed |
|------|-----|---------|-------|
| **Native webhook** ⭐ | GitHub Settings → Webhooks | **no** | ~1-2s |
| **Cron** | `cron.sh` — server polls every N min | no | within N min |
| **Self-hosted runner** | `runner.sh` | self-hosted | ~5-6s |

```bash
# Native webhook (fastest, 0 runner):
/bin/bash webhook.sh start

# Or cron (cPanel/VPS, unlimited, polling):
/bin/bash cron.sh 2            # every 2 minutes, 0 GitHub Actions
/bin/bash cron.sh 5            # ... or every 5 minutes
```

- No new commit → instant skip (SHA check) — idle checks cost nothing
- Build / DB backup / migrate / restart / health / Telegram all work the same
- Free plan = **unlimited** — the limit can never run out
- Not on a VPS? cPanel users: `cron.sh` prints the exact line for **cPanel → Cron Jobs**

> **Toggle:** running both? `touch ~/.deploy_github` + `SKIP_WHEN_FLAG=1` → cron skips
> and GitHub Actions takes over. Remove the flag → cron deploys again.

> **Simple rule:** small project / few pushes → Actions mode is fine.
> Many pushes / worry about the limit → `cron.sh` = unlimited, zero cost.

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
| "No such file or directory" in `~/deploy.log` | Workflow tries to run `auto_deploy.sh` from wrong path | Set `SERVER_DEPLOY_PATH` GitHub Secret to the correct path on your server |

## ✅ How to verify a deploy actually worked

**GitHub Actions green check** only means the trigger ran (~6s). It does NOT mean the deploy succeeded.

### 1. Server log (full detail)

```bash
tail -50 ~/deploy.log
```

You should see:
```
🚀 Deploy started (mydomain.com · main)
✅ Deploy successful (mydomain.com · main) — health OK
```

If you see `No such file or directory`, the `SERVER_DEPLOY_PATH` secret is wrong.

### 2. The site (quick)

```bash
# Health endpoint (if configured)
curl -s https://yoursite.com/health

# Or just the page status
curl -s -o /dev/null -w "%{http_code}" https://yoursite.com/
```

### 3. The deployed commit

```bash
cat ~/deploy-kit/deploy-workspace/.deployed_sha
```

Compare it with the latest commit on GitHub — if they match, the deploy went through.

---

## 🛡️ Safety Notes

- **Never commit `config.sh`** — it's in `.gitignore`, but still be careful
- Never **share `SSH_PRIVATE_KEY`** with anyone
- Everything is optional — whatever is empty in the config gets skipped. Only `REPO_URL` + `APP_DIR` are required
- It's better to keep DB backup `yes` on production (safe deploy)

## 🔒 Gitignore Guide — for anyone using this kit

**In your PROJECT repo, gitignore these (secrets — never commit):**

```gitignore
# Deploy kit secrets (per project)
deploy-kit/config.sh       # server IP, user, DB creds, keys
.env
.env.*
*.env
deploy_key*
*.key
*.pem

# Deploy runtime state
.deployed_sha
.failed_sha
deploy-workspace/

# Logs / backups
*.log
backups/
```

**Commit these (safe — placeholders only):**

```gitignore
# Yehi GitHub pe jayega — sab generic
config.example.sh          # template (placeholders, safe)
auto_deploy.sh rollback.sh setup.sh ...   # all kit scripts
.github/workflows/         # workflows (no secrets — use GitHub Secrets)
README.md
```

> **Golden rule:** GitHub pe wohi daalo jo **public ho sakta hai**. `config.example.sh` = safe template. `config.sh` = aapka personal setup = **kabhi nahi**.

## ♻️ Recovery — kit lost ho jaye to?

- **Kit code (scripts/docs):** ✅ GitHub se re-download kar sakte ho (`git clone` ya `curl`) — yeh code hai, public repo mein hai
- **Aapka setup (`config.sh`):** ❌ **GitHub mein nahi hai** (by design — secret). Lost ho to **dobara banana parega**: `/bin/bash setup.sh` + `keygen.sh` + `detect.sh` (5 min)

**So:** Code recover hota hai, setup nahi — isliye config.sh ka **backup apne server/local pe rakho** (never in git).

---

## ✅ Checklist (for completing the setup)

- [ ] `~/deploy-kit/` on the server (21 files)
- [ ] Created `config.sh` (wizard: `/bin/bash setup.sh`)
- [ ] `chmod +x *.sh`
- [ ] SSH keys + copy-paste: `/bin/bash keygen.sh` ✅
- [ ] GitHub Deploy key added (keygen block 1)
- [ ] GitHub Secrets (4) added (keygen blocks 2 + 3)
- [ ] Auto-detect project: `/bin/bash detect.sh` (optional but easy)
- [ ] `.github/workflows/deploy.yml` in your repo
- [ ] Manual test: `/bin/bash auto_deploy.sh main` ✅
- [ ] Push → Actions run ✅ → Telegram alert ✅

---

**This kit is public-ready. None of your data/secrets. Anyone can take any project and run it.**
