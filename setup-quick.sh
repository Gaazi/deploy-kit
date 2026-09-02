#!/bin/bash
# ============================================================
# DEPLOY KIT — setup-quick.sh (paste your config, no questions)
# ------------------------------------------------------------
#   /bin/bash setup-quick.sh
# Paste all your info at once (KEY=VALUE lines) →
# script creates config.sh. No questions asked.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"
if [ -f config.sh ]; then
  echo "⚠️ config.sh already exists — to create a new one first: rm config.sh"
  echo "   (or edit it directly: nano config.sh)"
  exit 1
fi

echo "============================================================"
echo "  Deploy Kit — Quick Setup (paste your info)"
echo ""
echo "  Paste your values below (KEY=VALUE one per line),"
echo "  then press Ctrl+D. Optional lines can be left empty."
echo ""
echo "  Example:"
echo "    SERVER_USER=cpuser"
echo "    REPO_URL=git@github.com:user/repo.git"
echo "============================================================"
echo ""

# ── Read pasted input (Ctrl+D = done) ──
INPUT="$(cat)"

# Escape a value for safe inclusion in double-quoted bash assignments.
# Handles \, $, ", ` that would otherwise be interpreted when config.sh is sourced.
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/\$/\\$/g' -e 's/"/\\"/g' -e 's/`/\\`/g'; }

# ── Defaults ──
SERVER_USER="cpuser"
SERVER_HOST="your-server.com"
SSH_PORT="22"
SITE_DOMAIN="your-domain.com"
APP_DIR=""
REPO_URL=""
APP_TYPE="python"
PYTHON_BIN=""
NODE_BIN=""
BUILD_CMD=""
MIGRATE_CMD=""
RESTART_METHOD="passenger"
SERVICE_NAME=""
PM2_APP="all"
SUPERVISOR_APP="all"
WSGI_FILE="passenger_wsgi.py"
DOCKER_COMPOSE=""
PHP_FPM_SERVICE=""
APP_SUBDIR=""
DB_BACKUP="no"
DB_TYPE="mysql"
DB_HOST="localhost"
DB_USER=""
DB_PASS=""
DB_NAME=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
DISCORD_WEBHOOK_URL=""
SLACK_WEBHOOK_URL=""
ALERT_EMAIL=""
DEPLOY_WEBHOOK_SECRET=""
WEBHOOK_PORT="9000"
HEALTH_URL=""
HEALTH_WAIT="8"
HEALTH_RETRY="3"
AUTO_ROLLBACK_ON_FAIL="no"
RESTORE_ON_FAIL="no"
DEPLOY_KEY=""
WORKSPACE_BASE="/home/$SERVER_USER/deploy-workspace"
TOGGLE_FLAG=""
SKIP_WHEN_FLAG=""
KIT_SELF_UPDATE=""
DEFAULT_BRANCH="main"
LOG_FILE=""
RSYNC_EXCLUDES=""

# ── Parse pasted KEY=VALUE lines (all keys, including advanced) ──
while IFS='=' read -r key val; do
  # trim whitespace around key and value for tolerance (e.g. "KEY = value")
  key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$key" ] && continue
  case "$key" in
    SERVER_USER)       SERVER_USER="$val" ;;
    SERVER_HOST)       SERVER_HOST="$val" ;;
    SSH_PORT)          SSH_PORT="$val" ;;
    SITE_DOMAIN)       SITE_DOMAIN="$val" ;;
    APP_DIR)           APP_DIR="$val" ;;
    REPO_URL)          REPO_URL="$val" ;;
    APP_TYPE)          APP_TYPE="$val" ;;
    PYTHON_BIN)        PYTHON_BIN="$val" ;;
    NODE_BIN)          NODE_BIN="$val" ;;
    BUILD_CMD)         BUILD_CMD="$val" ;;
    MIGRATE_CMD)       MIGRATE_CMD="$val" ;;
    RESTART_METHOD)    RESTART_METHOD="$val" ;;
    SERVICE_NAME)      SERVICE_NAME="$val" ;;
    PM2_APP)           PM2_APP="$val" ;;
    SUPERVISOR_APP)    SUPERVISOR_APP="$val" ;;
    WSGI_FILE)         WSGI_FILE="$val" ;;
    DOCKER_COMPOSE)    DOCKER_COMPOSE="$val" ;;
    PHP_FPM_SERVICE)   PHP_FPM_SERVICE="$val" ;;
    APP_SUBDIR)        APP_SUBDIR="$val" ;;
    DB_BACKUP)         DB_BACKUP="$val" ;;
    DB_TYPE)           DB_TYPE="$val" ;;
    DB_HOST)           DB_HOST="$val" ;;
    DB_USER)           DB_USER="$val" ;;
    DB_PASS)           DB_PASS="$val" ;;
    DB_NAME)           DB_NAME="$val" ;;
    TELEGRAM_BOT_TOKEN) TELEGRAM_BOT_TOKEN="$val" ;;
    TELEGRAM_CHAT_ID)  TELEGRAM_CHAT_ID="$val" ;;
    DISCORD_WEBHOOK_URL) DISCORD_WEBHOOK_URL="$val" ;;
    SLACK_WEBHOOK_URL)   SLACK_WEBHOOK_URL="$val" ;;
    ALERT_EMAIL)         ALERT_EMAIL="$val" ;;
    DEPLOY_WEBHOOK_SECRET) DEPLOY_WEBHOOK_SECRET="$val" ;;
    WEBHOOK_PORT)      WEBHOOK_PORT="$val" ;;
    HEALTH_URL)        HEALTH_URL="$val" ;;
    HEALTH_WAIT)       HEALTH_WAIT="$val" ;;
    HEALTH_RETRY)      HEALTH_RETRY="$val" ;;
    AUTO_ROLLBACK_ON_FAIL) AUTO_ROLLBACK_ON_FAIL="$val" ;;
    RESTORE_ON_FAIL)   RESTORE_ON_FAIL="$val" ;;
    DEPLOY_KEY)        DEPLOY_KEY="$val" ;;
    WORKSPACE_BASE)    WORKSPACE_BASE="$val" ;;
    TOGGLE_FLAG)       TOGGLE_FLAG="$val" ;;
    SKIP_WHEN_FLAG)    SKIP_WHEN_FLAG="$val" ;;
    KIT_SELF_UPDATE)   KIT_SELF_UPDATE="$val" ;;
    DEFAULT_BRANCH)    DEFAULT_BRANCH="$val" ;;
    LOG_FILE)          LOG_FILE="$val" ;;
    RSYNC_EXCLUDES)    RSYNC_EXCLUDES="$val" ;;
  esac
