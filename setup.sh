#!/bin/bash
# ============================================================
# DEPLOY KIT — setup.sh (interactive config generator)
# ------------------------------------------------------------
#   /bin/bash setup.sh
# Ye aapse sawal karke config.sh bana dega — galti ki gunjaish kam.
# config.sh bana to auto_deploy.sh ready.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f config.sh ] && echo "⚠️ config.sh pehle se hai — ise delete karke dobara banao (ya edit karo)." && exit 1

ask() { read -rp "$1 [$2]: " v; echo "${v:-$2}"; }

echo "============================================="
echo "  Deploy Kit — Setup"
echo "  (Enter dabao to default value use karo)"
echo "============================================="

SERVER_USER=$(ask "Server login user" "cpuser")
SERVER_HOST=$(ask "Server IP/domain" "your-server.com")
SSH_PORT=$(ask "SSH port" "22")
SITE_DOMAIN=$(ask "Live domain (no https://)" "your-domain.com")
APP_DIR=$(ask "Server app directory" "/home/$SERVER_USER/app")
REPO_URL=$(ask "Git repo (SSH)" "git@github.com:user/repo.git")
APP_TYPE=$(ask "App type (python/node/php/static/docker)" "python")
RESTART_METHOD=$(ask "Restart method (passenger/touch/systemctl/docker/php/none)" "passenger")
DB_BACKUP=$(ask "DB backup before migrate? (yes/no)" "no")
DB_NAME=$(ask "DB name (agar backup yes)" "")

cat > config.sh <<EOF
# ── Deploy Kit config (setup.sh se bana) ──
SERVER_USER="$SERVER_USER"
SERVER_HOST="$SERVER_HOST"
SSH_PORT="$SSH_PORT"
SITE_DOMAIN="$SITE_DOMAIN"
APP_DIR="$APP_DIR"
REPO_URL="$REPO_URL"
APP_TYPE="$APP_TYPE"
PYTHON_BIN="/home/$SERVER_USER/virtualenv/$SITE_DOMAIN/3.11/bin/python"
NODE_BIN=""
BUILD_CMD=""
MIGRATE_CMD="\$PYTHON_BIN -m alembic upgrade head"
RESTART_METHOD="$RESTART_METHOD"
WSGI_FILE="passenger_wsgi.py"
DOCKER_COMPOSE=""
PHP_FPM_SERVICE=""
DB_BACKUP="$DB_BACKUP"
DB_TYPE="mysql"
DB_HOST="localhost"
DB_USER=""
DB_PASS=""
DB_NAME="$DB_NAME"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
DEPLOY_KEY=""
WORKSPACE_BASE="/home/$SERVER_USER/deploy-workspace"
EOF

chmod 600 config.sh
echo ""
echo "✅ config.sh ban gaya — ab isme baqi details (DB pass, telegram, etc.) edit karo:"
echo "   nano config.sh"
echo "   phir test: /bin/bash auto_deploy.sh main"
