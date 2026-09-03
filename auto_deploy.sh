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
SCRIPT_DIR="${KIT_REAL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BRANCH_ARG="${1:-}"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
# Branch-specific config: if config.<branch>.sh exists, use it (e.g. config.dev.sh, config.main.sh)
if [ -n "$BRANCH_ARG" ] && [ -f "${SCRIPT_DIR}/config.${BRANCH_ARG}.sh" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.${BRANCH_ARG}.sh"
fi
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ config.sh not found — first run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

# ── Self-update snapshot guard (AFTER config, so KIT_SELF_UPDATE is known) ──
# When KIT_SELF_UPDATE=yes, re-exec this script from a /tmp SNAPSHOT so the
# later `git pull` can safely rewrite the real file — bash never executes a
# file that changes under it (mid-run corruption risk on shared hosting).
if [ "${KIT_SELF_UPDATE:-no}" = "yes" ] && [ -z "${KIT_SNAP_EXEC:-}" ] && [ -d "$SCRIPT_DIR/.git" ]; then
  _snap="$(mktemp /tmp/kit-deploy.XXXXXX.sh 2>/dev/null)" || _snap=""
  if [ -n "$_snap" ] && cp "$SCRIPT_DIR/auto_deploy.sh" "$_snap" 2>/dev/null; then
    trap '[ -n "${KIT_SNAP:-}" ] && rm -f "$KIT_SNAP" 2>/dev/null' EXIT
    KIT_SNAP_EXEC=1 KIT_REAL_DIR="$SCRIPT_DIR" KIT_SNAP="$_snap" \
      exec /bin/bash "$_snap" "$@"
  fi
fi

BRANCH="${1:-${DEFAULT_BRANCH:-main}}"
if [ -z "$BRANCH_ARG" ] && [ -f "${SCRIPT_DIR}/config.${BRANCH}.sh" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.${BRANCH}.sh"
  source "$CONFIG_FILE"
fi
APP_DIR="${APP_DIR:-/home/$SERVER_USER/app}"
WORKSPACE_BASE="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}"
WORKSPACE="$WORKSPACE_BASE/$BRANCH"
LOG="${LOG_FILE:-/home/$SERVER_USER/deploy.log}"
NOW="$(date '+%F %T')"

# ── .env fallback: auto-read app secrets the project already keeps ──
# If config.sh leaves notification keys empty, borrow them from the app's
# own .env (same file the app uses). No password duplication, no secrets in
# the repo. Only well-known variable names are supported; anything missing
# just stays empty (feature = optional, never fatal).
if [ -f "$APP_DIR/.env" ]; then
  _envget() { grep -E "^$1=" "$APP_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }
  [ -z "$TELEGRAM_BOT_TOKEN" ] && TELEGRAM_BOT_TOKEN="$(_envget TELEGRAM_BOT_TOKEN)"
  [ -z "$TELEGRAM_CHAT_ID" ]   && TELEGRAM_CHAT_ID="$(_envget TELEGRAM_CHAT_ID)"
  [ -z "$DISCORD_WEBHOOK_URL" ] && DISCORD_WEBHOOK_URL="$(_envget DISCORD_WEBHOOK_URL)"
  [ -z "$SLACK_WEBHOOK_URL" ]   && SLACK_WEBHOOK_URL="$(_envget SLACK_WEBHOOK_URL)"
  unset -f _envget
fi

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

# ── Pre-flight: fail fast BEFORE touching anything ─────────
# Light checks (~1s): disk space for workspace+backups. Full diagnostics
# live in doctor.sh — this is just the deploy-blocking minimum.
_avail_kb="$(df -Pk "$(dirname "$WORKSPACE_BASE")" 2>/dev/null | awk 'NR==2{print $4}' | head -1)"
if [ -n "$_avail_kb" ] && [ "$_avail_kb" -lt 51200 ]; then
  echo "❌ Low disk space — only ${_avail_kb}KB free on $(dirname "$WORKSPACE_BASE"). Free space or deploy will fail mid-way."
  exit 1
fi

# ── Placeholder check (clear error, not a confusing git failure) ─
# If config.sh was copied from config.example.sh but not filled in, catch it
# early — otherwise the user sees "Branch not found" or SSH key errors that
# point the wrong way.
case "$REPO_URL" in
  *YOUR_USER*|*YOUR_REPO*)
    echo "❌ config.sh still has PLACEHOLDER values — edit it and put your real values:"
    echo "   REPO_URL is: $REPO_URL"
    echo "   It should be: git@github.com:YOU/your-repo.git"
    echo "   First time? Run: /bin/bash setup.sh  (or edit config.sh directly)"
    exit 1 ;;
esac
case "$APP_DIR" in
  *your-app*|*your_app*) 
    echo "❌ config.sh APP_DIR looks like a placeholder — set your real app folder path:"
    echo "   APP_DIR is: $APP_DIR"
    exit 1 ;;
esac

log() { echo "$NOW: $1" >> "$LOG"; }

# ── Optional self-update of the kit itself (safe: config.sh is gitignored) ──
# If KIT_SELF_UPDATE=yes and this kit folder is a git clone, pull the latest
# scripts from its own repo. config.sh + keys are gitignored, so they are
# never touched. Failures are non-fatal (deploy continues).
if [ "${KIT_SELF_UPDATE:-no}" = "yes" ] && [ -d "$SCRIPT_DIR/.git" ]; then
  log "Kit self-update: git pull in $SCRIPT_DIR"
  ( cd "$SCRIPT_DIR" && git pull --ff-only --quiet ) >> "$LOG" 2>&1 || log "Kit self-update: skipped (up to date or failed)"
fi

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

# ── 0. GitHub-mode flag (optional toggle — cron deploys only) ─
# The flag means "GitHub Actions is active now" — so ONLY cron-fired
# deploys skip (cron.sh writes DEPLOY_TRIGGER=cron in its line).
# Actions/webhook/runner deploys never carry it and always run.
TOGGLE_FLAG="${TOGGLE_FLAG:-/home/$SERVER_USER/.deploy_github}"
if [ "${DEPLOY_TRIGGER:-}" = "cron" ] && [ -f "$TOGGLE_FLAG" ] && [ -n "$SKIP_WHEN_FLAG" ]; then
  log "Skipped — flag present ($TOGGLE_FLAG), cron disabled while GitHub mode is on"
  echo "⏭️ Cron deploy skipped — GitHub mode flag present ($TOGGLE_FLAG). Remove it to re-enable cron."
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
    # atomic: rename stale lock to temp, then mkdir — no gap for races
    mv "$LOCK_DIR" "$LOCK_DIR.stale.$$" 2>/dev/null
    rm -rf "$LOCK_DIR.stale.$$" 2>/dev/null &
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "⏳ Another deploy is running — skipped"; exit 0; }
  else
    echo "⏳ Another deploy is running — this one skipped (the running deploy picks up the latest commit)"
    exit 0
  fi
