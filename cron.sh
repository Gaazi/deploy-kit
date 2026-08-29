#!/bin/bash
# ============================================================
# DEPLOY KIT — cron.sh (ZERO GitHub Actions deploy)
# ------------------------------------------------------------
#   /bin/bash cron.sh [minutes] [branch]
# Installs a server cron job that checks the repo every N
# minutes and deploys if there's a new commit. Uses 0 GitHub
# Actions minutes — your free-plan limit never runs out.
#   - No new commit → instant skip (SHA check)
#   - Build / DB backup / migrate / restart / health / Telegram
#     all work exactly the same as the Actions flow
#   - Later want instant pushes again? Add the GitHub Actions
#     workflow + touch ~/.deploy_github + set SKIP_WHEN_FLAG=1
#     → cron auto-skips (toggle mode)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

MIN="${1:-2}"
case "$MIN" in
  ''|*[!0-9]*) MIN=2 ;;   # not a number → default 2
esac
[ "$MIN" -lt 1 ] && MIN=1   # 0/negative → 1 (valid cron interval)
BRANCH="${2:-${DEFAULT_BRANCH:-main}}"
LOG="${LOG_FILE:-$HOME/deploy.log}"
LINE="*/$MIN * * * * /bin/bash $SCRIPT_DIR/auto_deploy.sh $BRANCH >> $LOG 2>&1"

if command -v crontab >/dev/null 2>&1; then
  # install, removing any older deploy line for this branch first
  ( crontab -l 2>/dev/null | grep -v "auto_deploy.sh $BRANCH" ; echo "$LINE" ) | crontab -
  echo "✅ Cron installed — every $MIN min → auto-deploy '$BRANCH' (0 GitHub Actions)"
  echo "   Line added: $LINE"
  echo "   View/remove: crontab -e  (delete the auto_deploy.sh line)"
else
  echo "⚠️  'crontab' command not available (cPanel?) — paste this in cPanel → Cron Jobs:"
  echo "   $LINE"
fi

echo ""
echo "ℹ️  GitHub Actions mode = instant deploy (~6s job) but ~1 min of Actions time per push."
echo "   This cron mode = 0 Actions minutes, deploy within $MIN min. Free plan = 2000 min/month."
echo "   Toggle later: touch ~/.deploy_github + SKIP_WHEN_FLAG=1 → cron skips, Actions takes over."
