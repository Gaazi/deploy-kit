#!/bin/bash
# Notify configured channels once per available release and successful delivery.
kit_notification_env() {
  local key value
  [ -f "${APP_DIR:-}/.env" ] || return 0
  for key in TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID DISCORD_WEBHOOK_URL SLACK_WEBHOOK_URL ALERT_EMAIL; do
    [ -n "${!key:-}" ] && continue
    value="$(grep -E "^${key}=" "$APP_DIR/.env" | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
    printf -v "$key" '%s' "$value"
  done
}

# HTTP success is required; failed sends remain eligible for a later check.
kit_send_channel() {
  case "$1" in
    telegram)
      [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || return 2
      local reply
      reply="$(curl -fsS --connect-timeout 5 -m 15 --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$KIT_MESSAGE" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>/dev/null)" || return 1
      echo "$reply" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true';;
    discord|slack)
      local url field
      if [ "$1" = discord ]; then url="${DISCORD_WEBHOOK_URL:-}"; field=content; else url="${SLACK_WEBHOOK_URL:-}"; field=text; fi
      [ -n "$url" ] || return 2
      curl -fsS --connect-timeout 5 -m 15 -o /dev/null -H 'Content-Type: application/json' \
        --data "{\"$field\":\"$KIT_MESSAGE\"}" "$url" >/dev/null 2>&1;;
    email)
      [ -n "${ALERT_EMAIL:-}" ] || return 2
      if command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$KIT_MESSAGE" | mail -s 'Deploy Kit update available' "$ALERT_EMAIL"
      elif command -v sendmail >/dev/null 2>&1; then
        printf 'To: %s\nSubject: Deploy Kit update available\n\n%s\n' "$ALERT_EMAIL" "$KIT_MESSAGE" | sendmail -t
      else return 1; fi;;
  esac
}

# Version text is validated before it enters the fixed JSON-safe message.
kit_notify_release() {
  local channel marker status
  kit_notification_env
  KIT_MESSAGE="Deploy Kit $LATEST is available (installed v$CURRENT). Run bash update.sh apply $LATEST."
  [ "${LATEST#v}" = "${CURRENT}" ] && return 0
  KIT_MESSAGE="$KIT_MESSAGE Review release notes before updating."
  [ "${LATEST%%.*}" = "v${CURRENT%%.*}" ] || KIT_MESSAGE="$KIT_MESSAGE Major release: manual compatibility review and --allow-major required."
  for channel in telegram discord slack email; do
    marker="$STATE/notified-$BRANCH-$channel"
    [ "$(cat "$marker" 2>/dev/null)" = "$LATEST" ] && continue
    kit_send_channel "$channel"; status=$?
    if [ "$status" -eq 0 ]; then
      printf '%s\n' "$LATEST" > "$marker" || return 1
    elif [ "$status" -eq 1 ]; then echo "Update notification failed: $channel (will retry on a later daily check)."; fi
  done
}
