#!/bin/bash
# Stage validated kit releases and keep recoverable installation backups.
kit_installed_clean() {
  kit_bundle_valid "$KIT_HOME" || { echo 'Installed kit files changed or baseline is missing; update refused.'; return 1; }
  if [ -e "$KIT_HOME/.git" ]; then
    local prefix
    prefix="$(git -C "$KIT_HOME" rev-parse --show-prefix)" || return 1
    [ -z "$prefix" ] || return 1
    git -C "$KIT_HOME" diff --quiet && git -C "$KIT_HOME" diff --cached --quiet || return 1
  fi
}

# Refuse collisions with files not managed by the installed release.
kit_install_paths_safe() {
  local file parent
  while IFS= read -r file; do
    parent="$(dirname "$file")"
    while [ "$parent" != . ]; do
      [ ! -L "$KIT_HOME/$parent" ] || return 1
      parent="$(dirname "$parent")"
    done
    [ ! -L "$KIT_HOME/$file" ] || return 1
    if [ -e "$KIT_HOME/$file" ]; then grep -qxF "$file" "$KIT_HOME/kit-files.list" || return 1; fi
  done < "$STAGE/kit-files.list"
}

# Download only a requested stable tag into a private staging directory.
kit_stage_release() {
  STAGE="$STATE/stage-$(date +%s)-$$"
  kit_git clone -q --depth 1 --single-branch --branch "$LATEST" "$UPDATE_REPO" "$STAGE" 2>/dev/null \
    || { echo 'Release download failed; check upstream access and Git credentials.'; return 1; }
  kit_bundle_valid "$STAGE" && kit_bundle_syntax "$STAGE" || { echo 'Release validation failed.'; return 1; }
  [ "$(cat "$STAGE/VERSION")" = "${LATEST#v}" ] || { echo 'Tag and VERSION do not match.'; return 1; }
  kit_install_paths_safe || { echo 'Update would overwrite an unmanaged file or symlink.'; return 1; }
}

# Save only managed kit files, never configs, keys or site data.
kit_backup_release() {
  BACKUP="$STATE/backup-$(date +%s)-$$"
  mkdir -p "$BACKUP/files" || return 1
  local file
  while IFS= read -r file; do
    mkdir -p "$BACKUP/files/$(dirname "$file")" && cp -p "$KIT_HOME/$file" "$BACKUP/files/$file" || return 1
  done < "$KIT_HOME/kit-files.list"
  cp -p "$KIT_HOME/kit-files.sha256" "$BACKUP/files/kit-files.sha256" || return 1
  cp "$STAGE/kit-files.list" "$BACKUP/new-files.list" || return 1
  if [ -e "$KIT_HOME/.git" ]; then
    git -C "$KIT_HOME" rev-parse HEAD > "$BACKUP/head" || return 1
    git -C "$KIT_HOME" symbolic-ref -q --short HEAD > "$BACKUP/branch" || :
  fi
  printf '%s\n' "$(basename "$BACKUP")" > "$STATE/pending" || return 1
}

# Restore original files and move newly added files into the recovery backup.
kit_restore_files() {
  local file
  mkdir -p "$BACKUP/removed" || return 1
  while IFS= read -r file; do
    if ! grep -qxF "$file" "$BACKUP/files/kit-files.list" && [ -e "$KIT_HOME/$file" ]; then
      mkdir -p "$BACKUP/removed/$(dirname "$file")" && mv "$KIT_HOME/$file" "$BACKUP/removed/$file" || return 1
    fi
  done < "$BACKUP/new-files.list"
  while IFS= read -r file; do
    mkdir -p "$KIT_HOME/$(dirname "$file")" && cp -p "$BACKUP/files/$file" "$KIT_HOME/$file" || return 1
  done < "$BACKUP/files/kit-files.list"
  cp -p "$BACKUP/files/kit-files.sha256" "$KIT_HOME/kit-files.sha256"
}

