#!/bin/bash
# ============================================================
# DEPLOY KIT — rollback.sh (GENERIC)
# ------------------------------------------------------------
# Go back to a previous commit (or any SHA).
#   usage: /bin/bash rollback.sh <branch> [commit-sha]
#   no sha given → back to the PREVIOUS version (the one that was live before
#   the current deploy). Falls back to the currently deployed SHA when no
#   distinct previous version is recorded.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# One installation lock covers both kit updates and the entire app deployment.
if [ -f "$SCRIPT_DIR/lib/kit-lock.sh" ]; then
  KIT_HOME="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/kit-lock.sh" || exit 1
  kit_lock_acquire || exit 1
  trap 'kit_lock_release' EXIT
  [ ! -s "$SCRIPT_DIR/.kit-update/pending" ] || { echo "Kit update interrupted; run update.sh rollback."; exit 1; }
fi
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

# ── NODE_BIN (documented key): make a custom node/npm visible to build ──
if [ -n "${NODE_BIN:-}" ]; then
  PATH="$(dirname "$NODE_BIN"):$PATH"
  export PATH
fi
# Target resolution: an explicit SHA wins. Without one, roll back to the
# version that was live BEFORE the current deploy (.previous_sha, written by
# auto_deploy.sh) — that is the version a user wants back after a bad deploy.
# If no distinct previous version exists (first deploy, or a rollback already
# happened), fall back to the currently deployed SHA so a re-sync still works.
if [ -n "${2:-}" ]; then
  TARGET_SHA="$2"
else
  _CUR_SHA="$(cat "$WORKSPACE/.deployed_sha" 2>/dev/null || true)"
  _PREV_SHA="$(cat "$WORKSPACE/.previous_sha" 2>/dev/null || true)"
  if [ -n "$_PREV_SHA" ] && [ "$_PREV_SHA" != "$_CUR_SHA" ]; then
    TARGET_SHA="$_PREV_SHA"
  else
    TARGET_SHA="$_CUR_SHA"
  fi
fi

# ── Multi-channel notification helper (Telegram, Discord, Slack, Email) ──
notify() {
  local html_msg="$1"
  local subject="${2:-Rollback Notification ($SITE_DOMAIN)}"
  local plain_msg
  plain_msg="$(echo "$html_msg" | sed -e 's/<[^>]*>//g')"

  # 1. Telegram
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -s -o /dev/null --connect-timeout 5 -m 15 \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$html_msg" \
      --data-urlencode "parse_mode=HTML" >/dev/null 2>&1 || true
  fi

  # 2. Discord Webhook
  if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    local discord_json
    discord_json="$(printf '%s' "$plain_msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
    discord_json="${discord_json%\\n}"
    curl -s -o /dev/null --connect-timeout 5 -m 15 -H "Content-Type: application/json" \
      -d "{\"content\": \"$discord_json\"}" \
      "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi

  # 3. Slack Webhook
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    local slack_json
    slack_json="$(printf '%s' "$plain_msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
    slack_json="${slack_json%\\n}"
    curl -s -o /dev/null --connect-timeout 5 -m 15 -H "Content-Type: application/json" \
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
  trap 'declare -F kit_lock_release >/dev/null && kit_lock_release; rm -rf "$LOCK_DIR" 2>/dev/null' EXIT
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

# Every step is checked: an unchecked failure here would rsync the CURRENT
# (broken) worktree and still print "✅ Rolled back", exit 0 and update
# .deployed_sha — the worst possible outcome for a rollback.
git -C "$WORKSPACE" checkout "$TARGET_SHA" >> "$LOG" 2>&1 \
  || { echo "❌ git checkout failed — app untouched" | tee -a "$LOG"; exit 1; }

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
rsync -az --delete "${RSYNC_ARGS[@]}" "$SRC_DIR/" "$APP_DIR/" >> "$LOG" 2>&1 \
  || { echo "❌ rsync failed — rollback incomplete, app dir may be mixed" | tee -a "$LOG"; exit 1; }

# rebuild (only if the app has a build step)
if [ -n "$BUILD_CMD" ]; then
  echo "🔨 Rebuilding: $BUILD_CMD"
  (cd "$APP_DIR" && eval "$BUILD_CMD") >> "$LOG" 2>&1 \
    || { echo "❌ Build FAILED during rollback — code is rolled back, build is not" | tee -a "$LOG"; exit 1; }
fi

# ── DB restore (optional) ───────────────────────────────────
# Auto-read DB creds from the app's .env when config.sh leaves them empty:
# the dump being restored was created with exactly that fallback in
# auto_deploy.sh, so rollback must resolve the same credentials — otherwise
# the restore was silently skipped while "✅ Rolled back" was still printed.
if [ -n "$DB_NAME" ] && { [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; }; then
  ENV_FILE="$APP_DIR/.env"
  if [ -f "$ENV_FILE" ] && grep -qE '^DATABASE_URL=' "$ENV_FILE" 2>/dev/null; then
    DB_URL="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
    DB_REST="${DB_URL#*://}"
    DB_USERINFO="${DB_REST%@*}"      # split on LAST @ (password may contain @)
    DB_HOSTPORT="${DB_REST##*@}"
    case "$DB_USERINFO" in
      *:*) DB_USER="${DB_USER:-${DB_USERINFO%%:*}}"; DB_PASS="${DB_PASS:-${DB_USERINFO#*:}}" ;;
      *)   DB_USER="${DB_USER:-$DB_USERINFO}" ;;
    esac
    _host_raw="${DB_HOSTPORT%%/*}"
    _db_raw="${DB_HOSTPORT#*/}"
    DB_HOST="${DB_HOST:-${_host_raw%%:*}}"
    DB_NAME="${DB_NAME:-${_db_raw%%\?*}}"
    echo "$(date '+%F %T'): DB creds auto-read from .env (rollback restore)" >> "$LOG"
  fi
