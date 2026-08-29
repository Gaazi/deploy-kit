#!/bin/bash
# ============================================================
# DEPLOY KIT — detect.sh (fully dynamic — auto-detect project)
# ------------------------------------------------------------
#   /bin/bash detect.sh [branch]
# Looks at your repo and figures out the project itself:
#   - app type (node / python / php / wordpress / ruby / java /
#     go / docker / static)
#   - build command  (npm run build, bundle install, mvn ...)
#   - migration command
#   - restart method
# Prints the recommended config and can apply it to config.sh
# automatically. No technical knowledge needed.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ config.sh not found — run setup.sh first, then keygen.sh"
  exit 1
fi
source "$CONFIG_FILE"

BRANCH="${1:-${DEFAULT_BRANCH:-main}}"
WORKSPACE_BASE="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}"
WORKSPACE="$WORKSPACE_BASE/$BRANCH"

# ── 1. Get the code (clone or update workspace) ─────────────
if [ ! -d "$WORKSPACE/.git" ]; then
  echo "📦 Cloning repo (first time)..."
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
    git clone --branch "$BRANCH" "$REPO_URL" "$WORKSPACE" >/dev/null 2>&1 \
    || { echo "❌ Could not clone $REPO_URL — check REPO_URL + run keygen.sh"; exit 1; }
else
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
    git -C "$WORKSPACE" fetch origin "$BRANCH" >/dev/null 2>&1
  git -C "$WORKSPACE" checkout "$BRANCH" >/dev/null 2>&1
  git -C "$WORKSPACE" reset --hard "origin/$BRANCH" >/dev/null 2>&1
fi
cd "$WORKSPACE" || exit 1

# ── 2. Detect (most specific stack wins) ────────────────────
APP_TYPE=""; BUILD_CMD=""; MIGRATE_CMD=""; RESTART_METHOD=""
DETECTED=()

# Docker
if [ -f Dockerfile ] || [ -f docker-compose.yml ]; then
  APP_TYPE="docker"; RESTART_METHOD="docker"; DETECTED+=("Dockerfile/docker-compose.yml → docker")
fi
# Java
if [ -z "$APP_TYPE" ] && [ -f pom.xml ]; then
  APP_TYPE="java"; RESTART_METHOD="systemctl"; BUILD_CMD="mvn package -DskipTests"; DETECTED+=("pom.xml → java")
elif [ -z "$APP_TYPE" ] && [ -f build.gradle ]; then
  APP_TYPE="java"; RESTART_METHOD="systemctl"; BUILD_CMD="gradle build -x test"; DETECTED+=("build.gradle → java")
fi
# Go
if [ -z "$APP_TYPE" ] && [ -f go.mod ]; then
  APP_TYPE="go"; RESTART_METHOD="systemctl"; BUILD_CMD="go build -o app ."; DETECTED+=("go.mod → go")
fi
# Ruby
if [ -z "$APP_TYPE" ] && [ -f Gemfile ]; then
  APP_TYPE="ruby"; RESTART_METHOD="passenger"; BUILD_CMD="bundle install"
  [ -f bin/rails ] && MIGRATE_CMD="bundle exec rails db:migrate"
  DETECTED+=("Gemfile → ruby")
fi
# Node
if [ -z "$APP_TYPE" ] && [ -f package.json ]; then
  APP_TYPE="node"; RESTART_METHOD="passenger"
  grep -q '"build"' package.json && BUILD_CMD="npm install && npm run build"
  DETECTED+=("package.json → node")
fi
# Python
if [ -z "$APP_TYPE" ] && { [ -f manage.py ] || [ -f requirements.txt ] || [ -f Pipfile ] || [ -f pyproject.toml ] || [ -f passenger_wsgi.py ]; }; then
  APP_TYPE="python"; RESTART_METHOD="passenger"
  [ -f manage.py ] && MIGRATE_CMD="python manage.py migrate"
  [ -f alembic.ini ] && MIGRATE_CMD='$PYTHON_BIN -m alembic upgrade head'
  DETECTED+=("python files → python")
fi
# PHP / WordPress
if [ -z "$APP_TYPE" ] && [ -f wp-config.php ]; then
  APP_TYPE="wordpress"; RESTART_METHOD="php"; DETECTED+=("wp-config.php → wordpress")
elif [ -z "$APP_TYPE" ] && [ -f composer.json ]; then
  APP_TYPE="php"; RESTART_METHOD="php"; DETECTED+=("composer.json → php")
fi
# Static (fallback)
if [ -z "$APP_TYPE" ]; then
  APP_TYPE="static"; RESTART_METHOD="none"; DETECTED+=("no framework files → static")
fi

# ── 3. Show results ─────────────────────────────────────────
echo ""
echo "═══ AUTO-DETECTED — your project ═══"
for d in "${DETECTED[@]}"; do echo "  🔎 $d"; done
echo ""
echo "  APP_TYPE        = $APP_TYPE"
echo "  BUILD_CMD       = ${BUILD_CMD:-— (none)}"
echo "  MIGRATE_CMD     = ${MIGRATE_CMD:-— (none)}"
echo "  RESTART_METHOD  = $RESTART_METHOD"
echo ""

# ── 4. Apply to config.sh? ─────────────────────────────────
read -rp "Apply these to config.sh? (yes/no) [yes]: " ANS
case "$ANS" in
  ""|y|Y|yes|YES|Yes)
    apply_key() {  # $1=KEY  $2=value
      local k="$1" v="$2"
      if grep -q "^$k=" "$CONFIG_FILE"; then
        sed -i "s|^$k=.*|$k=\"$v\"|" "$CONFIG_FILE"
      else
        echo "$k=\"$v\"" >> "$CONFIG_FILE"
      fi
    }
    apply_key APP_TYPE "$APP_TYPE"
    apply_key BUILD_CMD "$BUILD_CMD"
    apply_key MIGRATE_CMD "$MIGRATE_CMD"
    apply_key RESTART_METHOD "$RESTART_METHOD"
    echo "✅ Applied to config.sh"
    echo "   Next: /bin/bash auto_deploy.sh $BRANCH"
    ;;
  *)
    echo "⏭️  Not applied — copy the values above into config.sh manually."
    ;;
esac