# Roll back Git metadata as well as the managed package files.
kit_restore_backup() {
  if [ -f "$BACKUP/head" ]; then
    git -C "$KIT_HOME" checkout -q --detach "$(cat "$BACKUP/head")" || return 1
    local branch
    branch="$(cat "$BACKUP/branch")"
    if [ -n "$branch" ] && [ "$(git -C "$KIT_HOME" rev-parse "$branch")" = "$(cat "$BACKUP/head")" ]; then
      git -C "$KIT_HOME" checkout -q "$branch" || return 1
    fi
  fi
  kit_restore_files && kit_bundle_valid "$KIT_HOME" || return 1
  mv "$STATE/pending" "$BACKUP/recovered" || return 1
}

# Copy the explicit package atomically per file; removed old files are retained.
kit_copy_release() {
  local file
  while IFS= read -r file; do
    mkdir -p "$KIT_HOME/$(dirname "$file")" || return 1
    cp -p "$STAGE/$file" "$STATE/replacement" && mv "$STATE/replacement" "$KIT_HOME/$file" || return 1
  done < "$STAGE/kit-files.list"
  cp -p "$STAGE/kit-files.sha256" "$STATE/replacement" && mv "$STATE/replacement" "$KIT_HOME/kit-files.sha256"
}

# Git installations advance to the release commit without dropping local commits.
kit_git_release() {
  kit_git -C "$KIT_HOME" fetch -q --no-tags "$UPDATE_REPO" "refs/tags/$LATEST:refs/kit-updates/$LATEST" || return 1
  git -C "$KIT_HOME" merge-base --is-ancestor HEAD "refs/kit-updates/$LATEST" || { echo 'Local Git history is not an ancestor of the release; update refused.'; return 1; }
  local file
  while IFS= read -r file; do
    case "$file" in config.sh|config.*.sh|.env|*.key|*.pem|deploy_key*) [ "$file" = config.example.sh ] || return 1;; esac
  done < <(git -C "$KIT_HOME" ls-tree -r --name-only "refs/kit-updates/$LATEST")
  git -C "$KIT_HOME" checkout -q --detach "refs/kit-updates/$LATEST"
}

# Commit the local update transaction only after validation succeeds.
kit_apply_release() {
  kit_installed_clean && kit_stage_release && kit_backup_release || return 1
  local status=0
  if [ -e "$KIT_HOME/.git" ]; then kit_git_release || status=1; else kit_copy_release || status=1; fi
  if [ "$status" -ne 0 ] || ! kit_bundle_valid "$KIT_HOME"; then
    echo 'Update failed; restoring the previous kit.'
    kit_restore_backup || echo 'Recovery incomplete; run update.sh rollback before deploying.'
    return 1
  fi
  printf '%s\n' "$(basename "$BACKUP")" > "$STATE/previous" || return 1
  mv "$STATE/pending" "$BACKUP/completed" || return 1
  echo "Installed Deploy Kit $LATEST. Backup: $BACKUP"
}

# Recover an interrupted update or undo the last completed update.
kit_rollback_release() {
  local name
  if [ -s "$STATE/pending" ]; then name="$(cat "$STATE/pending")"; else
    kit_installed_clean || return 1
    name="$(cat "$STATE/previous" 2>/dev/null)"
  fi
  [[ "$name" =~ ^backup-[0-9]+-[0-9]+$ ]] || { echo 'No update recovery backup available.'; return 1; }
  BACKUP="$STATE/$name"
  kit_bundle_valid "$BACKUP/files" || { echo 'Backup validation failed.'; return 1; }
  printf 'v%s\n' "$(cat "$KIT_HOME/VERSION")" > "$STATE/blocked" || return 1
  printf '%s\n' "$name" > "$STATE/pending" || return 1
  kit_restore_backup || return 1
  echo "Kit restored to v$(cat "$KIT_HOME/VERSION"). Auto-update of the rolled-back version is blocked."
}
