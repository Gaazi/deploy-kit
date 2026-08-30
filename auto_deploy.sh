#!/bin/bash
# ============================================================
# DEPLOY KIT — auto_deploy.sh (GENERIC)
# ------------------------------------------------------------
# Deploy for any project — all settings come from config.sh.
#   usage: /bin/bash auto_deploy.sh <branch>
#
# Flow: git fetch → rsync → [build] → [db backup] → [migrate]
#       → [restart] → [health check] → [telegram]
#
# [ ] = optional — leave empty in config to skip.
# No project-specific info — everything comes from config.sh.
# ============================================================

# ── Config load ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ config.sh not found — first run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

BRANCH="${1:-${DEFAULT_BRANCH:-main}}"
APP_DIR="${APP_DIR:-/home/$SERVER_USER/app}"
WORKSPACE_BASE="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}"
WORKSPACE="$WORKSPACE_BASE/$BRANCH"
LOG="${LOG_FILE:-/home/$SERVER_USER/deploy.log}"
NOW="$(date '+%F %T')"

DEPLOY_START_TIME="$(date +%s)"

# ── Log rotation (keep it light — 1MB cap) ─────────────────
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  mv "$LOG" "$LOG.1" 2>/dev/null
fi

# ── Required check (only these 2 required — rest optional) ─
if [ -z "$REPO_URL" ] || [ -z "$APP_DIR" ]; then
  echo "❌ config.sh: REPO_URL and APP_DIR are required — everything else is optional."
  exit 1
fi

log() { echo "$NOW: $1" >> "$LOG"; }

# ── Multi-channel notification helper (Telegram, Discord, Slack, Email) ──
notify() {
  local html_msg="$1"
  local subject="${2:-Deploy Notification ($SITE_DOMAIN)}"
  local plain_msg
  plain_msg="$(echo "$html_msg" | sed -e 's/<[^>]*>//g')"

  # 1. Telegram (HTML supported)
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -s -o /dev/null "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$html_msg" \
      --data-urlencode "parse_mode=HTML" >/dev/null 2>&1 || true
  fi

  # 2. Discord Webhook (JSON text)
  if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    local discord_json
    discord_json="$(printf '%s' "$plain_msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
    discord_json="${discord_json%\\n}"
    curl -s -o /dev/null -H "Content-Type: application/json" \
      -d "{\"content\": \"$discord_json\"}" \
      "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi

  # 3. Slack Webhook (JSON text)
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    local slack_json
    slack_json="$(printf '%s' "$plain_msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
    slack_json="${slack_json%\\n}"
    curl -s -o /dev/null -H "Content-Type: application/json" \
      -d "{\"text\": \"$slack_json\"}" \
      "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi

  # 4. Email Alert (via mail or sendmail)
  if [ -n "$ALERT_EMAIL" ]; then
    if command -v mail >/dev/null 2>&1; then
      printf '%s\n' "$plain_msg" | mail -s "$subject" "$ALERT_EMAIL" >/dev/null 2>&1 || true
    elif command -v sendmail >/dev/null 2>&1; then
      printf "To: %s\nSubject: %s\n\n%s\n" "$ALERT_EMAIL" "$subject" "$plain_msg" | sendmail -t >/dev/null 2>&1 || true
    fi
  fi
}

# ── 0. GitHub-mode flag (optional toggle — from config) ──────
TOGGLE_FLAG="${TOGGLE_FLAG:-/home/$SERVER_USER/.deploy_github}"
if [ -f "$TOGGLE_FLAG" ] && [ -n "$SKIP_WHEN_FLAG" ]; then
  log "Skipped — flag present ($TOGGLE_FLAG)"
  exit 0
fi

# ── Deploy lock (concurrent pushes can't clash) ─────────────
# mkdir-based lock: portable, no extra dependencies.
# Stale lock (dead PID) is cleaned automatically.
LOCK_DIR="$WORKSPACE_BASE/.deploy-lock"
mkdir -p "$WORKSPACE_BASE"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  LOCK_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  # stale if: pid file empty (crashed between mkdir and pid write) OR pid is a dead process
  if [ ! -s "$LOCK_DIR/pid" ] || { [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; }; then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "⏳ Another deploy is running — skipped"; exit 0; }
  else
    echo "⏳ Another deploy is running — this one skipped (the running deploy picks up the latest commit)"
    exit 0
  fi