done <<< "$INPUT"

# ── Required check ──
if [ -z "$APP_DIR" ] || [ -z "$REPO_URL" ]; then
  echo "❌ APP_DIR and REPO_URL are required — paste these 2 and run again."
  exit 1
fi

# PYTHON_BIN default follows the pasted SERVER_USER/SITE_DOMAIN unless overridden
PYTHON_BIN="${PYTHON_BIN:-/home/$SERVER_USER/virtualenv/$SITE_DOMAIN/3.11/bin/python}"

# ── Create config.sh ──
cat > config.sh <<EOF
# ── Deploy Kit config (generated by setup-quick.sh — $(date '+%F %T')) ──
SERVER_USER="$(esc "$SERVER_USER")"
SERVER_HOST="$(esc "$SERVER_HOST")"
SSH_PORT="$(esc "$SSH_PORT")"
SITE_DOMAIN="$(esc "$SITE_DOMAIN")"
APP_DIR="$(esc "$APP_DIR")"
REPO_URL="$(esc "$REPO_URL")"

# ── Stack ──
APP_TYPE="$(esc "$APP_TYPE")"
PYTHON_BIN="$(esc "$PYTHON_BIN")"
NODE_BIN="$(esc "$NODE_BIN")"
BUILD_CMD="$(esc "$BUILD_CMD")"
MIGRATE_CMD="$(esc "$MIGRATE_CMD")"
RESTART_METHOD="$(esc "$RESTART_METHOD")"
SERVICE_NAME="$(esc "$SERVICE_NAME")"
PM2_APP="$(esc "$PM2_APP")"
SUPERVISOR_APP="$(esc "$SUPERVISOR_APP")"
WSGI_FILE="$(esc "$WSGI_FILE")"
DOCKER_COMPOSE="$(esc "$DOCKER_COMPOSE")"
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

# ── Webhook (VPS only) ──
DEPLOY_WEBHOOK_SECRET="$(esc "$DEPLOY_WEBHOOK_SECRET")"
WEBHOOK_PORT="$(esc "$WEBHOOK_PORT")"

# ── Health check & Safety ──
HEALTH_URL="$(esc "$HEALTH_URL")"
HEALTH_WAIT="$(esc "$HEALTH_WAIT")"
HEALTH_RETRY="$(esc "$HEALTH_RETRY")"
AUTO_ROLLBACK_ON_FAIL="$(esc "$AUTO_ROLLBACK_ON_FAIL")"
RESTORE_ON_FAIL="$(esc "$RESTORE_ON_FAIL")"

# ── Git / Advanced ──
DEPLOY_KEY="$(esc "$DEPLOY_KEY")"
WORKSPACE_BASE="$(esc "$WORKSPACE_BASE")"
TOGGLE_FLAG="$(esc "$TOGGLE_FLAG")"
SKIP_WHEN_FLAG="$(esc "$SKIP_WHEN_FLAG")"
KIT_SELF_UPDATE="$(esc "$KIT_SELF_UPDATE")"
DEFAULT_BRANCH="$(esc "$DEFAULT_BRANCH")"
LOG_FILE="$(esc "$LOG_FILE")"
RSYNC_EXCLUDES="$(esc "$RSYNC_EXCLUDES")"
EOF

chmod 600 config.sh
echo ""
echo "✅ config.sh created!"
echo "   nano config.sh → edit remaining details (DB_PASS, PYTHON_BIN...)"
echo "   Then test: /bin/bash auto_deploy.sh main"