fi
echo $$ > "$LOCK_DIR/pid" 2>/dev/null
# NOTE: this trap REPLACES the snapshot trap above — clean both here,
# otherwise /tmp/kit-deploy.* leaked on every KIT_SELF_UPDATE=yes deploy.
trap 'rm -rf "$LOCK_DIR" 2>/dev/null; rm -f "${KIT_SNAP:-}" 2>/dev/null' EXIT

# ── 1. Git workspace ────────────────────────────────────────
# --single-branch: only this branch's history — minimum network + disk
if [ ! -d "$WORKSPACE/.git" ]; then
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i \"$DEPLOY_KEY\" -o StrictHostKeyChecking=no}" \
    git clone --single-branch --branch "$BRANCH" "$REPO_URL" "$WORKSPACE" >> "$LOG" 2>&1
else
  GIT_SSH_COMMAND="${DEPLOY_KEY:+ssh -i \"$DEPLOY_KEY\" -o StrictHostKeyChecking=no}" \
    git -C "$WORKSPACE" fetch origin "$BRANCH" >> "$LOG" 2>&1
fi

# Safety guard: abort if the branch is missing on the remote (clone/fetch failed).
# Never rsync --delete from a broken workspace — it would wipe the app.
# Distinguish SSH key error from branch-missing — the user can't fix the
# wrong error if we blame the branch when it's really a key problem.
if ! git -C "$WORKSPACE" rev-parse --verify -q "origin/$BRANCH" >/dev/null 2>&1; then
  _git_err="$(tail -5 "$LOG" 2>/dev/null | grep -iE 'permission denied|publickey|repository not found|not found|does not appear' | head -1)"
  echo "❌ git remote error — deploy aborted, app untouched" | tee -a "$LOG"
  if [ -n "$_git_err" ]; then
    echo "   $REPO_URL: $_git_err" | tee -a "$LOG"
    echo "   (Check: SSH key added to GitHub? DEPLOY_KEY path correct? Repo URL correct?)" | tee -a "$LOG"
  else
    echo "   Branch '$BRANCH' not found on remote ($REPO_URL)" | tee -a "$LOG"
    echo "   (Check: branch name spelled correctly? git push --set-upstream?)" | tee -a "$LOG"
  fi
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
FAILED_SHA="$(cat "$WORKSPACE/.failed_sha" 2>/dev/null || echo '')"