fi
echo $$ > "$LOCK_DIR/pid" 2>/dev/null
trap 'rm -rf "$LOCK_DIR" 2>/dev/null' EXIT

# ── 1. Git workspace ────────────────────────────────────────
if [ ! -d "$WORKSPACE/.git" ]; then
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
    # --single-branch: only this branch's history — minimum network + disk
    git clone --single-branch --branch "$BRANCH" "$REPO_URL" "$WORKSPACE" >> "$LOG" 2>&1
else
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i $DEPLOY_KEY -o StrictHostKeyChecking=no}" \
    git -C "$WORKSPACE" fetch origin "$BRANCH" >> "$LOG" 2>&1
fi

# Safety guard: abort if the branch is missing on the remote (clone/fetch failed).
# Never rsync --delete from a broken workspace — it would wipe the app.
if ! git -C "$WORKSPACE" rev-parse --verify -q "origin/$BRANCH" >/dev/null 2>&1; then
  echo "❌ Branch '$BRANCH' not found on remote ($REPO_URL) — deploy aborted, app untouched" | tee -a "$LOG"
  exit 1
fi

git -C "$WORKSPACE" checkout "$BRANCH" >> "$LOG" 2>&1
git -C "$WORKSPACE" reset --hard "origin/$BRANCH" >> "$LOG" 2>&1
NEW_SHA="$(git -C "$WORKSPACE" rev-parse HEAD)"

# Safety guard: a real commit must be resolved before touching the app dir.
if [ -z "$NEW_SHA" ]; then
  echo "❌ Could not resolve git HEAD — deploy aborted, app untouched" | tee -a "$LOG"
  exit 1
fi
OLD_SHA="$(cat "$WORKSPACE/.deployed_sha" 2>/dev/null || echo none)"

if [ "$OLD_SHA" = "$NEW_SHA" ]; then
  log "No new commit on $BRANCH ($NEW_SHA) — skip"
  echo "⏭️ No new commit on $BRANCH — skip (deployed: ${NEW_SHA:0:10})"
  exit 0
fi

COMMIT_AUTHOR="$(git -C "$WORKSPACE" log -1 --pretty=format:'%an' "$NEW_SHA" 2>/dev/null || echo 'Unknown')"
COMMIT_MSG="$(git -C "$WORKSPACE" log -1 --pretty=format:'%s' "$NEW_SHA" 2>/dev/null || echo '')"

notify "🚀 <b>Deploy started</b> ($SITE_DOMAIN · $BRANCH)
<code>${OLD_SHA:0:10}</code> → <code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
💬 <i>$COMMIT_MSG</i>" "Deploy Started: $SITE_DOMAIN ($BRANCH)"
log "Deploying $BRANCH: $OLD_SHA -> $NEW_SHA ($COMMIT_AUTHOR: $COMMIT_MSG)"

# ── 2. Rsync to app dir ─────────────────────────────────────
mkdir -p "$APP_DIR"
RSYNC_ARGS=(--exclude='/.git/' --exclude='.env' --exclude='*.db' --exclude='*.sqlite3' \
  --exclude='__pycache__/' --exclude='*.pyc' --exclude='node_modules/' \
  --exclude='venv/' --exclude='.venv/' --exclude='*.log' --exclude='media/' \
  --exclude='backups/' --exclude='tests/')
for ex in $RSYNC_EXCLUDES; do RSYNC_ARGS+=(--exclude="$ex"); done
# APP_SUBDIR (optional): deploy only one subfolder (monorepos)
SRC_DIR="$WORKSPACE"
[ -n "$APP_SUBDIR" ] && SRC_DIR="$WORKSPACE/$APP_SUBDIR"
if [ ! -d "$SRC_DIR" ]; then
  echo "❌ APP_SUBDIR not found: $SRC_DIR — deploy aborted, app untouched" | tee -a "$LOG"
  exit 1
fi
rsync -az --delete "${RSYNC_ARGS[@]}" "$SRC_DIR/" "$APP_DIR/" >> "$LOG" 2>&1

# ── 3. Build (if configured) ────────────────────────────────
if [ -n "$BUILD_CMD" ]; then
  log "Running build: $BUILD_CMD"
  if ! (cd "$APP_DIR" && eval "$BUILD_CMD") >> "$LOG" 2>&1; then
    notify "❌ <b>Deploy FAILED (Build)</b> ($SITE_DOMAIN · $BRANCH) — build failed
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
Check server log: $LOG" "Deploy Build FAILED: $SITE_DOMAIN ($BRANCH)"
    echo "❌ Build FAILED — deploy aborted. If the site is broken, run: rollback.sh $BRANCH" | tee -a "$LOG"
    exit 1
  fi
