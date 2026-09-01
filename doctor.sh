#!/bin/bash
# ============================================================
# DEPLOY KIT — doctor.sh (Preflight & Environment Diagnostic)
# ------------------------------------------------------------
# Check your server setup, config, tools, and permissions before
# deploying.
#   usage: /bin/bash doctor.sh [config.sh]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/config.sh}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

ok()   { echo "  ✅ $1"; PASS_COUNT=$((PASS_COUNT+1)); }
warn() { echo "  ⚠️  $1"; WARN_COUNT=$((WARN_COUNT+1)); }
fail() { echo "  ❌ $1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
info() { echo "  ℹ️  $1"; }

echo "============================================="
echo "  Deploy Kit — System Doctor & Preflight Check"
echo "============================================="
echo ""

# ── 1. Shell & System ───────────────────────────────────────
echo "== 1. Shell & Operating System =="
if [ -n "$BASH_VERSION" ]; then
  ok "Bash version: $BASH_VERSION"
else
  warn "Not running inside standard Bash"
fi

OS_NAME="$(uname -s 2>/dev/null || echo 'Unknown')"
ARCH_NAME="$(uname -m 2>/dev/null || echo 'Unknown')"
info "System: $OS_NAME ($ARCH_NAME)"

# ── 2. Core CLI Tools ───────────────────────────────────────
echo ""
echo "== 2. Essential CLI Tools =="
for tool in git rsync curl ssh tar sed awk; do
  if command -v "$tool" >/dev/null 2>&1; then
    TOOL_PATH="$(command -v "$tool")"
    ok "$tool found ($TOOL_PATH)"
  else
    fail "$tool is MISSING (required for deployment)"
  fi
done

# ── 3. Configuration Check ──────────────────────────────────
echo ""
echo "== 3. Configuration ($CONFIG_FILE) =="
if [ ! -f "$CONFIG_FILE" ]; then
  fail "config.sh not found at: $CONFIG_FILE"
  echo "     Run setup wizard first: /bin/bash setup.sh"
  echo ""
  echo "============================================="
  echo "  Doctor Finished: ❌ Configuration Missing"
  echo "============================================="
  exit 1
fi
ok "config.sh found"

# Check file permissions (GNU: stat -c %a → "600", BSD: stat -f %Lp → "600")
CONFIG_PERMS="$(stat -c %a "$CONFIG_FILE" 2>/dev/null || stat -f %Lp "$CONFIG_FILE" 2>/dev/null || echo '')"
if [ "$CONFIG_PERMS" = "600" ] || [ "$CONFIG_PERMS" = "400" ]; then
  ok "config.sh permissions secure ($CONFIG_PERMS)"
else
  warn "config.sh permissions are $CONFIG_PERMS (recommended: chmod 600 config.sh)"
fi

# Load config
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Required settings
[ -n "$REPO_URL" ] && ok "REPO_URL: $REPO_URL" || fail "REPO_URL is missing in config.sh"
[ -n "$APP_DIR" ] && ok "APP_DIR: $APP_DIR" || fail "APP_DIR is missing in config.sh"
[ -n "$SITE_DOMAIN" ] && info "Domain: $SITE_DOMAIN" || warn "SITE_DOMAIN is not set"
[ -n "$APP_TYPE" ] && info "App Type: $APP_TYPE" || info "App Type: default"

# ── 4. Directories & Permissions ────────────────────────────
echo ""
echo "== 4. Directories & Permissions =="
WORKSPACE_DIR="${WORKSPACE_BASE:-/home/$SERVER_USER/deploy-workspace}"
if mkdir -p "$WORKSPACE_DIR" 2>/dev/null && [ -w "$WORKSPACE_DIR" ]; then
  ok "Workspace directory writable: $WORKSPACE_DIR"
else
  fail "Cannot write to workspace directory: $WORKSPACE_DIR"
fi

if [ -d "$APP_DIR" ]; then
  if [ -w "$APP_DIR" ]; then
    ok "App directory exists & writable: $APP_DIR"
  else
    fail "App directory exists but is NOT writable: $APP_DIR"
  fi
else
  PARENT_APP_DIR="$(dirname "$APP_DIR")"
  if [ -w "$PARENT_APP_DIR" ]; then
    ok "App directory will be created on first deploy in: $PARENT_APP_DIR"
  else
    fail "Parent directory of APP_DIR is NOT writable: $PARENT_APP_DIR"
  fi
fi

LOG_DEST="${LOG_FILE:-/home/$SERVER_USER/deploy.log}"
LOG_DIR="$(dirname "$LOG_DEST")"
if [ -w "$LOG_DIR" ] 2>/dev/null; then
  ok "Log location writable: $LOG_DEST"
else
  warn "Cannot write log file to: $LOG_DEST"
fi

# ── 5. SSH & Git Remote Access ──────────────────────────────
echo ""
echo "== 5. Git Remote & SSH Access =="
if [ -n "$DEPLOY_KEY" ]; then
  if [ -f "$DEPLOY_KEY" ]; then
    ok "Deploy key found: $DEPLOY_KEY"
    KEY_PERM="$(stat -c %a "$DEPLOY_KEY" 2>/dev/null || echo '')"
    [ "$KEY_PERM" = "600" ] || [ "$KEY_PERM" = "400" ] && ok "Deploy key permissions secure ($KEY_PERM)" || warn "Deploy key permissions ($KEY_PERM) should be 600"
  else
    fail "DEPLOY_KEY specified but file does not exist: $DEPLOY_KEY"
  fi
else
  info "DEPLOY_KEY not set (using default SSH identity ~/.ssh/id_rsa or agent)"
fi

if [ -n "$REPO_URL" ]; then
  if [ -n "$DEPLOY_KEY" ] && [ -f "$DEPLOY_KEY" ]; then
    GIT_SSH_COMMAND="ssh -i \"$DEPLOY_KEY\" -o StrictHostKeyChecking=no -o ConnectTimeout=8"
    export GIT_SSH_COMMAND
  fi
  if git ls-remote --heads "$REPO_URL" >/dev/null 2>&1; then
    ok "Git remote repository is accessible ($REPO_URL)"
  else
    warn "Could not reach remote repo (check SSH key in GitHub or network access)"
  fi
  unset GIT_SSH_COMMAND
fi

# ── 6. App Runtime & Stack Checks ──────────────────────
echo ""
echo "== 6. App Runtime & Stack Checks =="
case "${APP_TYPE:-}" in
  python)
    PY_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || echo '')}"
    if [ -n "$PY_BIN" ] && [ -x "$PY_BIN" ]; then
      ok "Python binary found: $PY_BIN ($("$PY_BIN" --version 2>&1))"
    else
      warn "Python binary not found ($PY_BIN)"
    fi
    ;;
  node)
    N_BIN="${NODE_BIN:-$(command -v node || echo '')}"
    if [ -n "$N_BIN" ] && command -v "$N_BIN" >/dev/null 2>&1; then
      ok "Node found: $("$N_BIN" --version 2>/dev/null)"
    else
      warn "Node.js not found in PATH"
    fi
    command -v npm >/dev/null 2>&1 && ok "npm found ($(npm --version 2>/dev/null))" || warn "npm not found"
    ;;
  php|wordpress)
    command -v php >/dev/null 2>&1 && ok "PHP found ($(php -v 2>/dev/null | head -1))" || warn "php CLI not found"
    command -v composer >/dev/null 2>&1 && ok "composer found" || info "composer not found (optional)"
    ;;
  docker)
    command -v docker >/dev/null 2>&1 && ok "docker found" || fail "docker CLI missing"
    command -v docker compose >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 && ok "docker compose found" || warn "docker compose missing"
    ;;
