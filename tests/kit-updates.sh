#!/bin/bash
# Sourced by test.sh: exercise versioned updates using a local tagged upstream.
echo '== Kit release/update integration =='
UP_TEST="$TMP/kit-updates"
mkdir -p "$UP_TEST/bin" "$UP_TEST/upstream"
source lib/kit-release.sh

# Copy only release files; tests never read real installation credentials.
up_test_copy() {
  local source="$1" destination="$2" file
  mkdir -p "$destination"
  while IFS= read -r file; do
    mkdir -p "$destination/$(dirname "$file")"
    cp "$source/$file" "$destination/$file" || return 1
  done < "$source/kit-files.list"
  cp "$source/kit-files.sha256" "$destination/kit-files.sha256"
}

# Each fixture has its own config, update state and notification policy.
up_test_config() {
  cat > "$1/config.sh" <<CFG
KIT_UPDATE_REPO="file://$UP_TEST/upstream"
KIT_UPDATE_MODE="${2:-notify}"
ALERT_EMAIL="updates@example.test"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
DISCORD_WEBHOOK_URL=""
SLACK_WEBHOOK_URL=""
CFG
  chmod 600 "$1/config.sh"
}

# Only test-owned scripts are executed; the mail stub can fail on demand.
cat > "$UP_TEST/bin/mail" <<'MAIL_STUB'
#!/bin/bash
cat >> "$UP_MAIL_LOG"
[ ! -f "$UP_MAIL_FAIL" ]
MAIL_STUB
chmod +x "$UP_TEST/bin/mail"
export UP_MAIL_LOG="$UP_TEST/mail.log" UP_MAIL_FAIL="$UP_TEST/mail.fail"
UP_PATH="$UP_TEST/bin:$PATH"
up_test_copy . "$UP_TEST/upstream"
printf '1.0.0\n' > "$UP_TEST/upstream/VERSION"
kit_bundle_hash "$UP_TEST/upstream" > "$UP_TEST/upstream/kit-files.sha256"
git init -q "$UP_TEST/upstream"
git -C "$UP_TEST/upstream" config core.autocrlf false
git -C "$UP_TEST/upstream" add .
git -C "$UP_TEST/upstream" -c user.name=test -c user.email=test@example.test commit -qm baseline
git -C "$UP_TEST/upstream" tag v1.0.0
for name in copied auto legacy dirty failed gitfail recover offline major collision; do
  up_test_copy "$UP_TEST/upstream" "$UP_TEST/$name"
  up_test_config "$UP_TEST/$name"
done
git clone -q "$UP_TEST/upstream" "$UP_TEST/cloned"
git -C "$UP_TEST/cloned" config core.autocrlf false
up_test_config "$UP_TEST/cloned"
printf '1.0.1\n' > "$UP_TEST/upstream/VERSION"
printf '\nPatch fixture.\n' >> "$UP_TEST/upstream/README.md"
kit_bundle_hash "$UP_TEST/upstream" > "$UP_TEST/upstream/kit-files.sha256"
git -C "$UP_TEST/upstream" add .
git -C "$UP_TEST/upstream" -c user.name=test -c user.email=test@example.test commit -qm patch
git -C "$UP_TEST/upstream" tag v1.0.1
git -C "$UP_TEST/upstream" tag v99.0.0-rc.1

kit_version_valid 1.0.0 && ! kit_version_valid v1.0.0-rc.1 && ! kit_version_valid v01.0.0 \
  && ok 'stable semver validation rejects prereleases and leading zeros' || bad 'stable semver validation'
PATH="$UP_PATH" bash "$UP_TEST/copied/update.sh" check > "$UP_TEST/check.out" 2>&1
[ "$(cat "$UP_TEST/copied/VERSION")" = 1.0.0 ] && grep -q v1.0.1 "$UP_TEST/check.out" \
  && ok 'default check notifies without installing; prerelease ignored' || bad 'notify-only check'
UP_STAMP="$(cat "$UP_TEST/copied/.kit-update/checked-main")"
PATH="$UP_PATH" bash "$UP_TEST/copied/update.sh" check >/dev/null 2>&1
[ "$(cat "$UP_TEST/copied/.kit-update/checked-main")" = "$UP_STAMP" ] \
  && ok 'daily check cache skips repeated checks' || bad 'daily check cache'