fi

# restore pre-migration DB dump if present (fresh/uncompressed only — the
# .gz archives are intentionally never auto-restored)
LATEST_DUMP="$(ls -1t "$WORKSPACE_BASE/backups/$BRANCH/"*.sql "$WORKSPACE_BASE/backups/$BRANCH/"*.db 2>/dev/null | head -1)"
if [ -n "$LATEST_DUMP" ] && [ -n "$DB_NAME" ]; then
  echo "🔄 Restoring DB: $LATEST_DUMP"
  case "$DB_TYPE" in
    mysql)
      if [ -n "$DB_USER" ] && command -v mysql >/dev/null 2>&1; then
        MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" < "$LATEST_DUMP" >> "$LOG" 2>&1 \
          && echo "✅ DB restored" \
          || { echo "❌ DB restore FAILED — the DB is still migrated (dump: $LATEST_DUMP)" | tee -a "$LOG"; }
      elif [ -f "$SCRIPT_DIR/db-dump.py" ]; then
        _PYX="${PYTHON_BIN:-python3}"
        "$_PYX" "$SCRIPT_DIR/db-dump.py" restore "$APP_DIR/.env" "$LATEST_DUMP" >> "$LOG" 2>&1 \
          && echo "✅ DB restored (db-dump.py fallback)" \
          || { echo "❌ DB restore FAILED (db-dump.py) — the DB is still migrated" | tee -a "$LOG"; }
      else
        echo "⚠️  DB dump found but no mysql client and no db-dump.py — DB NOT restored" | tee -a "$LOG"
      fi ;;
    postgres)
      if [ -n "$DB_USER" ] && command -v psql >/dev/null 2>&1; then
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" < "$LATEST_DUMP" >> "$LOG" 2>&1 \
          && echo "✅ DB restored" \
          || { echo "❌ DB restore FAILED — the DB is still migrated" | tee -a "$LOG"; }
      else
        echo "⚠️  DB dump found but psql (or DB_USER) is missing — DB NOT restored" | tee -a "$LOG"
      fi ;;
    sqlite)
      { cp "$LATEST_DUMP" "$APP_DIR/$DB_NAME" >> "$LOG" 2>&1 \
        && echo "✅ DB restored (sqlite)"; } \
        || { echo "❌ sqlite restore FAILED" | tee -a "$LOG"; } ;;
  esac
elif [ -n "$DB_NAME" ]; then
  echo "ℹ️  No fresh DB dump in $WORKSPACE_BASE/backups/$BRANCH/ — DB not restored" | tee -a "$LOG"
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
