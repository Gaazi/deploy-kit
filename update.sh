#!/bin/bash
# Check, apply or recover a stable Deploy Kit release in this installation.
set -u
KIT_HOME="${KIT_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$KIT_HOME/lib/kit-lock.sh" || exit 1
kit_lock_acquire || exit 1
trap 'kit_lock_release' EXIT
STATE="$KIT_HOME/.kit-update"
umask 077
mkdir -p "$STATE" || exit 1
[ ! -L "$STATE" ] || { echo 'Update state must not be a symlink.'; exit 1; }
# Execute a private snapshot: updating update.sh must not rewrite this process.
if [ "${KIT_UPDATE_SNAPSHOT:-0}" != 1 ]; then
  RUNTIME="$STATE/runtime"
  [ ! -L "$RUNTIME" ] || exit 1
  mkdir -p "$RUNTIME/lib" && cp "$KIT_HOME/update.sh" "$RUNTIME/update.sh" \
    && cp "$KIT_HOME"/lib/kit-*.sh "$RUNTIME/lib/" || exit 1
  KIT_UPDATE_SNAPSHOT=1 KIT_REEXEC_LOCK="$$" KIT_HOME="$KIT_HOME" \
    exec bash "$RUNTIME/update.sh" "$@"
fi
RUNTIME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUNTIME/lib/kit-release.sh" || exit 1
source "$RUNTIME/lib/kit-install.sh" || exit 1
source "$RUNTIME/lib/kit-notify.sh" || exit 1
ACTION="${1:-check}"; [ "$#" -gt 0 ] && shift
LATEST=""; BRANCH=""; FORCE=0; ALLOW_MAJOR=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1;;
    --allow-major) ALLOW_MAJOR=1;;
    v[0-9]*) kit_version_valid "$arg" || { echo 'Invalid stable release version.'; exit 1; }; LATEST="$arg";;
    *) [ -z "$BRANCH" ] || { echo 'Unexpected argument.'; exit 1; }; BRANCH="$arg";;
  esac
done
BRANCH="${BRANCH:-main}"
[[ "$BRANCH" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Use a simple branch name for update settings.'; exit 1; }
CONFIG="$KIT_HOME/config.$BRANCH.sh"
[ -f "$CONFIG" ] || CONFIG="$KIT_HOME/config.sh"
[ ! -f "$CONFIG" ] || source "$CONFIG"
CURRENT="$(cat "$KIT_HOME/VERSION")"
kit_version_valid "$CURRENT" || { echo 'Invalid installed VERSION.'; exit 1; }
MODE="${KIT_UPDATE_MODE:-}"
[ -n "$MODE" ] || { MODE=notify; [ "${KIT_SELF_UPDATE:-}" != yes ] || MODE=auto; }
UPDATE_REPO="${KIT_UPDATE_REPO:-}"
if [ -z "$UPDATE_REPO" ] && [ -e "$KIT_HOME/.git" ]; then UPDATE_REPO="$(git -C "$KIT_HOME" remote get-url origin 2>/dev/null)"; fi
UPDATE_REPO="${UPDATE_REPO:-https://github.com/Gaazi/deploy-kit.git}"
case "$UPDATE_REPO" in http*://*@*) echo 'Use Git credentials, not credentials embedded in the upstream URL.'; exit 1;; esac
case "$MODE" in notify|auto|off) :;; *) echo 'KIT_UPDATE_MODE must be notify, auto or off.'; exit 1;; esac

# Cache successful and failed checks for one day; --force explicitly retries.
kit_check_release() {
  [ "$MODE" != off ] || return 0
  local now last refs
  now="$(date +%s)"; last="$(cat "$STATE/checked-$BRANCH" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0;; esac
  [ "$FORCE" = 1 ] || [ "$now" -lt "$last" ] || [ "$((now-last))" -ge 86400 ] || return 0
  printf '%s\n' "$now" > "$STATE/checked-$BRANCH" || return 1
  refs="$(kit_git ls-remote --tags --refs "$UPDATE_REPO" 2>/dev/null)" || { echo 'Release check unavailable; installed kit is unchanged.'; return 1; }
  LATEST="$(printf '%s\n' "$refs" | sed -nE 's@.*refs/tags/(v[0-9]+\.[0-9]+\.[0-9]+)$@\1@p' | sort -V | tail -1)"
  [ -n "$LATEST" ] || { echo 'No stable release tag is published yet.'; return 0; }
  kit_version_valid "$LATEST" && kit_version_newer "$LATEST" "$CURRENT" || return 0
  printf '%s\n' "$LATEST" > "$STATE/available" || return 1
  echo "Deploy Kit $LATEST available; installed v$CURRENT."
  kit_notify_release || :
  [ "$MODE" = auto ] || return 0
  [ "$(cat "$STATE/blocked" 2>/dev/null)" != "$LATEST" ] || { echo 'Auto-update blocked after recovery; use explicit apply.'; return 0; }
  [ "${LATEST%.*}" = "v${CURRENT%.*}" ] || { echo 'Minor/major update needs manual review and apply.'; return 0; }
  kit_apply_release
}

if [ -s "$STATE/pending" ] && [ "$ACTION" != rollback ]; then
  echo 'Interrupted kit update; run bash update.sh rollback before deploying.'; exit 1
fi
case "$ACTION" in
  check) kit_check_release;;
  apply)
    kit_version_valid "$LATEST" || { echo 'Usage: bash update.sh apply vX.Y.Z [branch] [--allow-major]'; exit 1; }
    kit_version_newer "$LATEST" "$CURRENT" || { echo 'Version is not newer; use rollback for recovery.'; exit 1; }
    [ "${LATEST%%.*}" = "v${CURRENT%%.*}" ] || [ "$ALLOW_MAJOR" = 1 ] \
      || { echo 'Major version change: review release notes, then use --allow-major.'; exit 1; }
    kit_apply_release;;
  rollback) kit_rollback_release;;
  *) echo 'Usage: bash update.sh check [branch] [--force] | apply vX.Y.Z [branch] [--allow-major] | rollback [branch]'; exit 1;;
esac