PATH="$UP_PATH" bash "$UP_TEST/copied/update.sh" check --force >/dev/null 2>&1
[ "$(grep -c 'Deploy Kit v1.0.1' "$UP_MAIL_LOG")" -eq 1 ] \
  && ok 'successful notification is deduplicated per release' || bad 'notification deduplication'
touch "$UP_MAIL_FAIL"
PATH="$UP_PATH" bash "$UP_TEST/failed/update.sh" check >/dev/null 2>&1
[ ! -f "$UP_TEST/failed/.kit-update/notified-main-email" ] \
  && ok 'failed notification does not consume delivery marker' || bad 'failed notification marker'
mv "$UP_MAIL_FAIL" "$UP_MAIL_FAIL.saved"
PATH="$UP_PATH" bash "$UP_TEST/failed/update.sh" check --force >/dev/null 2>&1
[ "$(cat "$UP_TEST/failed/.kit-update/notified-main-email")" = v1.0.1 ] \
  && ok 'notification failure can be retried' || bad 'notification retry'

printf 'preserve secret\n' > "$UP_TEST/copied/config.dev.sh"
printf 'private key\n' > "$UP_TEST/copied/deploy_key"
printf 'site data\n' > "$UP_TEST/copied/unrelated.txt"
UP_CONFIG_HASH="$(sha256sum "$UP_TEST/copied/config.sh")"
PATH="$UP_PATH" bash "$UP_TEST/copied/update.sh" apply v1.0.1 >/dev/null 2>&1
[ "$(cat "$UP_TEST/copied/VERSION")" = 1.0.1 ] && [ "$(sha256sum "$UP_TEST/copied/config.sh")" = "$UP_CONFIG_HASH" ] \
  && grep -q 'preserve secret' "$UP_TEST/copied/config.dev.sh" && grep -q 'private key' "$UP_TEST/copied/deploy_key" \
  && grep -q 'site data' "$UP_TEST/copied/unrelated.txt" \
  && ok 'manual copied update preserves config, keys and unrelated files' || bad 'copied update preservation'
bash "$UP_TEST/copied/update.sh" rollback >/dev/null 2>&1
[ "$(cat "$UP_TEST/copied/VERSION")" = 1.0.0 ] && [ "$(cat "$UP_TEST/copied/.kit-update/blocked")" = v1.0.1 ] \
  && ok 'copied rollback restores original version and blocks automatic retry' || bad 'copied rollback'
up_test_config "$UP_TEST/auto" auto
PATH="$UP_PATH" bash "$UP_TEST/auto/update.sh" check >/dev/null 2>&1
[ "$(cat "$UP_TEST/auto/VERSION")" = 1.0.1 ] && ok 'auto mode installs compatible patch' || bad 'patch auto-update'
up_test_config "$UP_TEST/legacy"
printf 'KIT_UPDATE_MODE=""\nKIT_SELF_UPDATE="yes"\n' >> "$UP_TEST/legacy/config.sh"
PATH="$UP_PATH" bash "$UP_TEST/legacy/update.sh" check >/dev/null 2>&1
[ "$(cat "$UP_TEST/legacy/VERSION")" = 1.0.1 ] && ok 'legacy KIT_SELF_UPDATE yes maps to patch auto-update' || bad 'legacy update alias'

printf '\nLocal edit.\n' >> "$UP_TEST/dirty/README.md"
if bash "$UP_TEST/dirty/update.sh" apply v1.0.1 >/dev/null 2>&1; then bad 'local edits refused'; else
  grep -q 'Local edit' "$UP_TEST/dirty/README.md" && ok 'copied local edits refuse update and stay intact' || bad 'local edit preservation'
fi
PATH="$UP_PATH" bash "$UP_TEST/cloned/update.sh" apply v1.0.1 >/dev/null 2>&1
[ "$(cat "$UP_TEST/cloned/VERSION")" = 1.0.1 ] && git -C "$UP_TEST/cloned" diff --quiet \
  && [ -f "$UP_TEST/cloned/config.sh" ] && ok 'Git clone update keeps clean metadata and config' || bad 'Git clone update'
