#!/bin/bash
# ============================================================
# DEPLOY KIT — rollback.sh (GENERIC)
# ------------------------------------------------------------
# Pichle commit par wapas jao (ya kisi bhi SHA par).
#   usage: /bin/bash rollback.sh <branch> [commit-sha]
#   agar sha na do to last deployed SHA par wapas.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || { echo "❌ config.sh not found"; exit 1; }

BRANCH="${1:-main}"
APP_DIR="${APP_DIR:-/home/$SERVER_USER/app}"
WORKSPACE="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}/$BRANCH"
TARGET_SHA="${2:-$(cat "$WORKSPACE/.deployed_sha" 2>/dev/null)}"

if [ -z "$TARGET_SHA" ]; then
  echo "❌ Target SHA not found — provide a commit SHA"
  exit 1
fi

echo "⏪ Rolling back $BRANCH to $TARGET_SHA"

GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
  git -C "$WORKSPACE" fetch origin "$BRANCH" >> /dev/null 2>&1
git -C "$WORKSPACE" checkout "$TARGET_SHA" >> /dev/null 2>&1

rsync -az --delete \
  --exclude='/.git/' --exclude='.env' --exclude='*.db' --exclude='node_modules/' \
  --exclude='venv/' --exclude='.venv/' --exclude='media/' --exclude='backups/' \
  "$WORKSPACE/" "$APP_DIR/" >> /dev/null 2>&1

# restore pre-migration DB dump agar ho
LATEST_DUMP="$(ls -1t "$APP_DIR/backups/predeploy/"*.sql 2>/dev/null | head -1)"
if [ -n "$LATEST_DUMP" ] && [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
  echo "🔄 Restoring DB: $LATEST_DUMP"
  if [ "$DB_TYPE" = "mysql" ]; then
    MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" < "$LATEST_DUMP"
  elif [ "$DB_TYPE" = "postgres" ]; then
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" < "$LATEST_DUMP"
  fi
fi

# restart (optional)
case "$RESTART_METHOD" in
  passenger) mkdir -p "$APP_DIR/tmp" && touch "$APP_DIR/tmp/restart.txt" ;;
  touch)     touch "$APP_DIR/restart.txt" ;;
  systemctl) systemctl restart "$SITE_DOMAIN" 2>/dev/null || true ;;
  ""|none)   : ;;
esac

echo "✅ Rolled back to $TARGET_SHA + restarted"
