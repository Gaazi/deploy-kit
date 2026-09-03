#!/bin/bash
# ============================================================
# DEPLOY KIT — setup.sh (beginner-friendly setup wizard)
# ------------------------------------------------------------
#   /bin/bash setup.sh
# Clean YES/NO questions with recommended defaults — a beginner
# can press Enter all the way and get a working config.
# Creates config.sh. Then run keygen.sh for SSH keys + GitHub
# copy-paste blocks.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"
if [ -f config.sh ]; then
  echo "⚠️ config.sh already exists — to create a new one first: rm config.sh"
  echo "   (or edit it directly: nano config.sh)"
  exit 1
fi

ask() { read -rp "$1 [$2]: " v; echo "${v:-$2}"; }

# Escape a value for safe inclusion in double-quoted bash assignments.
# Handles \, $, ", ` that would otherwise be interpreted when config.sh is sourced.
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/\$/\\$/g' -e 's/"/\\"/g' -e 's/`/\\`/g'; }

# yesno: $1=question  $2=default (yes|no)  → returns 0=yes, 1=no
yesno() {
  local a d
  [ "$2" = "yes" ] && d="Y/n" || d="y/N"
  read -rp "$1 ($d): " a
  case "$a" in
    "" ) [ "$2" = "yes" ] && return 0 || return 1 ;;
    y|Y|yes|YES|Yes ) return 0 ;;
    * ) return 1 ;;
  esac
}

echo "============================================="
echo "  Deploy Kit — Setup Wizard"
echo "  * Answer YES/NO or paste values"
echo "  * Press Enter = recommended answer"
echo "  * No technical knowledge needed — hints on every step"
echo "============================================="

# ── 1. Server basics ──────────────────────────────
SERVER_USER=$(ask "Server login username (cPanel username)" "cpuser")
SERVER_HOST=$(ask "Server host or IP" "your-server.com")
SSH_PORT=$(ask "SSH port (cPanel = 22)" "22")
SITE_DOMAIN=$(ask "Live domain, without https://" "myapp.com")
APP_DIR=$(ask "App folder on the server (full path)" "/home/$SERVER_USER/myapp")
echo ""
echo "  📋 Copy from GitHub: open your repo → green Code button → SSH"
REPO_URL=$(ask "GitHub repo SSH URL (git@github.com:...)" "git@github.com:user/repo.git")
echo ""

# ── 2. App type (restart method + command hints auto-set) ──
echo "  What kind of app is this?"
echo "    python | node | php | wordpress | ruby | java | go | static | docker"
APP_TYPE=$(ask "App type" "python")
BUILD_HINT=""; MIGRATE_HINT=""; RESTART_METHOD="passenger"; WSGI_FILE=""
case "$APP_TYPE" in
  python)    RESTART_METHOD="passenger"; WSGI_FILE="passenger_wsgi.py"; MIGRATE_HINT='$PYTHON_BIN -m alembic upgrade head' ;;
  node)      RESTART_METHOD="passenger"; WSGI_FILE="passenger_wsgi.py"; BUILD_HINT="npm install && npm run build" ;;
  php)       RESTART_METHOD="php" ;;
  wordpress) RESTART_METHOD="php" ;;
  ruby)      RESTART_METHOD="passenger"; BUILD_HINT="bundle install"; MIGRATE_HINT="bundle exec rails db:migrate" ;;
  java)      RESTART_METHOD="systemctl"; BUILD_HINT="mvn package -DskipTests" ;;
  go)        RESTART_METHOD="systemctl"; BUILD_HINT="go build -o app ." ;;
  docker)    RESTART_METHOD="docker" ;;
  static)    RESTART_METHOD="none" ;;
  *)         RESTART_METHOD="passenger" ;;
esac
echo "  (restart method auto-set: $RESTART_METHOD — change later in config.sh if needed)"
[ -n "$BUILD_HINT" ] && echo "  💡 $APP_TYPE tip: build command → $BUILD_HINT"
[ -n "$MIGRATE_HINT" ] && echo "  💡 $APP_TYPE tip: migration command → $MIGRATE_HINT"
echo ""

