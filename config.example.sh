# ============================================================
# DEPLOY KIT — config.example.sh
# ------------------------------------------------------------
# Copy this file to config.sh and fill in YOUR project values.
#   cp config.example.sh config.sh && nano config.sh
#
# config.sh is gitignored — kabhi commit mat karo (secrets hain).
# ============================================================

# ── Server / SSH ────────────────────────────────────────────
SERVER_USER="your_cpanel_user"        # server login user
SERVER_HOST="your-server.com"         # server IP or hostname
SSH_PORT="22"                         # SSH port (usually 22)

# ── Site / App ──────────────────────────────────────────────
SITE_DOMAIN="your-domain.com"         # live domain (no https://)
APP_DIR="/home/$SERVER_USER/your-app" # live app directory
REPO_URL="git@github.com:YOUR_USER/YOUR_REPO.git"  # your git repo

# ── App Type (choose your stack) ────────────────────────────
APP_TYPE="python"                     # python | node | php | static | docker
PYTHON_BIN="/home/$SERVER_USER/virtualenv/your-app/3.11/bin/python"  # python type
NODE_BIN=""                           # node type: /path/to/node
BUILD_CMD=""                          # build command (npm run build etc.) — leave "" if none
MIGRATE_CMD="$PYTHON_BIN -m alembic upgrade head"   # migration command — "" if none
RESTART_METHOD="passenger"            # passenger | touch | systemctl | docker | none
WSGI_FILE="passenger_wsgi.py"         # passenger type: your wsgi entry
DOCKER_COMPOSE=""                     # docker type: docker-compose.yml ka path ("" = nahi)
PHP_FPM_SERVICE=""                    # php type: php-fpm service name ("" = nahi)

# ── Database (optional — backup before migrate) ─────────────
DB_BACKUP="no"                        # yes | no
DB_TYPE="mysql"                       # mysql | postgres
DB_HOST="localhost"
DB_USER=""
DB_PASS=""
DB_NAME=""

# ── Notifications (optional) ────────────────────────────────
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# ── Git ─────────────────────────────────────────────────────
DEPLOY_KEY=""                         # path to SSH deploy key ("" = use default ssh)
WORKSPACE_BASE="/home/$SERVER_USER/deploy-workspace"  # clone workspace
