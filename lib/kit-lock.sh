#!/bin/bash
# Serialize kit updates, deploys and rollbacks in one installation.
kit_lock_acquire() {
  KIT_LOCK="$KIT_HOME/.kit-operation-lock"
  if mkdir "$KIT_LOCK" 2>/dev/null; then
    printf '%s\n' "$$" > "$KIT_LOCK/pid" || return 1
    KIT_LOCK_OWNED=1
    return 0
  fi
  local owner
  owner="$(cat "$KIT_LOCK/pid" 2>/dev/null)"
  if [ "$owner" = "$$" ] && [ "${KIT_REEXEC_LOCK:-}" = "$owner" ]; then
    KIT_LOCK_OWNED=1
    return 0
  fi
  if [ "$owner" = "$PPID" ] && [ "${KIT_PARENT_LOCK:-}" = "$owner" ]; then
    return 0
  fi
  case "$owner" in ''|*[!0-9]*) echo 'Kit is busy (lock initialization).'; return 1;; esac
  if kill -0 "$owner" 2>/dev/null; then
    echo 'Kit is busy; retry after the active operation finishes.'
    return 1
  fi
  mkdir -p "$KIT_HOME/.kit-update" || return 1
  mv "$KIT_LOCK" "$KIT_HOME/.kit-update/stale-lock-$(date +%s)-$$" || return 1
  kit_lock_acquire
}

# Release only the lock owned by this process, never a parent's lock.
kit_lock_release() {
  [ "${KIT_LOCK_OWNED:-0}" = 1 ] || return 0
  [ "$(cat "$KIT_LOCK/pid" 2>/dev/null)" = "$$" ] || return 1
  mkdir -p "$KIT_HOME/.kit-update" || return 1
  mv "$KIT_LOCK/pid" "$KIT_HOME/.kit-update/last-lock-pid" && rmdir "$KIT_LOCK"
}
