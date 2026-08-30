#!/bin/bash
# ============================================================
# DEPLOY KIT — webhook.sh (GitHub webhook listener, ~1-2s)
# ------------------------------------------------------------
#   /bin/bash webhook.sh start|stop|status
# VPS ONLY — needs socat (apt install socat) + openssl.
# GitHub POSTs → webhook.sh verifies → fires auto_deploy.sh
# <branch> in the background. Fastest trigger (~1-2s), 0 GitHub
# Actions minutes (no runner at all with native webhook).
#
# 2 ways to trigger:
#   1. Native GitHub webhook (recommended, 0 runner): repo →
#      Settings → Webhooks → payload URL http://SERVER:PORT/
#      webhook/deploy/ + secret (HMAC verified).
#   2. GitHub Actions workflow (deploy-webhook.yml.example).
# Pair with: .github/workflows/deploy-webhook.yml.example
# ⚠️ Production: put it behind HTTPS (nginx/caddy proxy).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

SECRET="${DEPLOY_WEBHOOK_SECRET:-}"
PORT="${WEBHOOK_PORT:-9000}"
LOG="${LOG_FILE:-$HOME/deploy.log}"
PIDFILE="$SCRIPT_DIR/.webhook.pid"

start() {
  if [ -z "$SECRET" ]; then
    echo "❌ DEPLOY_WEBHOOK_SECRET is empty — set it in config.sh first"
    exit 1
  fi
  command -v socat >/dev/null 2>&1 || { echo "❌ socat not found — run: apt install socat"; exit 1; }
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "✅ Webhook listener already running (pid $(cat "$PIDFILE"))"
    exit 0
  fi
  nohup socat TCP-LISTEN:"$PORT",fork,reuseaddr,max-children=10 \
    EXEC:"$SCRIPT_DIR/webhook.sh handler",setsid,stderr >> "$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  echo "✅ Webhook listener started on port $PORT (pid $!)"
  echo "   URL: http://SERVER_IP:$PORT/webhook/deploy/"
  echo "   GitHub secrets: DEPLOY_WEBHOOK_URL = that URL, DEPLOY_WEBHOOK_SECRET = same value"
}

stop() {
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
    rm -f "$PIDFILE"
    echo "🛑 Webhook listener stopped"
  else
    echo "ℹ️ No listener running"
  fi
}

status() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "✅ Running (pid $(cat "$PIDFILE"), port $PORT)"
  else
    echo "ℹ️ Not running"
  fi
}

handler() {
  # parse the HTTP request from stdin
  read -r REQUEST
  SECRET_HEADER=""; HUB_SIG=""; LEN=0
  while read -r line; do
    line="${line%$'\r'}"
    [ -z "$line" ] && break
    # lowercase header name for case-insensitive matching (RFC 7230)
    lc_line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    case "$lc_line" in
      x-deploy-secret:*)     SECRET_HEADER="${line#*: }" ;;
      x-hub-signature-256:*) HUB_SIG="${line#*: }" ;;
      content-length:*)      LEN="${line#*: }" ;;
    esac
  done
  BODY=""
  [ "$LEN" -gt 0 ] 2>/dev/null && BODY="$(dd bs=1 count="$LEN" 2>/dev/null)"
  # extract branch: try our format first, then native GitHub webhook ref
  # use grep -o to avoid greedy .* matching wrong "ref" in minified JSON
  BRANCH="$(printf '%s' "$BODY" | grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//;s/"//')"
  if [ -z "$BRANCH" ]; then
    BRANCH="$(printf '%s' "$BODY" | grep -o '"ref"[[:space:]]*:[[:space:]]*"refs/heads/[^"]*"' | head -1 | sed 's/.*refs\/heads\///;s/"//')"
  fi
  # verify: native GitHub webhook (HMAC) OR our custom header OR nothing
  AUTHORIZED=0
  if [ -n "$SECRET" ]; then
    if [ -n "$HUB_SIG" ]; then
      # native GitHub webhook — verify HMAC-SHA256 (constant-time via double-HMAC)
      EXPECTED="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" 2>/dev/null | sed 's/.* //')"
      # constant-time: HMAC both strings with a nonce — if equal, HMACs match
      NONCE="$$.$RANDOM"
      H1="$(printf '%s' "$HUB_SIG" | openssl dgst -sha256 -hmac "$NONCE" 2>/dev/null)"
      H2="$(printf '%s' "$EXPECTED" | openssl dgst -sha256 -hmac "$NONCE" 2>/dev/null)"
      [ "$H1" = "$H2" ] && AUTHORIZED=1
    elif [ -n "$SECRET_HEADER" ] && [ "$SECRET_HEADER" = "$SECRET" ]; then
      AUTHORIZED=1
    fi
  fi
  if [ "$AUTHORIZED" -eq 1 ] && [ -n "$BRANCH" ]; then
    nohup /bin/bash "$SCRIPT_DIR/auto_deploy.sh" "$BRANCH" >> "$LOG" 2>&1 &
    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\nok'
  else
    printf 'HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: 9\r\n\r\nforbidden'
  fi
}

case "$1" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  handler) handler ;;
  *) echo "usage: /bin/bash webhook.sh start|stop|status"; exit 1 ;;
esac
