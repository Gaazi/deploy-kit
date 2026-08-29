#!/bin/bash
# ============================================================
# DEPLOY KIT — auto_deploy.sh (GENERIC)
# ------------------------------------------------------------
# Kisi bhi project ke liye deploy — config.sh se sab settings.
#   usage: /bin/bash auto_deploy.sh <branch>
#
# Flow: git fetch → rsync → [build] → [db backup] → [migrate]
#       → [restart] → health check → [telegram]
#
# Koi project-specific info nahi — sab config.sh se aata hai.
# ============================================================

# ── Config load ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ config.sh nahi mila — pehle: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

BRANCH="${1:-${DEFAULT_BRANCH:-main}}"
APP_DIR="${APP_DIR:-/home/$SERVER_USER/app}"
WORKSPACE="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}/$BRANCH"
LOG="${LOG_FILE:-/home/$SERVER_USER/deploy.log}"
NOW="$(date '+%F %T')"

log() { echo "$NOW: $1" >> "$LOG"; }

notify() {
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -s -o /dev/null "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$1" --data-urlencode "parse_mode=HTML" >/dev/null 2>&1 || true
  fi
}

# ── 0. GitHub-mode flag (optional toggle — config se) ───────
TOGGLE_FLAG="${TOGGLE_FLAG:-/home/$SERVER_USER/.deploy_github}"
if [ -f "$TOGGLE_FLAG" ] && [ -n "$SKIP_WHEN_FLAG" ]; then
  log "Skipped — flag present ($TOGGLE_FLAG)"
  exit 0
fi

# ── 1. Git workspace ────────────────────────────────────────
if [ ! -d "$WORKSPACE/.git" ]; then
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
    git clone --branch "$BRANCH" "$REPO_URL" "$WORKSPACE" >> "$LOG" 2>&1
else
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
    git -C "$WORKSPACE" fetch origin "$BRANCH" >> "$LOG" 2>&1
fi
git -C "$WORKSPACE" checkout "$BRANCH" >> "$LOG" 2>&1
git -C "$WORKSPACE" reset --hard "origin/$BRANCH" >> "$LOG" 2>&1
NEW_SHA="$(git -C "$WORKSPACE" rev-parse HEAD)"
OLD_SHA="$(cat "$WORKSPACE/.deployed_sha" 2>/dev/null || echo none)"

if [ "$OLD_SHA" = "$NEW_SHA" ]; then
  log "No new commit on $BRANCH ($NEW_SHA) — skip"
  exit 0
fi

notify "🚀 <b>Deploy started</b> ($SITE_DOMAIN · $BRANCH)
<code>$OLD_SHA</code> → <code>${NEW_SHA:0:10}</code>"
log "Deploying $BRANCH: $OLD_SHA -> $NEW_SHA"

# ── 2. Rsync to app dir ─────────────────────────────────────
mkdir -p "$APP_DIR"
rsync -az --delete \
  --exclude='/.git/' --exclude='.env' --exclude='*.db' --exclude='*.sqlite3' \
  --exclude='__pycache__/' --exclude='*.pyc' --exclude='node_modules/' \
  --exclude='venv/' --exclude='.venv/' --exclude='*.log' --exclude='media/' \
  --exclude='backups/' --exclude='tests/' \
  "$WORKSPACE/" "$APP_DIR/" >> "$LOG" 2>&1

# ── 3. Build (if configured) ────────────────────────────────
if [ -n "$BUILD_CMD" ]; then
  log "Running build: $BUILD_CMD"
  (cd "$APP_DIR" && eval "$BUILD_CMD") >> "$LOG" 2>&1
fi

# ── 4. DB backup (optional) ─────────────────────────────────
if [ "$DB_BACKUP" = "yes" ] && [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
  BK_DIR="$APP_DIR/backups/predeploy"
  mkdir -p "$BK_DIR"
  TS="$(date +%Y%m%d_%H%M%S)"
  if [ "$DB_TYPE" = "mysql" ] && command -v mysqldump >/dev/null 2>&1; then
    MYSQL_PWD="$DB_PASS" mysqldump -h "$DB_HOST" -u "$DB_USER" --single-transaction "$DB_NAME" \
      > "$BK_DIR/${SITE_DOMAIN}_${TS}.sql" 2>>"$LOG" \
      && ls -1t "$BK_DIR"/*.sql 2>/dev/null | tail -n +8 | xargs -r rm -f 2>/dev/null
    log "DB backup: $BK_DIR/${SITE_DOMAIN}_${TS}.sql (last 7 kept)"
  elif [ "$DB_TYPE" = "postgres" ] && command -v pg_dump >/dev/null 2>&1; then
    PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" \
      > "$BK_DIR/${SITE_DOMAIN}_${TS}.sql" 2>>"$LOG"
    log "DB backup: $BK_DIR/${SITE_DOMAIN}_${TS}.sql"
  fi
fi

# ── 5. Migrate (if configured) ──────────────────────────────
if [ -n "$MIGRATE_CMD" ]; then
  log "Running migrate: $MIGRATE_CMD"
  (cd "$APP_DIR" && eval "$MIGRATE_CMD") >> "$LOG" 2>&1
fi

# ── 6. Restart ──────────────────────────────────────────────
case "$RESTART_METHOD" in
  passenger) mkdir -p "$APP_DIR/tmp" && touch "$APP_DIR/tmp/restart.txt" ;;
  touch)     touch "$APP_DIR/restart.txt" ;;
  systemctl) systemctl restart "$SITE_DOMAIN" 2>>"$LOG" || true ;;
  docker)    if [ -n "$DOCKER_COMPOSE" ]; then
               (cd "$APP_DIR" && docker compose -f "$DOCKER_COMPOSE" down && docker compose -f "$DOCKER_COMPOSE" up -d --build) >> "$LOG" 2>&1
             else
               (cd "$APP_DIR" && docker compose up -d --build) >> "$LOG" 2>&1
             fi ;;
  php)       if [ -n "$PHP_FPM_SERVICE" ]; then
               systemctl reload "$PHP_FPM_SERVICE" 2>>"$LOG" || service "$PHP_FPM_SERVICE" reload 2>>"$LOG" || true
             fi ;;
  none)      : ;;
esac
log "Restart done ($RESTART_METHOD)"

# ── 7. Record SHA ───────────────────────────────────────────
echo "$NEW_SHA" > "$WORKSPACE/.deployed_sha"

# ── 8. Health check ─────────────────────────────────────────
sleep 8
if curl -fsS "https://$SITE_DOMAIN/" >/dev/null 2>&1 || curl -fsS "http://127.0.0.1:8000/" >/dev/null 2>&1; then
  notify "✅ <b>Deploy successful</b> ($SITE_DOMAIN · $BRANCH) — health OK
<code>${NEW_SHA:0:10}</code>"
  log "Health OK"
else
  notify "❌ <b>Deploy done but health FAILED</b> ($SITE_DOMAIN) — rollback karo"
  log "Health FAILED"
fi

echo "✅ Deploy complete: $BRANCH @ ${NEW_SHA:0:10}"