# skip if: no new commit, OR this exact SHA already failed health + was auto-rolled-back
if [ "$OLD_SHA" = "$NEW_SHA" ] || { [ -n "$FAILED_SHA" ] && [ "$FAILED_SHA" = "$NEW_SHA" ]; }; then
  log "No new commit on $BRANCH ($NEW_SHA) — skip"
  echo "⏭️ No new commit on $BRANCH — skip (deployed: ${NEW_SHA:0:10})"
  exit 0
fi

COMMIT_AUTHOR="$(git -C "$WORKSPACE" log -1 --pretty=format:'%an' "$NEW_SHA" 2>/dev/null || echo 'Unknown')"
COMMIT_MSG="$(git -C "$WORKSPACE" log -1 --pretty=format:'%s' "$NEW_SHA" 2>/dev/null || echo '')"
# HTML-escape the commit message (Telegram parse_mode=HTML breaks on & < >)
COMMIT_MSG="$(printf '%s' "$COMMIT_MSG" | sed -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"

if [ "${NOTIFY_ON_SUCCESS:-yes}" != "no" ]; then
  notify "🚀 <b>Deploy started</b> ($SITE_DOMAIN · $BRANCH)
<code>${OLD_SHA:0:10}</code> → <code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
💬 <i>$COMMIT_MSG</i>" "Deploy Started: $SITE_DOMAIN ($BRANCH)"
fi
log "Deploying $BRANCH: $OLD_SHA -> $NEW_SHA ($COMMIT_AUTHOR: $COMMIT_MSG)"

# ── 1.5 Pre-deploy hook (optional — e.g. php artisan down, pre-flight checks) ──
# Runs BEFORE rsync touches APP_DIR — aborts safely if it exits non-zero.
if [ -n "$PRE_DEPLOY_HOOK" ]; then
  log "Running pre-deploy hook: $PRE_DEPLOY_HOOK"
  _hook_dir="$APP_DIR"
  [ ! -d "$_hook_dir" ] && _hook_dir="$WORKSPACE"
  if ! (cd "$_hook_dir" && eval "$PRE_DEPLOY_HOOK") >> "$LOG" 2>&1; then
    notify "❌ <b>Deploy ABORTED (Pre-deploy hook)</b> ($SITE_DOMAIN · $BRANCH) — pre-deploy hook failed
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
Check server log: $LOG" "Deploy Pre-deploy hook FAILED: $SITE_DOMAIN ($BRANCH)"
    echo "❌ Pre-deploy hook FAILED — deploy aborted, app untouched." | tee -a "$LOG"
    exit 1
  fi
fi

# ── 2. Rsync to app dir ─────────────────────────────────────
mkdir -p "$APP_DIR"
RSYNC_ARGS=(--exclude='/.git/' --exclude='.env' --exclude='*.db' --exclude='*.sqlite3' \
  --exclude='__pycache__/' --exclude='*.pyc' --exclude='node_modules/' \
  --exclude='venv/' --exclude='.venv/' --exclude='*.log' --exclude='media/' \
  --exclude='backups/' --exclude='tests/' --exclude='deploy_kit/' --exclude='deploy-kit/' \
  --exclude='.htaccess' --exclude='.htaccess.')
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

