#!/bin/bash
# ============================================================
# DEPLOY KIT — setup.sh (interactive config generator)
# ------------------------------------------------------------
#   /bin/bash setup.sh
# Sawal jawab se config.sh banata hai — har sawal par hint
# (kahan se value lao). Koi galti ki gunjaish kam.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"
if [ -f config.sh ]; then
  echo "⚠️ config.sh pehle se hai — naye banane ke liye pehle: rm config.sh"
  echo "   (ya seedha edit karo: nano config.sh)"
  exit 1
fi

ask() { read -rp "$1 [$2]: " v; echo "${v:-$2}"; }

echo "============================================="
echo "  Deploy Kit — Setup (sawal jawab)"
echo "  * Enter dabao = default value use hogi"
echo "============================================="

SERVER_USER=$(ask "1/15 Server login user (cPanel username)" "cpuser")
SERVER_HOST=$(ask "2/15 Server IP ya domain" "your-server.com")
SSH_PORT=$(ask "3/15 SSH port (cPanel = 22)" "22")
SITE_DOMAIN=$(ask "4/15 Live domain, bina https://" "your-domain.com")
APP_DIR=$(ask "5/15 App folder server par (pura path)" "/home/$SERVER_USER/app")
REPO_URL=$(ask "6/15 Git repo SSH URL (GitHub → Code → SSH)" "git@github.com:user/repo.git")
APP_TYPE=$(ask "7/15 App type: python/node/php/static/docker" "python")
RESTART_METHOD=$(ask "8/15 Restart: passenger/touch/systemctl/docker/php/none" "passenger")
BUILD_CMD=$(ask "9/15 Build command (Node/static) — nahi to khaali" "")
MIGRATE_CMD=$(ask "10/15 Migration command — nahi to khaali" "$( [ "$APP_TYPE" = python ] && echo '$PYTHON_BIN -m alembic upgrade head' || echo '' )")
DB_BACKUP=$(ask "11/15 DB backup before migrate? yes/no" "no")
DB_NAME=$(ask "12/15 DB name (agar backup yes)" "")
DB_USER=$(ask "13/15 DB user (agar backup yes)" "")
TELEGRAM_TOKEN=$(ask "14/15 Telegram bot token (optional, khaali chhor sakte)" "")
TELEGRAM_CHAT=$(ask "15/15 Telegram chat ID (optional)" "")

cat > config.sh <<EOF
# ── Deploy Kit config (setup.sh se bana — $(date '+%F %T')) ──
SERVER_USER="$SERVER_USER"
SERVER_HOST="$SERVER_HOST"
SSH_PORT="$SSH_PORT"
SITE_DOMAIN="$SITE_DOMAIN"
APP_DIR="$APP_DIR"
REPO_URL="$REPO_URL"

# ── Stack ──
APP_TYPE="$APP_TYPE"
PYTHON_BIN="/home/$SERVER_USER/virtualenv/$SITE_DOMAIN/3.11/bin/python"
NODE_BIN=""
BUILD_CMD="$BUILD_CMD"
MIGRATE_CMD="$MIGRATE_CMD"
RESTART_METHOD="$RESTART_METHOD"
WSGI_FILE="passenger_wsgi.py"
DOCKER_COMPOSE=""
PHP_FPM_SERVICE=""

# ── Database ──
DB_BACKUP="$DB_BACKUP"
DB_TYPE="mysql"
DB_HOST="localhost"
DB_USER="$DB_USER"
DB_PASS=""
DB_NAME="$DB_NAME"

# ── Notifications ──
TELEGRAM_BOT_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT"

# ── Git / Advanced ──
DEPLOY_KEY=""
WORKSPACE_BASE="/home/$SERVER_USER/deploy-workspace"
TOGGLE_FLAG=""
SKIP_WHEN_FLAG=""
DEFAULT_BRANCH="main"
LOG_FILE=""
EOF

chmod 600 config.sh
echo ""
echo "✅ config.sh ban gaya!"
echo ""
echo "⚠️ Ab isme baqi details edit karo (jo setup mein nahi puchhe):"
echo "   nano config.sh"
echo "   → DB_PASS (DB password)"
echo "   → PYTHON_BIN (agar alag path)"
echo "   → WSGI_FILE / DOCKER_COMPOSE / PHP_FPM (aapke stack ke mutabiq)"
echo ""
echo "Phir test: /bin/bash auto_deploy.sh main"
