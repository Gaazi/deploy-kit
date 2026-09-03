#!/bin/bash
# ============================================================
# DEPLOY KIT — rollback.sh (GENERIC)
# ------------------------------------------------------------
# Go back to a previous commit (or any SHA).
#   usage: /bin/bash rollback.sh <branch> [commit-sha]
#   no sha given → back to the last deployed SHA.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH_ARG="${1:-}"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
# Branch-specific config: if config.<branch>.sh exists, use it (e.g. config.dev.sh, config.main.sh)
if [ -n "$BRANCH_ARG" ] && [ -f "${SCRIPT_DIR}/config.${BRANCH_ARG}.sh" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.${BRANCH_ARG}.sh"
fi
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || { echo "❌ $(basename "$CONFIG_FILE") not found"; exit 1; }

BRANCH="${1:-${DEFAULT_BRANCH:-main}}"
if [ -z "$BRANCH_ARG" ] && [ -f "${SCRIPT_DIR}/config.${BRANCH}.sh" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.${BRANCH}.sh"
  source "$CONFIG_FILE"
fi
USER_HOME="${HOME:-${SERVER_USER:+/home/$SERVER_USER}}"
USER_HOME="${USER_HOME:-/home/$SERVER_USER}"
APP_DIR="${APP_DIR:-$USER_HOME/app}"
WORKSPACE_BASE="${WORKSPACE_BASE:-$USER_HOME/deploy-workspace}"
WORKSPACE="$WORKSPACE_BASE/$BRANCH"
LOG="${LOG_FILE:-$USER_HOME/deploy.log}"
TARGET_SHA="${2:-$(cat "$WORKSPACE/.deployed_sha" 2>/dev/null)}"

# ── Multi-channel notification helper (Telegram, Discord, Slack, Email) ──
notify() {
  local html_msg="$1"
  local subject="${2:-Rollback Notification ($SITE_DOMAIN)}"
  local plain_msg
  plain_msg="$(echo "$html_msg" | sed -e 's/<[^>]*>//g')"

  # 1. Telegram
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -s -o /dev/null "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$html_msg" \
      --data-urlencode "parse_mode=HTML" >/dev/null 2>&1 || true
  fi

  # 2. Discord Webhook
  if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    local discord_json
    discord_json="$(printf '%s' "$plain_msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
    discord_json="${discord_json%\\n}"
    curl -s -o /dev/null -H "Content-Type: application/json" \
      -d "{\"content\": \"$discord_json\"}" \
      "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi

  # 3. Slack Webhook
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    local slack_json
    slack_json="$(printf '%s' "$plain_msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
    slack_json="${slack_json%\\n}"
    curl -s -o /dev/null -H "Content-Type: application/json" \
      -d "{\"text\": \"$slack_json\"}" \
      "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi

  # 4. Email Alert
  if [ -n "$ALERT_EMAIL" ]; then
    if command -v mail >/dev/null 2>&1; then
      printf '%s\n' "$plain_msg" | mail -s "$subject" "$ALERT_EMAIL" >/dev/null 2>&1 || true
    elif command -v sendmail >/dev/null 2>&1; then
      printf "To: %s\nSubject: %s\n\n%s\n" "$ALERT_EMAIL" "$subject" "$plain_msg" | sendmail -t >/dev/null 2>&1 || true
    fi
  fi
}

# ── Deploy lock (same lock as auto_deploy.sh — no clash) ────
LOCK_DIR="$WORKSPACE_BASE/.deploy-lock"
mkdir -p "$WORKSPACE_BASE"
LOCK_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
if [ "${DEPLOY_LOCK_HELD:-0}" != "1" ] && [ "$LOCK_PID" != "$PPID" ]; then
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # stale if: pid file empty (crashed between mkdir and pid write) OR pid is a dead process
    if [ ! -s "$LOCK_DIR/pid" ] || { [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; }; then
      # atomic: rename stale lock to temp, then mkdir — no gap for races
      mv "$LOCK_DIR" "$LOCK_DIR.stale.$$" 2>/dev/null
      rm -rf "$LOCK_DIR.stale.$$" 2>/dev/null &
      mkdir "$LOCK_DIR" 2>/dev/null || { echo "❌ A deploy is running — wait, then retry rollback"; exit 1; }
    else
      echo "❌ A deploy is currently running — wait for it to finish, then retry rollback"
      exit 1
    fi
  fi
  echo $$ > "$LOCK_DIR/pid" 2>/dev/null
  trap 'rm -rf "$LOCK_DIR" 2>/dev/null' EXIT
fi

if [ -z "$TARGET_SHA" ]; then
  echo "❌ Target SHA not found — provide a commit SHA"
  exit 1
fi

echo "⏪ Rolling back $BRANCH to $TARGET_SHA"
echo "$(date '+%F %T'): Rollback $BRANCH to $TARGET_SHA" >> "$LOG"

GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i \"$DEPLOY_KEY\" -o StrictHostKeyChecking=no}" \
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
  --exclude='backups/' --exclude='tests/' --exclude='deploy_kit/' --exclude='deploy-kit/' \
  --exclude='config.*.sh' --exclude='config.sh' \
  --exclude='.htaccess' --exclude='.htaccess.')
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
LATEST_DUMP="$(ls -1t "$WORKSPACE_BASE/backups/$BRANCH/"*.sql "$WORKSPACE_BASE/backups/$BRANCH/"*.db 2>/dev/null | head -1)"
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

# post-deploy hook (optional — e.g. cache clear on rollback)
if [ -n "$POST_DEPLOY_HOOK" ]; then
  (cd "$APP_DIR" && eval "$POST_DEPLOY_HOOK") >> "$LOG" 2>&1 || true
fi

echo "$TARGET_SHA" > "$WORKSPACE/.deployed_sha" 2>/dev/null || true
# manual rollback = user intervention — clear the failed marker so the
# same SHA can be retried later (auto-rollback re-writes it afterwards,
# so the re-deploy loop guard stays intact).
if [ "${ROLLBACK_AUTO:-0}" != "1" ]; then
  rm -f "$WORKSPACE/.failed_sha" 2>/dev/null || true
fi

# when called from auto-rollback, auto_deploy.sh sends its own alert — skip duplicate
if [ "${ROLLBACK_AUTO:-0}" != "1" ]; then
  notify "⏪ <b>Rollback completed</b> ($SITE_DOMAIN · $BRANCH)
Rolled back to <code>${TARGET_SHA:0:10}</code> + restarted" "Rollback Successful: $SITE_DOMAIN ($BRANCH)"
fi

echo "✅ Rolled back to $TARGET_SHA + restarted"