# Auto-read DB creds from the app's .env when config.sh leaves them empty.
# Many frameworks (Django/FastAPI/Laravel/...) already keep DATABASE_URL in
# .env — no need to duplicate the password in config.sh. Format parsed:
#   mysql://USER:PASS@HOST/DBNAME   (also postgres://, mysql+pymysql://, etc.)
if [ "$DB_BACKUP" = "yes" ] && { [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; }; then
  ENV_FILE="$APP_DIR/.env"
  if [ -f "$ENV_FILE" ] && grep -qE '^DATABASE_URL=' "$ENV_FILE" 2>/dev/null; then
    DB_URL="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
    # strip scheme up to "://"
    DB_REST="${DB_URL#*://}"
    # split on LAST @ (host never has @, pass may have it unencoded)
    DB_USERINFO="${DB_REST%@*}"
    DB_HOSTPORT="${DB_REST##*@}"
    case "$DB_USERINFO" in
      *:*) DB_USER="${DB_USER:-${DB_USERINFO%%:*}}"; DB_PASS="${DB_PASS:-${DB_USERINFO#*:}}" ;;
      *)   DB_USER="${DB_USER:-$DB_USERINFO}" ;;
    esac
    DB_HOST="${DB_HOST:-${DB_HOSTPORT%%/*}}"
    DB_NAME="${DB_NAME:-${DB_HOSTPORT#*/}}"
    log "DB creds auto-read from .env (backup)"
  fi
fi

