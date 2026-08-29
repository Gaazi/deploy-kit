#!/bin/bash
# ============================================================
# DEPLOY KIT — rollback.sh (GENERIC)
# ------------------------------------------------------------
# Go back to a previous commit (or any SHA).
#   usage: /bin/bash rollback.sh <branch> [commit-sha]
#   no sha given → back to the last deployed SHA.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || { echo "❌ config.sh not found"; exit 1; }

BRANCH="${1:-${DEFAULT_BRANCH:-main}}"
APP_DIR="${APP_DIR:-/home/$SERVER_USER/app}"
WORKSPACE_BASE="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}"
WORKSPACE="$WORKSPACE_BASE/$BRANCH"
LOG="${LOG_FILE:-/home/$SERVER_USER/deploy.log}"
TARGET_SHA="${2:-$(cat "$WORKSPACE/.deployed_sha" 2>/dev/null)}"

# ── Deploy lock (same lock as auto_deploy.sh — no clash) ────
LOCK_DIR="$WORKSPACE_BASE/.deploy-lock"
mkdir -p "$WORKSPACE_BASE"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  LOCK_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  # stale if: pid file empty (crashed between mkdir and pid write) OR pid is a dead process
  if [ ! -s "$LOCK_DIR/pid" ] || { [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; }; then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "❌ A deploy is running — wait, then retry rollback"; exit 1; }
  else
    echo "❌ A deploy is currently running — wait for it to finish, then retry rollback"
    exit 1
  fi
fi
echo $$ > "$LOCK_DIR/pid" 2>/dev/null
trap 'rm -rf "$LOCK_DIR" 2>/dev/null' EXIT

if [ -z "$TARGET_SHA" ]; then
  echo "❌ Target SHA not found — provide a commit SHA"
  exit 1
fi

echo "⏪ Rolling back $BRANCH to $TARGET_SHA"
echo "$(date '+%F %T'): Rollback $BRANCH to $TARGET_SHA" >> "$LOG"

GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
  git -C "$WORKSPACE" fetch origin "$BRANCH" >> "$LOG" 2>&1

# Safety guard: the target SHA must exist locally before we touch the app dir.
if ! git -C "$WORKSPACE" rev-parse --verify -q "$TARGET_SHA" >/dev/null 2>&1; then
  echo "❌ SHA $TARGET_SHA not found in workspace — rollback aborted, app untouched" | tee -a "$LOG"
  exit 1
fi

git -C "$WORKSPACE" checkout "$TARGET_SHA" >> "$LOG" 2>&1

# Same excludes as auto_deploy.sh so the app dir stays consistent.
RSYNC_ARGS=(--exclude='/.git/' --exclude='.env' --exclude='*.db' --exclude='*.sqlite3' \
  --exclude='__pycache__/' --exclude='*.pyc' --exclude='node_modules/' \
  --exclude='venv/' --exclude='.venv/' --exclude='*.log' --exclude='media/' \
  --exclude='backups/' --exclude='tests/')
for ex in $RSYNC_EXCLUDES; do RSYNC_ARGS+=(--exclude="$ex"); done
# APP_SUBDIR (optional): deploy only one subfolder (monorepos)
SRC_DIR="$WORKSPACE"
[ -n "$APP_SUBDIR" ] && SRC_DIR="$WORKSPACE/$APP_SUBDIR"
if [ ! -d "$SRC_DIR" ]; then
  echo "❌ APP_SUBDIR not found: $SRC_DIR — rollback aborted, app untouched" | tee -a "$LOG"
  exit 1
fi
rsync -az --delete "${RSYNC_ARGS[@]}" "$SRC_DIR/" "$APP_DIR/" >> "$LOG" 2>&1

# rebuild (only if the app has a build step)
if [ -n "$BUILD_CMD" ]; then
  echo "🔨 Rebuilding: $BUILD_CMD"
  (cd "$APP_DIR" && eval "$BUILD_CMD") >> "$LOG" 2>&1
fi

# restore pre-migration DB dump if present
LATEST_DUMP="$(ls -1t "$APP_DIR/backups/predeploy/"*.sql "$APP_DIR/backups/predeploy/"*.db 2>/dev/null | head -1)"
# sqlite needs no DB_USER — only DB_NAME (file path inside APP_DIR)
if [ -n "$LATEST_DUMP" ] && [ -n "$DB_NAME" ]; then
  echo "🔄 Restoring DB: $LATEST_DUMP"
  if [ "$DB_TYPE" = "mysql" ] && [ -n "$DB_USER" ]; then
    MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" < "$LATEST_DUMP"
  elif [ "$DB_TYPE" = "postgres" ] && [ -n "$DB_USER" ]; then
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" < "$LATEST_DUMP"
  elif [ "$DB_TYPE" = "sqlite" ]; then
    cp "$LATEST_DUMP" "$APP_DIR/$DB_NAME"
  fi
fi

# restart (optional)
case "$RESTART_METHOD" in
  passenger)  mkdir -p "$APP_DIR/tmp" && touch "$APP_DIR/tmp/restart.txt" ;;
  touch)      touch "$APP_DIR/restart.txt" ;;
  systemctl)  systemctl restart "${SERVICE_NAME:-$SITE_DOMAIN}" 2>>"$LOG" || true ;;
  pm2)        pm2 restart "${PM2_APP:-all}" >> "$LOG" 2>&1 || true ;;
  supervisor) supervisorctl restart "${SUPERVISOR_APP:-all}" >> "$LOG" 2>&1 || true ;;
  docker)     if [ -n "$DOCKER_COMPOSE" ]; then
                (cd "$APP_DIR" && docker compose -f "$DOCKER_COMPOSE" up -d --build) >> "$LOG" 2>&1
              else
                (cd "$APP_DIR" && docker compose up -d --build) >> "$LOG" 2>&1
              fi ;;
  php)        if [ -n "$PHP_FPM_SERVICE" ]; then
                systemctl reload "$PHP_FPM_SERVICE" 2>>"$LOG" || service "$PHP_FPM_SERVICE" reload 2>>"$LOG" || true
              fi ;;
  ""|none)    : ;;
esac

echo "✅ Rolled back to $TARGET_SHA + restarted"