fi

# ── 4. DB backup (optional) ─────────────────────────────────
# sqlite needs no DB_USER — only DB_NAME (file path inside APP_DIR)
if [ "$DB_BACKUP" = "yes" ] && [ -n "$DB_NAME" ]; then
  BK_DIR="$APP_DIR/backups/predeploy"
  mkdir -p "$BK_DIR"
  TS="$(date +%Y%m%d_%H%M%S)"
  KEEP="${DB_BACKUP_KEEP:-7}"   # how many old dumps to keep (lighter disk = smaller number)
  case "$KEEP" in ''|*[!0-9]*) KEEP=7;; esac   # safety: non-numeric → default 7
  [ "$KEEP" -lt 1 ] && KEEP=1                  # safety: 0 would delete ALL backups
  if [ "$DB_TYPE" = "mysql" ] && [ -n "$DB_USER" ] && command -v mysqldump >/dev/null 2>&1; then
    MYSQL_PWD="$DB_PASS" mysqldump -h "$DB_HOST" -u "$DB_USER" --single-transaction "$DB_NAME" \
      > "$BK_DIR/${SITE_DOMAIN}_${TS}.sql" 2>>"$LOG" \
      && ls -1t "$BK_DIR"/*.sql 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f 2>/dev/null
    log "DB backup: $BK_DIR/${SITE_DOMAIN}_${TS}.sql (last $KEEP kept)"
  elif [ "$DB_TYPE" = "postgres" ] && [ -n "$DB_USER" ] && command -v pg_dump >/dev/null 2>&1; then
    PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" \
      > "$BK_DIR/${SITE_DOMAIN}_${TS}.sql" 2>>"$LOG" \
      && ls -1t "$BK_DIR"/*.sql 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f 2>/dev/null
    log "DB backup: $BK_DIR/${SITE_DOMAIN}_${TS}.sql (last $KEEP kept)"
  elif [ "$DB_TYPE" = "sqlite" ] && [ -f "$APP_DIR/$DB_NAME" ]; then
    cp "$APP_DIR/$DB_NAME" "$BK_DIR/${SITE_DOMAIN}_${TS}.db" 2>>"$LOG" \
      && ls -1t "$BK_DIR"/*.db 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f 2>/dev/null
    log "DB backup (sqlite): $BK_DIR/${SITE_DOMAIN}_${TS}.db (last $KEEP kept)"
  fi
fi

# ── 5. Migrate (if configured) ──────────────────────────────
if [ -n "$MIGRATE_CMD" ]; then
  log "Running migrate: $MIGRATE_CMD"
  if ! (cd "$APP_DIR" && eval "$MIGRATE_CMD") >> "$LOG" 2>&1; then
    notify "❌ <b>Deploy FAILED (Migrate)</b> ($SITE_DOMAIN · $BRANCH) — migrate failed
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
Check server log: $LOG" "Deploy Migration FAILED: $SITE_DOMAIN ($BRANCH)"
    echo "❌ Migrate FAILED — deploy aborted. Restore the DB from backups/predeploy/, then run: rollback.sh $BRANCH" | tee -a "$LOG"
    exit 1
  fi
fi

# ── 6. Restart (optional — "" / "none" = skip) ───────────────
case "$RESTART_METHOD" in
  passenger)  mkdir -p "$APP_DIR/tmp" && touch "$APP_DIR/tmp/restart.txt" ;;
  touch)      touch "$APP_DIR/restart.txt" ;;
  systemctl)  systemctl restart "${SERVICE_NAME:-$SITE_DOMAIN}" 2>>"$LOG" || true ;;
  pm2)        pm2 restart "${PM2_APP:-all}" >> "$LOG" 2>&1 || true ;;
  supervisor) supervisorctl restart "${SUPERVISOR_APP:-all}" >> "$LOG" 2>&1 || true ;;
  docker)     if [ -n "$DOCKER_COMPOSE" ]; then
                (cd "$APP_DIR" && docker compose -f "$DOCKER_COMPOSE" down && docker compose -f "$DOCKER_COMPOSE" up -d --build) >> "$LOG" 2>&1
              else
                (cd "$APP_DIR" && docker compose up -d --build) >> "$LOG" 2>&1
              fi ;;
  php)        if [ -n "$PHP_FPM_SERVICE" ]; then
                systemctl reload "$PHP_FPM_SERVICE" 2>>"$LOG" || service "$PHP_FPM_SERVICE" reload 2>>"$LOG" || true
              fi ;;
  ""|none)    : ;;
esac
[ -n "$RESTART_METHOD" ] && [ "$RESTART_METHOD" != "none" ] && log "Restart done ($RESTART_METHOD)"

# ── 7. Record SHA ───────────────────────────────────────────
[ -f "$WORKSPACE/.deployed_sha" ] && cp "$WORKSPACE/.deployed_sha" "$WORKSPACE/.previous_sha" 2>/dev/null || true
echo "$NEW_SHA" > "$WORKSPACE/.deployed_sha"

DEPLOY_DURATION=$(( $(date +%s) - DEPLOY_START_TIME ))

# ── 8. Health check (optional — empty SITE_DOMAIN/HEALTH_URL = skip) ─
HEALTH_URL="${HEALTH_URL:-https://$SITE_DOMAIN/}"
if [ -n "$HEALTH_URL" ] && [ "$HEALTH_URL" != "https:///" ]; then
  sleep "${HEALTH_WAIT:-8}"  # let the app boot before checking
  RETRY="${HEALTH_RETRY:-3}"   # how many times to try (app may need a moment)
  OK=0
  i=1
  while [ "$i" -le "$RETRY" ]; do
    if curl -fsS -m 15 "$HEALTH_URL" >/dev/null 2>&1; then OK=1; break; fi
    i=$((i+1))
    [ "$i" -le "$RETRY" ] && sleep 5
  done
  if [ "$OK" -eq 1 ]; then
    notify "✅ <b>Deploy successful</b> ($SITE_DOMAIN · $BRANCH) — health OK
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
💬 <i>$COMMIT_MSG</i>
⏱️ Time: ${DEPLOY_DURATION}s" "Deploy Successful: $SITE_DOMAIN ($BRANCH)"
    log "Health OK"
  else
    log "Health FAILED"
    if [ "${AUTO_ROLLBACK_ON_FAIL:-no}" = "yes" ] || [ "${AUTO_ROLLBACK_ON_FAIL:-false}" = "true" ] || [ "${AUTO_ROLLBACK_ON_FAIL:-0}" = "1" ]; then
      PREV_SHA="$(cat "$WORKSPACE/.previous_sha" 2>/dev/null || echo '')"
      if [ -n "$PREV_SHA" ]; then
        log "Health FAILED — initiating auto-rollback to $PREV_SHA"
        DEPLOY_LOCK_HELD=1 /bin/bash "${SCRIPT_DIR}/rollback.sh" "$BRANCH" "$PREV_SHA" >> "$LOG" 2>&1 || true
        notify "⚠️ <b>Health FAILED — Auto-rollback executed</b> ($SITE_DOMAIN · $BRANCH)
Rolled back from <code>${NEW_SHA:0:10}</code> to <code>${PREV_SHA:0:10}</code>
Check server log: $LOG" "Deploy Health FAILED (Auto-Rolled Back): $SITE_DOMAIN ($BRANCH)"
      else
        log "Health FAILED — no previous version available for auto-rollback"
        notify "❌ <b>Deploy done but health FAILED</b> ($SITE_DOMAIN · $BRANCH) — first deploy, no rollback target
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
Check server log: $LOG" "Deploy Health FAILED: $SITE_DOMAIN ($BRANCH)"
      fi
    else
      notify "❌ <b>Deploy done but health FAILED</b> ($SITE_DOMAIN · $BRANCH) — run rollback
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
Check server log: $LOG" "Deploy Health FAILED: $SITE_DOMAIN ($BRANCH)"
    fi
  fi
else
  notify "✅ <b>Deploy successful</b> ($SITE_DOMAIN · $BRANCH)
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
💬 <i>$COMMIT_MSG</i>
⏱️ Time: ${DEPLOY_DURATION}s" "Deploy Successful: $SITE_DOMAIN ($BRANCH)"
  log "Health check skipped (no URL)"
fi

echo "✅ Deploy complete: $BRANCH @ ${NEW_SHA:0:10} (${DEPLOY_DURATION}s)"