if [ "$DB_BACKUP" = "yes" ] && [ -n "$DB_NAME" ]; then
  BK_DIR="$WORKSPACE_BASE/backups/$BRANCH"   # OUTSIDE app dir — not web-accessible, keeps app dir light
  mkdir -p "$BK_DIR"
  TS="$(date +%Y%m%d_%H%M%S)"
  KEEP="${DB_BACKUP_KEEP:-7}"   # how many old dumps to keep (lighter disk = smaller number)
  case "$KEEP" in ''|*[!0-9]*) KEEP=7;; esac   # safety: non-numeric → default 7
  [ "$KEEP" -lt 1 ] && KEEP=1                  # safety: 0 would delete ALL backups
  if [ "$DB_TYPE" = "mysql" ]; then
    if command -v mysqldump >/dev/null 2>&1; then
      BK_FILE="$BK_DIR/${SITE_DOMAIN}_${TS}.sql"
      MYSQL_PWD="$DB_PASS" mysqldump -h "$DB_HOST" -u "$DB_USER" --single-transaction "$DB_NAME" \
        > "$BK_FILE" 2>>"$LOG"
    else
      # ── Python fallback (shared hosting: no mysqldump) ──
      # Uses the app's own venv python + pymysql + DATABASE_URL from .env.
      BK_FILE="$BK_DIR/${SITE_DOMAIN}_${TS}.sql"
      _PYX="${PYTHON_BIN:-python3}"
      if [ -f "$APP_DIR/.env" ] && [ -f "$SCRIPT_DIR/db-dump.py" ] && command -v "$_PYX" >/dev/null 2>&1; then
        "$_PYX" "$SCRIPT_DIR/db-dump.py" dump "$APP_DIR/.env" "$BK_FILE" >> "$LOG" 2>&1 \
          || log "python backup FAILED (see log)"
      else
        log "DB backup skipped — no mysqldump, no python fallback (.env/db-dump.py missing)"
      fi
    fi
    archive_old_backups
    log "DB backup: ${BK_FILE:-none} (last $KEEP fresh + older archived)"
  elif [ "$DB_TYPE" = "postgres" ] && [ -n "$DB_USER" ] && command -v pg_dump >/dev/null 2>&1; then
    BK_FILE="$BK_DIR/${SITE_DOMAIN}_${TS}.sql"
    PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" \
      > "$BK_FILE" 2>>"$LOG"
    archive_old_backups
    log "DB backup: $BK_FILE (last $KEEP fresh + older archived)"
  elif [ "$DB_TYPE" = "sqlite" ] && [ -f "$APP_DIR/$DB_NAME" ]; then
    BK_FILE="$BK_DIR/${SITE_DOMAIN}_${TS}.db"
    cp "$APP_DIR/$DB_NAME" "$BK_FILE" 2>>"$LOG"
    archive_old_backups
    log "DB backup (sqlite): $BK_FILE (last $KEEP fresh + older archived)"
  fi

  # ── Backup archive rotation (USER RULE: NEVER delete — compress instead) ──
  # Last KEEP dumps stay full-speed (fast restore). Older ones are gzip-
  # compressed in place (~90% smaller). Compressed archive is capped at KEEP;
  # beyond that the OLDEST compressed is removed (by then it is extremely old
  # and double-redundant with the app's own cPanel backups).
  archive_old_backups() {
    for _ext in sql db; do
      for _old in $(ls -1t "$BK_DIR"/*."$_ext" 2>/dev/null | tail -n +$((KEEP+1))); do
        [ -f "$_old" ] && gzip -f "$_old" 2>/dev/null
      done
      ls -1t "$BK_DIR"/*."$_ext".gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f 2>/dev/null
    done
  }

  # ── Backup verification (protect rollback from restoring garbage) ──
  # An empty/corrupt dump means a failed migration CANNOT be rolled back.
  # Abort BEFORE migrate when a migration is configured (the risky step);
  # otherwise warn only (backup was precautionary).
  BK_VERDICT="ok"
  if [ -z "${BK_FILE:-}" ] || [ ! -s "$BK_FILE" ]; then
    BK_VERDICT="empty"
  elif [ "$DB_TYPE" = "mysql" ] && ! grep -q "MySQL dump" "$BK_FILE" 2>/dev/null; then
    BK_VERDICT="invalid"
  elif [ "$DB_TYPE" = "postgres" ] && ! grep -q "PostgreSQL database dump" "$BK_FILE" 2>/dev/null; then
    BK_VERDICT="invalid"
  elif [ "$DB_TYPE" = "sqlite" ] && [ "$(head -c 15 "$BK_FILE" 2>/dev/null)" != "SQLite format 3" ]; then
    BK_VERDICT="invalid"
  fi
  if [ "$BK_VERDICT" != "ok" ]; then
    log "DB backup INVALID ($BK_VERDICT): ${BK_FILE:-none}"
    if [ -n "$MIGRATE_CMD" ]; then
      notify "❌ <b>Deploy ABORTED (DB backup $BK_VERDICT)</b> ($SITE_DOMAIN · $BRANCH)
Migration is configured but the pre-deploy backup is $BK_VERDICT — deploying would leave rollback impossible.
Fix DB creds/connection in config.sh, then push again." "Deploy ABORTED (bad backup): $SITE_DOMAIN ($BRANCH)"
      log "Deploy aborted — refusing to migrate without a valid backup"
      echo "❌ DB backup $BK_VERDICT — refusing to migrate (rollback would be impossible). Fix config.sh DB creds."
      exit 1
    fi
    log "Warning: backup invalid but no migration configured — continuing"
    echo "⚠️ DB backup $BK_VERDICT — continuing (no migration configured, low risk)"
  fi
fi

# ── 5. Migrate (if configured) ──────────────────────────────
if [ -n "$MIGRATE_CMD" ]; then
  log "Running migrate: $MIGRATE_CMD"
  MIGRATE_RESULT="ok"
  if ! (cd "$APP_DIR" && eval "$MIGRATE_CMD") >> "$LOG" 2>&1; then
    MIGRATE_RESULT="FAIL"
    # ── RESTORE_ON_FAIL: auto-restore DB from THIS deploy's verified backup ──
    # USER RULE: restore ONLY from this deploy's own backup — never stale/old backups.
    # Migration adhoori fail ho to DB half-migrated reh jata hai (MySQL DDL
    # rollback nahi hota) — isliye verified backup se restore karo.
    if [ "${RESTORE_ON_FAIL:-no}" = "yes" ] && [ -s "${BK_FILE:-}" ]; then
      _PYX="${PYTHON_BIN:-python3}"
      log "RESTORE_ON_FAIL — restoring DB from $BK_FILE"
      if [ "$DB_TYPE" = "mysql" ] && command -v mysql >/dev/null 2>&1; then
        MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" < "$BK_FILE" >> "$LOG" 2>&1 \
          && log "DB restored from this deploy's backup" || log "DB restore FAILED"
      elif [ -f "$SCRIPT_DIR/db-dump.py" ]; then
        "$_PYX" "$SCRIPT_DIR/db-dump.py" restore "$APP_DIR/.env" "$BK_FILE" >> "$LOG" 2>&1 \
          && log "DB restored from this deploy's backup (python)" || log "DB restore FAILED"
      fi
      notify "🔄 <b>Deploy FAILED (Migrate) — DB AUTO-RESTORED</b> ($SITE_DOMAIN · $BRANCH)
DB restored from this deploy's backup. Fix migration, push again." "Migrate FAIL — DB auto-restored: $SITE_DOMAIN ($BRANCH)"
    fi
    notify "❌ <b>Deploy FAILED (Migrate)</b> ($SITE_DOMAIN · $BRANCH) — migrate failed
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
Check server log: $LOG" "Deploy Migration FAILED: $SITE_DOMAIN ($BRANCH)"
    echo "❌ Migrate FAILED — deploy aborted. Restore the DB from $BK_DIR, then run: rollback.sh $BRANCH" | tee -a "$LOG"
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

# ── 6.5 Post-deploy hook (optional — e.g. cache clear, CDN purge, maintenance off) ──
# Runs AFTER restart & before health check
if [ -n "$POST_DEPLOY_HOOK" ]; then
  log "Running post-deploy hook: $POST_DEPLOY_HOOK"
  (cd "$APP_DIR" && eval "$POST_DEPLOY_HOOK") >> "$LOG" 2>&1 || log "Post-deploy hook warning: exited non-zero"
fi

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
    HEALTH_RESULT="ok"
    rm -f "$WORKSPACE/.failed_sha" 2>/dev/null   # deploy succeeded — clear failed marker
    if [ "${NOTIFY_ON_SUCCESS:-yes}" != "no" ]; then
      notify "✅ <b>Deploy successful</b> ($SITE_DOMAIN · $BRANCH) — health OK
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
💬 <i>$COMMIT_MSG</i>
⏱️ Time: ${DEPLOY_DURATION}s" "Deploy Successful: $SITE_DOMAIN ($BRANCH)"
    fi
    log "Health OK"
  else
    HEALTH_RESULT="FAIL"
    log "Health FAILED"
    if [ "${AUTO_ROLLBACK_ON_FAIL:-no}" = "yes" ] || [ "${AUTO_ROLLBACK_ON_FAIL:-false}" = "true" ] || [ "${AUTO_ROLLBACK_ON_FAIL:-0}" = "1" ]; then
      PREV_SHA="$(cat "$WORKSPACE/.previous_sha" 2>/dev/null || echo '')"
      if [ -n "$PREV_SHA" ]; then
        log "Health FAILED — initiating auto-rollback to $PREV_SHA"
        ROLLBACK_AUTO=1 DEPLOY_LOCK_HELD=1 /bin/bash "${SCRIPT_DIR}/rollback.sh" "$BRANCH" "$PREV_SHA" >> "$LOG" 2>&1 || true
        # stop re-deploy loop: mark the broken SHA as "failed" so the next
        # cron/Actions trigger skips it (files are already rolled back to PREV_SHA).
        # .deployed_sha stays PREV_SHA (rollback.sh set it) — manual rollback stays correct.
        echo "$NEW_SHA" > "$WORKSPACE/.failed_sha" 2>/dev/null || true
        AUTO_ROLLED_BACK=1
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
  if [ "${NOTIFY_ON_SUCCESS:-yes}" != "no" ]; then
    notify "✅ <b>Deploy successful</b> ($SITE_DOMAIN · $BRANCH)
<code>${NEW_SHA:0:10}</code> · 👤 $COMMIT_AUTHOR
💬 <i>$COMMIT_MSG</i>
⏱️ Time: ${DEPLOY_DURATION}s" "Deploy Successful: $SITE_DOMAIN ($BRANCH)"
  fi
  log "Health check skipped (no URL)"
fi

echo "✅ Deploy complete: $BRANCH @ ${NEW_SHA:0:10} (${DEPLOY_DURATION}s)"
[ "${AUTO_ROLLED_BACK:-0}" = "1" ] && echo "⚠️ Note: health failed — auto-rolled back to previous version. Fix the code and push again." || true

# ── Deploy history (audit trail — one line per deploy, keeps 90 deploys) ──
HIST="$WORKSPACE_BASE/deploy-history.md"
{ [ -f "$HIST" ] || echo "| When | Branch | SHA | Dur | Backup | Migrate | Health |" > "$HIST"
  echo "| $(date '+%F %T') | $BRANCH | ${NEW_SHA:0:10} | ${DEPLOY_DURATION}s | ${BK_VERDICT:-skip} | ${MIGRATE_RESULT:-skip} | ${HEALTH_RESULT:-skip} |" >> "$HIST"
} 2>/dev/null
# cap history at 90 lines (keep header)
_HL="$(wc -l < "$HIST" 2>/dev/null || echo 0)"
if [ "$_HL" -gt 92 ]; then
  { head -1 "$HIST"; tail -n 90 "$HIST"; } > "$HIST.tmp" 2>/dev/null && mv "$HIST.tmp" "$HIST" 2>/dev/null
fi