# ── 2b. Restart method details (only for the chosen method) ──
SERVICE_NAME=""; PM2_APP="all"; SUPERVISOR_APP="all"; PHP_FPM_SERVICE=""
if [ "$RESTART_METHOD" = "systemctl" ]; then
  SERVICE_NAME=$(ask "systemd service name (from: systemctl list-units)" "$SITE_DOMAIN")
elif [ "$RESTART_METHOD" = "php" ]; then
  PHP_FPM_SERVICE=$(ask "php-fpm service name (Enter = skip reload)" "")
fi

# ── 2c. Monorepo subfolder (optional) ──
APP_SUBDIR=""
if yesno "Is your app in a subfolder of the repo? (monorepo — deploy only that folder)" no; then
  APP_SUBDIR=$(ask "Subfolder path (relative to repo root)" "")
fi
echo ""

# ── 3. Optional features (all YES/NO) ────────────
BUILD_CMD=""
if yesno "Do you need a build step? (e.g. npm run build)" no; then
  BUILD_CMD=$(ask "Paste your build command" "$BUILD_HINT")
fi

DB_BACKUP="no"; DB_TYPE="mysql"; DB_HOST="localhost"
DB_USER=""; DB_PASS=""; DB_NAME=""
if yesno "Do you use a database?" no; then
  DB_TYPE=$(ask "DB type (mysql / postgres / sqlite)" "mysql")
  DB_NAME=$(ask "DB name (sqlite: file path inside the app folder)" "")
  DB_USER=$(ask "DB user (not needed for sqlite)" "")
  DB_PASS=$(ask "DB password (stays on the server, never committed)" "")
  if yesno "Backup the DB before every deploy? (recommended for production)" no; then
    DB_BACKUP="yes"
  fi
fi

MIGRATE_CMD=""
if yesno "Do you need database migrations on deploy? (e.g. alembic)" no; then
  MIGRATE_CMD=$(ask "Migration command" "$MIGRATE_HINT")
fi

TELEGRAM_BOT_TOKEN=""; TELEGRAM_CHAT_ID=""
if yesno "Do you want Telegram alerts when a deploy finishes?" no; then
  echo "  📋 Get the token from @BotFather on Telegram"
  TELEGRAM_BOT_TOKEN=$(ask "Bot token" "")
  TELEGRAM_CHAT_ID=$(ask "Chat ID (ask @userinfobot after messaging the bot)" "")
fi

DISCORD_WEBHOOK_URL=""
if yesno "Do you want Discord webhook alerts?" no; then
  DISCORD_WEBHOOK_URL=$(ask "Discord Webhook URL" "")
fi

SLACK_WEBHOOK_URL=""
if yesno "Do you want Slack webhook alerts?" no; then
  SLACK_WEBHOOK_URL=$(ask "Slack Webhook URL" "")
fi

ALERT_EMAIL=""
if yesno "Do you want Email alerts?" no; then
  ALERT_EMAIL=$(ask "Alert email address" "")
fi

HEALTH_URL=""
AUTO_ROLLBACK_ON_FAIL="no"
RESTORE_ON_FAIL="no"
if yesno "Do you want a health check after deploy? (recommended)" yes; then
  HEALTH_DEFAULT="https://${SITE_DOMAIN:-localhost}/"
  HEALTH_URL=$(ask "Health URL (Enter = $HEALTH_DEFAULT)" "$HEALTH_DEFAULT")
  if yesno "Auto-rollback to previous version if health check fails?" no; then
    AUTO_ROLLBACK_ON_FAIL="yes"
  fi
fi

