# ============================================================
# DEPLOY KIT — config.example.sh
# ------------------------------------------------------------
# Copy this file to config.sh and fill in YOUR project values.
#   cp config.example.sh config.sh && nano config.sh
#
# config.sh is gitignored — never commit it (secrets).
# ============================================================

# ── Server / SSH ────────────────────────────────────────────
SERVER_USER="your_cpanel_user"        # server login user
SERVER_HOST="your-server.com"         # server IP or hostname
SSH_PORT="22"                         # SSH port (usually 22)

# ── Site / App ──────────────────────────────────────────────
SITE_DOMAIN="your-domain.com"         # live domain (no https://)
APP_DIR="/home/$SERVER_USER/your-app" # live app directory (REQUIRED)
REPO_URL="git@github.com:YOUR_USER/YOUR_REPO.git"  # your git repo (REQUIRED)

# ── App Type (choose your stack) ────────────────────────────
APP_TYPE="python"                     # python | node | php | wordpress | ruby | java | go | static | docker
PYTHON_BIN="/home/$SERVER_USER/virtualenv/your-app/3.11/bin/python"  # python type
NODE_BIN=""                           # node type: /path/to/node
BUILD_CMD=""                          # build command (npm run build etc.) — leave "" if none
MIGRATE_CMD="$PYTHON_BIN -m alembic upgrade head"   # migration command — "" if none
RESTART_METHOD="passenger"            # passenger | touch | systemctl | pm2 | supervisor | docker | php | none
SERVICE_NAME=""                       # systemctl type: service name ("" = SITE_DOMAIN)
PM2_APP="all"                         # pm2 type: pm2 app name or "all"
SUPERVISOR_APP="all"                  # supervisor type: app name or "all"
WSGI_FILE="passenger_wsgi.py"         # passenger type: your wsgi entry
DOCKER_COMPOSE=""                     # docker type: path to docker-compose.yml ("" = not set)
PHP_FPM_SERVICE=""                    # php type: php-fpm service name ("" = not set)
APP_SUBDIR=""                         # monorepo: deploy only this subfolder ("" = whole repo)

# ── Database (optional — backup before migrate) ─────────────
DB_BACKUP="no"                        # yes | no
DB_TYPE="mysql"                       # mysql | postgres | sqlite (sqlite: DB_NAME = file path inside APP_DIR)
DB_HOST="localhost"
DB_USER=""
DB_PASS=""
DB_NAME=""

# ── Notifications (optional) ────────────────────────────────
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# ── Health check (optional — "" = skip) ─────────────────────
HEALTH_URL=""                         # e.g. https://your-domain.com/health — "" to skip

# ── Git ─────────────────────────────────────────────────────
DEPLOY_KEY=""                         # path to SSH deploy key ("" = use default ssh)
WORKSPACE_BASE="/home/$SERVER_USER/deploy-workspace"  # clone workspace

# ── Advanced (optional — dynamic defaults) ───────────────────
TOGGLE_FLAG=""                        # "" = default /home/$SERVER_USER/.deploy_github
SKIP_WHEN_FLAG=""                     # "1" = flag exists → deploy skips (toggle mode)
DEFAULT_BRANCH="main"                 # branch used when none is passed
LOG_FILE=""                           # "" = default /home/$SERVER_USER/deploy.log
RSYNC_EXCLUDES=""                     # extra rsync excludes, space-separated ("" = defaults only)