esac

case "${RESTART_METHOD:-}" in
  pm2)        command -v pm2 >/dev/null 2>&1 && ok "PM2 found" || warn "PM2 binary not in PATH" ;;
  supervisor) command -v supervisorctl >/dev/null 2>&1 && ok "supervisorctl found" || warn "supervisorctl not in PATH" ;;
  systemctl)  command -v systemctl >/dev/null 2>&1 && ok "systemctl found" || warn "systemctl not available" ;;
  passenger)  info "Passenger restart: will touch tmp/restart.txt" ;;
  touch)      info "Touch restart: will touch restart.txt" ;;
  php)        info "PHP reload: ${PHP_FPM_SERVICE:-default}" ;;
  docker)     info "Docker restart: container rebuild" ;;
  ""|none)    info "No restart method configured" ;;
esac

# ── 7. Notifications ────────────────────────────────────────
echo ""
echo "== 7. Notification Channels =="
NOTIF_ACTIVE=0
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  ok "Telegram alerts configured (Chat ID: $TELEGRAM_CHAT_ID)"
  NOTIF_ACTIVE=$((NOTIF_ACTIVE+1))
else
  info "Telegram alerts: not configured"
fi

if [ -n "$DISCORD_WEBHOOK_URL" ]; then
  ok "Discord webhook configured"
  NOTIF_ACTIVE=$((NOTIF_ACTIVE+1))