# ── 4. Write config.sh (all keys — same as config.example.sh) ──
PYTHON_BIN="/home/$SERVER_USER/virtualenv/$SITE_DOMAIN/3.11/bin/python"
cat > config.sh <<EOF
# ── Deploy Kit config (generated by setup.sh — $(date '+%F %T')) ──
SERVER_USER="$(esc "$SERVER_USER")"
SERVER_HOST="$(esc "$SERVER_HOST")"
SSH_PORT="$(esc "$SSH_PORT")"
SITE_DOMAIN="$(esc "$SITE_DOMAIN")"
APP_DIR="$(esc "$APP_DIR")"
REPO_URL="$(esc "$REPO_URL")"

# ── Stack ──
APP_TYPE="$(esc "$APP_TYPE")"
PYTHON_BIN="$(esc "$PYTHON_BIN")"
NODE_BIN=""
BUILD_CMD="$(esc "$BUILD_CMD")"
MIGRATE_CMD="$(esc "$MIGRATE_CMD")"
PRE_DEPLOY_HOOK=""
POST_DEPLOY_HOOK=""
RESTART_METHOD="$(esc "$RESTART_METHOD")"
SERVICE_NAME="$(esc "$SERVICE_NAME")"
PM2_APP="$(esc "$PM2_APP")"
SUPERVISOR_APP="$(esc "$SUPERVISOR_APP")"
WSGI_FILE="$(esc "$WSGI_FILE")"
DOCKER_COMPOSE=""
PHP_FPM_SERVICE="$(esc "$PHP_FPM_SERVICE")"
APP_SUBDIR="$(esc "$APP_SUBDIR")"

# ── Database ──
DB_BACKUP="$(esc "$DB_BACKUP")"
DB_BACKUP_KEEP="7"
DB_TYPE="$(esc "$DB_TYPE")"
DB_HOST="$(esc "$DB_HOST")"
DB_USER="$(esc "$DB_USER")"
DB_PASS="$(esc "$DB_PASS")"
DB_NAME="$(esc "$DB_NAME")"

# ── Notifications ──
TELEGRAM_BOT_TOKEN="$(esc "$TELEGRAM_BOT_TOKEN")"
TELEGRAM_CHAT_ID="$(esc "$TELEGRAM_CHAT_ID")"
DISCORD_WEBHOOK_URL="$(esc "$DISCORD_WEBHOOK_URL")"
SLACK_WEBHOOK_URL="$(esc "$SLACK_WEBHOOK_URL")"
ALERT_EMAIL="$(esc "$ALERT_EMAIL")"
NOTIFY_ON_SUCCESS="yes"

# ── Webhook (VPS only) ──
DEPLOY_WEBHOOK_SECRET=""
WEBHOOK_PORT="9000"

# ── Health check & Safety ──
HEALTH_URL="$(esc "$HEALTH_URL")"
HEALTH_WAIT="8"
HEALTH_RETRY="3"
AUTO_ROLLBACK_ON_FAIL="$(esc "$AUTO_ROLLBACK_ON_FAIL")"
RESTORE_ON_FAIL="$(esc "$RESTORE_ON_FAIL")"

# ── Git / Advanced ──
DEPLOY_KEY=""
WORKSPACE_BASE="/home/$(esc "$SERVER_USER")/deploy-workspace"
TOGGLE_FLAG=""
SKIP_WHEN_FLAG=""
KIT_SELF_UPDATE=""
DEFAULT_BRANCH="main"
LOG_FILE=""
RSYNC_EXCLUDES=""
EOF

chmod 600 config.sh

# ── 5. Summary + next steps ──
echo ""
echo "✅ config.sh created!"
echo ""
echo "  ── Next steps: ──"
echo "  1. SSH keys:  /bin/bash keygen.sh"
echo "  2. Auto-detect your project (fully dynamic):  /bin/bash detect.sh"
echo "     (reads your repo → sets APP_TYPE/BUILD/MIGRATE/RESTART itself)"
echo "  3. Deploy:    /bin/bash auto_deploy.sh main"
echo ""

if yesno "Set up SSH keys now? (recommended — takes 1 minute)" yes; then
  echo ""
  /bin/bash keygen.sh
fi
