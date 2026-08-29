# Deploy Kit — Generic Auto-Deployment Kit

> **Kisi bhi project (Python / Node / PHP / Static) ko GitHub push par auto-deploy karo.**
> Ye kit **public-ready** hai — koi secret/data nahi, sab placeholder. Koi bhi project le kar apna config bhar ke chala sakta hai.

---

## 📌 Ye kit kya karta hai

```
GitHub push (dev/demo/main)
   → GitHub Actions trigger (~6s, fire-and-forget)
   → Server par: auto_deploy.sh <branch>
   → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → health check → [Telegram]
   → Site live
```

**Fire-and-forget:** GitHub run ~6s mein complete. Deploy server par background chalta hai. Result **Telegram alert** se milta hai.

---

## 📁 Files (6)

| File | Kya karta hai |
|------|---------------|
| `config.example.sh` | **Settings template** — `config.sh` banao aur apne values bharo |
| `setup.sh` | **Interactive setup** — sawal jawab se config.sh khud banata hai |
| `auto_deploy.sh` | Deploy script — git → rsync → build → backup → migrate → restart → health → telegram |
| `rollback.sh` | Pichle commit par wapas jao + DB restore |
| `.github/workflows/deploy.yml.example` | GitHub Actions trigger (fire-and-forget ~6s) |
| `README.md` | Ye guide |
| `LICENSE` | MIT License — public repo ke liye |
| `.gitignore` | `config.sh` / secrets kabhi commit na ho |

---

## 🚀 Setup — Step by Step (5 min)

### Step 1: Server par kit rakho

```bash
# Server par folder banao aur kit ke files copy karo:
mkdir -p ~/deploy-kit
# ... is folder ke 6 files ~/deploy-kit/ mein copy karo ...
# (ya: git clone apna-repo → deploy-kit/ folder already hai)

cd ~/deploy-kit
```

### Step 2: Config banao (sabse zaroori)

**2 tareeke:**

```bash
# Tareeka A — Easy (setup.sh — sawal jawab, khud banata hai):
/bin/bash setup.sh

# Tareeka B — Manual (config.example.sh copy + edit):
cp config.example.sh config.sh
nano config.sh
```

#### 📋 `config.sh` — KAHAN KYA DALNA HAI (poori detail)

