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
BRANCH_ARG="${2:-}"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
if [ -n "$BRANCH_ARG" ] && [ -f "${SCRIPT_DIR}/config.${BRANCH_ARG}.sh" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.${BRANCH_ARG}.sh"
fi
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

MIN="${1:-2}"
case "$MIN" in
  ''|*[!0-9]*) MIN=2 ;;   # not a number → default 2
esac
[ "$MIN" -lt 1 ] && MIN=1   # 0/negative → 1 (valid cron interval)
BRANCH="${2:-${DEFAULT_BRANCH:-main}}"
if [ -z "$BRANCH_ARG" ] && [ -f "${SCRIPT_DIR}/config.${BRANCH}.sh" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/config.${BRANCH}.sh"
  source "$CONFIG_FILE"
fi
LOG="${LOG_FILE:-$HOME/deploy.log}"
# DEPLOY_TRIGGER=cron marks this line as cron-fired — the toggle flag
# (TOGGLE_FLAG + SKIP_WHEN_FLAG) then skips ONLY cron deploys, never Actions.
LINE="*/$MIN * * * * DEPLOY_TRIGGER=cron /bin/bash '$SCRIPT_DIR/auto_deploy.sh' '$BRANCH' >> '$LOG' 2>&1"

if command -v crontab >/dev/null 2>&1; then
  # install, removing any older deploy line for this branch first.
  # Read first, verify, then write: a failing `crontab -l` must never look
  # like "no crontab" (that would silently delete every other cron job).
  CRON_CURRENT="$(crontab -l 2>/dev/null)"; CRON_RC=$?
  if [ "$CRON_RC" -ne 0 ] && [ -n "$CRON_CURRENT" ]; then
    echo "❌ Could not read the current crontab (exit $CRON_RC) — refusing to overwrite it"
    exit 1
  fi
  # Dedup with FIXED strings anchored by the closing quote / the redirect:
  # the old substring match also deleted a different branch (dev vs dev2).
  CRON_NEW="$(printf '%s\n' "$CRON_CURRENT" | grep -v '^$' \
    | grep -vF "auto_deploy.sh' '$BRANCH'" \
    | grep -vF "auto_deploy.sh $BRANCH >>")"
  if ! { [ -n "$CRON_NEW" ] && printf '%s\n' "$CRON_NEW"; printf '%s\n' "$LINE"; } | crontab -; then
    echo "❌ crontab install failed — check cron.allow/cron.deny or spool permissions"
    exit 1
  fi
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