bash "$UP_TEST/cloned/update.sh" rollback >/dev/null 2>&1
[ "$(cat "$UP_TEST/cloned/VERSION")" = 1.0.0 ] && git -C "$UP_TEST/cloned" diff --quiet \
  && ok 'Git clone rollback restores commit and files' || bad 'Git clone rollback'

mkdir "$UP_TEST/gitfail/.kit-operation-lock"
echo "$$" > "$UP_TEST/gitfail/.kit-operation-lock/pid"
if bash "$UP_TEST/gitfail/update.sh" apply v1.0.1 >/dev/null 2>&1; then bad 'active kit lock'; else
  [ "$(cat "$UP_TEST/gitfail/VERSION")" = 1.0.0 ] && ok 'active deploy/update lock prevents installation race' || bad 'active lock preservation'
fi
mv "$UP_TEST/gitfail/.kit-operation-lock" "$UP_TEST/gitfail/held-lock"
up_test_config "$UP_TEST/offline" off
bash "$UP_TEST/offline/update.sh" check >/dev/null 2>&1
[ ! -e "$UP_TEST/offline/.kit-update/checked-main" ] && ok 'off mode does no upstream check' || bad 'off mode'

# Simulate a power loss after the backup journal, before files finish copying.
(
  source lib/kit-install.sh
  KIT_HOME="$UP_TEST/recover"; STATE="$KIT_HOME/.kit-update"; STAGE="$UP_TEST/upstream"
  mkdir -p "$STATE"
  kit_backup_release
  printf '\nInterrupted replacement.\n' >> "$KIT_HOME/README.md"
)
if bash "$UP_TEST/recover/update.sh" check >/dev/null 2>&1; then bad 'pending update refusal'; else ok 'interrupted update blocks later checks'; fi
bash "$UP_TEST/recover/update.sh" rollback >/dev/null 2>&1
kit_bundle_valid "$UP_TEST/recover" && ok 'interrupted update recovery restores verified baseline' || bad 'interrupted recovery'

# Add a stable major version; automatic updates must stop at this boundary.
printf '2.0.0\n' > "$UP_TEST/upstream/VERSION"
kit_bundle_hash "$UP_TEST/upstream" > "$UP_TEST/upstream/kit-files.sha256"
git -C "$UP_TEST/upstream" add .
git -C "$UP_TEST/upstream" -c user.name=test -c user.email=test@example.test commit -qm major
git -C "$UP_TEST/upstream" tag v2.0.0
up_test_config "$UP_TEST/major" auto
PATH="$UP_PATH" bash "$UP_TEST/major/update.sh" check >/dev/null 2>&1
[ "$(cat "$UP_TEST/major/VERSION")" = 1.0.0 ] && ok 'major release only notifies in auto mode' || bad 'major auto-update guard'
if bash "$UP_TEST/major/update.sh" apply v2.0.0 >/dev/null 2>&1; then bad 'major requires opt-in'; else ok 'major manual apply requires explicit allow-major'; fi
bash "$UP_TEST/major/update.sh" apply v2.0.0 --allow-major >/dev/null 2>&1
[ "$(cat "$UP_TEST/major/VERSION")" = 2.0.0 ] && ok 'explicit major opt-in installs selected release' || bad 'major explicit apply'

printf '\nCorrupt published contents.\n' >> "$UP_TEST/upstream/README.md"
git -C "$UP_TEST/upstream" add .
git -C "$UP_TEST/upstream" -c user.name=test -c user.email=test@example.test commit -qm corrupt
git -C "$UP_TEST/upstream" tag v2.0.1
if bash "$UP_TEST/collision/update.sh" apply v2.0.1 --allow-major >/dev/null 2>&1; then bad 'corrupt release rejected'; else
  [ "$(cat "$UP_TEST/collision/VERSION")" = 1.0.0 ] && ok 'invalid release checksums leave installation untouched' || bad 'corrupt release preservation'
fi
kit_path_valid config.example.sh && ! kit_path_valid config.dev.sh && ! kit_path_valid ../outside.sh \
  && ! kit_path_valid lib/config.secret.sh && ok 'package paths exclude secrets and traversal' || bad 'package path safety'
kit_bundle_syntax . && ok 'all packaged Bash scripts have valid syntax' || bad 'package Bash syntax'