else
  info "Discord webhook: not configured"
fi

if [ -n "$SLACK_WEBHOOK_URL" ]; then
  ok "Slack webhook configured"
  NOTIF_ACTIVE=$((NOTIF_ACTIVE+1))
else
  info "Slack webhook: not configured"
fi

if [ -n "$ALERT_EMAIL" ]; then
  if command -v mail >/dev/null 2>&1 || command -v sendmail >/dev/null 2>&1; then
    ok "Email alerts configured ($ALERT_EMAIL) — mail utility available"
  else
    warn "Email configured ($ALERT_EMAIL) but neither 'mail' nor 'sendmail' is installed"
  fi
  NOTIF_ACTIVE=$((NOTIF_ACTIVE+1))
else
  info "Email alerts: not configured"
fi

[ "$NOTIF_ACTIVE" -eq 0 ] && info "No notification channels enabled (optional)"

# ── 7.5 Kit Self-Update & Trigger Path ─────────────────────
echo ""
echo "== 7.5 Kit Self-Update & Trigger Path =="
if [ "${KIT_SELF_UPDATE:-no}" = "yes" ]; then
  if [ -d "$SCRIPT_DIR/.git" ]; then
    ok "KIT_SELF_UPDATE=yes and kit is a git clone — will auto-pull on deploy (config.sh gitignored, safe)"
  else
    warn "KIT_SELF_UPDATE=yes but kit is NOT a git clone (no $SCRIPT_DIR/.git) — self-update will be skipped"
  fi
else
  info "KIT_SELF_UPDATE not set (kit does not auto-update — optional)"
fi
if [ -n "${SERVER_DEPLOY_PATH:-}" ]; then
  info "SERVER_DEPLOY_PATH set (workflow will call: $SERVER_DEPLOY_PATH)"
else
  info "SERVER_DEPLOY_PATH not set (workflow uses default ~/deploy-kit/auto_deploy.sh — set this if your kit lives elsewhere)"
fi

# Web-accessible config.sh warning (kit inside project root = secrets exposed)
# Trailing "/*" in the pattern — "/home/user/app2" must NOT match "/home/user/app"
if [ -n "$APP_DIR" ] && case "$SCRIPT_DIR" in "$APP_DIR"/*) true;; *) false;; esac; then
  if [ -f "$SCRIPT_DIR/.htaccess" ]; then
    ok "Kit is inside the app dir but .htaccess blocks web access — config.sh is protected"
  else
    fail "Kit is inside the web-accessible app dir but NO .htaccess — config.sh (DB_PASS, keys) may be visible in the browser. Add a .htaccess that denies all access."
  fi
fi

# ── 8. Health Check ─────────────────────────────────────────
echo ""
echo "== 8. Health Check & Safety =="
if [ -n "$HEALTH_URL" ] || [ -n "$SITE_DOMAIN" ]; then
  CHECK_URL="${HEALTH_URL:-https://$SITE_DOMAIN/}"
  info "Health check target: $CHECK_URL"
  if curl -fsS -m 5 "$CHECK_URL" >/dev/null 2>&1; then
    ok "Site is currently reachable at $CHECK_URL"
  else
    info "Site not reachable yet (normal if not yet deployed)"
  fi
fi

if [ "${AUTO_ROLLBACK_ON_FAIL:-no}" = "yes" ] || [ "${AUTO_ROLLBACK_ON_FAIL:-false}" = "true" ] || [ "${AUTO_ROLLBACK_ON_FAIL:-0}" = "1" ]; then
  ok "Auto-rollback on health failure is ENABLED"
else
  info "Auto-rollback on health failure is disabled (manual rollback mode)"
fi

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo "  Doctor Summary"
echo "  Passed:   $PASS_COUNT"
echo "  Warnings: $WARN_COUNT"
echo "  Errors:   $FAIL_COUNT"
echo "============================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "✅ All critical checks passed! Ready for deploy."
  exit 0
else
  echo "❌ Found $FAIL_COUNT critical issue(s). Please fix before deploying."
  exit 1
fi
