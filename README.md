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

```bash
cp config.example.sh config.sh
nano config.sh
```

`config.sh` mein ye bharo (sab zaroori):

| Setting | Kya likhna hai | Example |
|---------|---------------|---------|
| `SERVER_USER` | Server login user | `cpuser` |
| `SERVER_HOST` | Server IP / domain | `123.45.67.89` ya `server.com` |
| `SSH_PORT` | SSH port | `22` |
| `SITE_DOMAIN` | Live domain (health check ke liye) | `myapp.com` |
| `APP_DIR` | Server par app ka folder | `/home/cpuser/myapp` |
| `REPO_URL` | Aapka git repo (SSH) | `git@github.com:user/repo.git` |
| `MIGRATE_CMD` | Migration command | Python: `$PYTHON_BIN -m alembic upgrade head` — Node/PHP: `""` |
| `RESTART_METHOD` | App kaise restart | `passenger` / `touch` / `systemctl` / `none` |
| `DB_BACKUP` | Migrate se pehle DB backup | `yes` / `no` |
| `DB_*` | DB settings (agar backup yes) | host/user/pass/name |
| `TELEGRAM_*` | Alerts (optional) | token + chat_id |

**Baqi settings optional:** `BUILD_CMD`, `NODE_BIN`, `WSGI_FILE`, `DEPLOY_KEY`.

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
- DB backup optional hai — production par `yes` rakhna behtar
- Health check + Telegram = deploy ka result hamesha pata

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
