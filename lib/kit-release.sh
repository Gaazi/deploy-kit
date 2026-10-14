#!/bin/bash
# Read and verify explicit release files without loading downloaded code.
kit_version_valid() {
  [[ "$1" =~ ^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

# Return success only when the first stable version is newer.
kit_version_newer() {
  local a="${1#v}" b="${2#v}"
  [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" = "$a" ]
}

# Use noninteractive Git authentication and bounded network operations.
kit_git() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}" \
    git -c http.connectTimeout=10 -c http.lowSpeedLimit=100 -c http.lowSpeedTime=15 "$@"
}

# Allow kit files only; configs, keys, runtime data and traversal are forbidden.
kit_path_valid() {
  case "$(basename "$1")" in config.sh|config.*.sh) [ "$1" = config.example.sh ]; return;; esac
  case "$1" in ''|/*|*..*|*\\*|*[[:space:]]*|config.sh|config.*.sh) [ "$1" = config.example.sh ]; return;; esac
  case "$1" in
    lib/*.sh|tests/*.sh|.github/workflows/*.example) return 0;;
    */*) return 1;;
    VERSION|LICENSE|README.md|RELEASE_NOTES.md|kit-files.list|*.sh|db-dump.py|.htaccess|.gitignore|.gitattributes) return 0;;
    *) return 1;;
  esac
}

# Reject unsafe paths, duplicate entries, symlinks and invalid checksums.
kit_bundle_valid() {
  local root="$1" file parent
  [ -f "$root/kit-files.list" ] && [ -f "$root/kit-files.sha256" ] || return 1
  [ "$(sort "$root/kit-files.list" | uniq -d | wc -l)" -eq 0 ] || return 1
  while IFS= read -r file; do
    kit_path_valid "$file" && [ -f "$root/$file" ] && [ ! -L "$root/$file" ] || return 1
    parent="$(dirname "$file")"
    while [ "$parent" != . ]; do
      [ ! -L "$root/$parent" ] || return 1
      parent="$(dirname "$parent")"
    done
  done < "$root/kit-files.list"
  [ ! -L "$root/kit-files.sha256" ] || return 1
  diff -q <(sed -E 's/^[a-f0-9]{64} [ *]//' "$root/kit-files.sha256") "$root/kit-files.list" >/dev/null || return 1
  (cd "$root" && sha256sum -c kit-files.sha256 >/dev/null 2>&1) || return 1
  kit_version_valid "$(cat "$root/VERSION")" || return 1
  for file in VERSION auto_deploy.sh rollback.sh update.sh lib/kit-lock.sh lib/kit-release.sh lib/kit-install.sh lib/kit-notify.sh; do
    grep -qxF "$file" "$root/kit-files.list" || return 1
  done
}

# Bash syntax is checked without executing any release script.
kit_bundle_syntax() {
  local file
  while IFS= read -r file; do
    case "$file" in *.sh) bash -n "$1/$file" || return 1;; esac
  done < "$1/kit-files.list"
}

# Produce a deterministic checksum manifest from the explicit package list.
kit_bundle_hash() {
  local file
  (cd "$1" || exit 1
    while IFS= read -r file; do sha256sum -b "$file" || exit 1; done < kit-files.list)
}