| Setting | Kahan se lao | Kya likhna hai | Example |
|---------|-------------|---------------|---------|
| `SERVER_USER` | Server panel (cPanel username) | Login user | `cpuser` |
| `SERVER_HOST` | Server IP ya domain | Host | `123.45.67.89` ya `server.com` |
| `SSH_PORT` | SSH port (cPanel: 22) | Port | `22` |
| `SITE_DOMAIN` | Aapka live domain | Domain (bina https://) | `myapp.com` |
| `APP_DIR` | Server par app ka pura folder path | App directory | `/home/cpuser/myapp` |
| `REPO_URL` | GitHub repo (Settings → SSH clone) | Repo SSH URL | `git@github.com:user/repo.git` |
| `APP_TYPE` | Aapka stack | python/node/php/static/docker | `python` |
| `PYTHON_BIN` | Server par Python path (virtualenv) | Python binary | `/home/cpuser/virtualenv/myapp/3.11/bin/python` |
| `BUILD_CMD` | Build command (Node/static) | Ya khaali `""` | `npm run build` |
| `MIGRATE_CMD` | DB migration command | Ya khaali `""` | `$PYTHON_BIN -m alembic upgrade head` |
| `RESTART_METHOD` | App kaise restart | passenger/touch/systemctl/docker/php/none | `passenger` |
| `WSGI_FILE` | Passenger wala (Python) | WSGI file | `passenger_wsgi.py` |
| `DOCKER_COMPOSE` | Docker project | compose file path | `docker-compose.yml` |
| `PHP_FPM_SERVICE` | PHP project | php-fpm service name | `php8.2-fpm` |
| `DB_BACKUP` | DB backup chahiye? | yes/no | `yes` |
| `DB_TYPE` / `DB_HOST` / `DB_USER` / `DB_PASS` / `DB_NAME` | Server DB panel | DB details | `mysql` / `localhost` / user / pass / name |
| `TELEGRAM_BOT_TOKEN` | @BotFather se (optional) | Token | `123:ABC...` |
| `TELEGRAM_CHAT_ID` | Telegram mein bot se message (optional) | Chat ID | `-100123...` |
| `HEALTH_URL` | Health check URL (optional) | Full URL | `https://myapp.com/health` |
| `DEPLOY_KEY` | GitHub deploy key ka path | Key file | `/home/cpuser/.ssh/deploy_key` |
| `TOGGLE_FLAG` / `SKIP_WHEN_FLAG` | Toggle system (optional) | Flag path + `1` | — |
| `DEFAULT_BRANCH` | Default deploy branch | Branch | `main` |
| `LOG_FILE` | Log kahan | Path | `/home/cpuser/deploy.log` |

**Rule:** Jo cheez aapke project mein **nahi** hai → `""` (khaali) chhor do. Script automatically skip karega.
**Sirf 2 zaroori hain:** `REPO_URL` + `APP_DIR`. Baqi **sab optional** — backup, build, migrate, restart, health check, Telegram, toggle — jo khali hai woh skip.

### Step 3: Permissions + Test

```bash
chmod +x auto_deploy.sh rollback.sh

# Manual test (pehli baar — sab theek hai confirm karo):
/bin/bash auto_deploy.sh main
```

**Agar manual deploy theek → GitHub setup karo.**

### Step 4: GitHub Actions setup

```bash
# Apne project repo mein:
mkdir -p .github/workflows
cp ~/deploy-kit/.github/workflows/deploy.yml.example .github/workflows/deploy.yml
```

`deploy.yml` mein apne **branch names** edit karo (default: dev/demo/main).

### Step 5: GitHub Secrets

```
GitHub → Repo → Settings → Secrets and variables → Actions → New repository secret
```

| Secret | Value |
|--------|-------|
| `SSH_PRIVATE_KEY` | Server ka **private key** (server par `~/.ssh/id_ed25519` ka content) |
| `SERVER_HOST` | Server IP/domain |
| `SERVER_USER` | Server user |
| `SSH_PORT` | `22` (ya custom) |

### Step 6: Push karo 🎉

```
Push (dev/demo/main) → GitHub Actions (~6s) → server deploy → Telegram alert
```

---

## 🎛️ auto_deploy.sh — deploy flow (har step)

| Step | Kya | Kab |
|------|-----|-----|
| 1 | `config.sh` load | Hamesha |
| 2 | GitHub-mode flag check (`~/.deploy_github`) | Agar flag setup ho |
| 3 | Git clone/fetch workspace | Pehli baar / har push |
| 4 | New commit check (same SHA = skip) | Har push |
| 5 | Rsync files → app dir (excludes .env/db/media) | Har deploy |
| 6 | Build (agar `BUILD_CMD` ho) | Config ke mutabiq |
| 7 | DB backup (agar `DB_BACKUP=yes`) | Migrate se pehle |
| 8 | Migrate (agar `MIGRATE_CMD` ho) | Har deploy |
| 9 | Restart (`RESTART_METHOD`) | Har deploy |
| 10 | Record deployed SHA | Har deploy |
| 11 | Health check (site live?) | Har deploy |
| 12 | Telegram alert (start/success/fail) | Agar token ho |

---

## ⏪ Rollback (agar kuch bigde)

```bash
# Server par:
/bin/bash ~/deploy-kit/rollback.sh main              # last SHA par wapas
/bin/bash ~/deploy-kit/rollback.sh main <COMMIT_SHA>  # kisi specific SHA par
```

Ye automatically: pin → DB dump restore (agar ho) → files sync → restart.

---

## 🔄 Toggle (GitHub vs Cron — optional)

Agar aapke paas cron deploy bhi hai:

```bash
touch ~/.deploy_github   # GitHub mode (cron skip)
rm    ~/.deploy_github   # cron mode (GitHub skip)
```

`auto_deploy.sh` mein `SKIP_WHEN_FLAG=1` set karo to flag present par skip hoga.

---

## 🔍 Troubleshooting

| Problem | Wajah | Fix |
|---------|-------|-----|
| `config.sh nahi mila` | config banaya nahi | `cp config.example.sh config.sh` |
| SSH fail (GitHub) | Secret galat | GitHub Secrets check karo |
| Deploy hua lekin site down | Health check fail | `rollback.sh` chalao |
| Deploy skip ("No new commit") | SHA same | Koi naya push karo |
| DB backup nahi | `DB_BACKUP` no ya DB_* khali | config check karo |

---

## 🛡️ Safety Notes

- **`config.sh` kabhi commit mat karo** — `.gitignore` mein hai, lekin phir bhi dhyan
- `SSH_PRIVATE_KEY` **kisi se share mat karo**
- Sab kuch optional hai — jo config mein khali hai woh skip. Sirf `REPO_URL` + `APP_DIR` zaroori
- DB backup production par `yes` rakhna behtar (safe deploy)

---

## ✅ Checklist (setup complete hone ke liye)

- [ ] `~/deploy-kit/` server par (6 files)
- [ ] `config.sh` bana + apne values
- [ ] `chmod +x auto_deploy.sh rollback.sh`
- [ ] Manual test: `/bin/bash auto_deploy.sh main` ✅
- [ ] `.github/workflows/deploy.yml` apne repo mein
- [ ] GitHub Secrets (4) set
- [ ] Push karo → Actions run ✅ → Telegram alert ✅

---

**Ye kit public-ready hai. Koi aapka data/secret nahi. Koi bhi project le kar chala sakta hai.**
