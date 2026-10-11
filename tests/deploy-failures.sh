#!/bin/bash
# Sourced by test.sh: verify failed deploy commands never record success.
echo "== Deploy command failure guards =="
GUARD_TMP="$TMP/failure-guards"
mkdir -p "$GUARD_TMP/kit" "$GUARD_TMP/bin" "$GUARD_TMP/app"
cp auto_deploy.sh "$GUARD_TMP/kit/"
printf 'keep me\n' > "$GUARD_TMP/app/sentinel"
GUARD_GIT="$(command -v git)"
export GUARD_GIT
cat > "$GUARD_TMP/bin/git" <<'GIT_STUB'
#!/bin/bash
for arg in "$@"; do
  [ "$arg" = "$GUARD_FAIL" ] && exit 1
done
exec "$GUARD_GIT" "$@"
GIT_STUB
printf '#!/bin/bash\nexit 1\n' > "$GUARD_TMP/bin/rsync"
chmod +x "$GUARD_TMP/bin/git" "$GUARD_TMP/bin/rsync"
for GUARD_FAIL in clone fetch checkout reset rsync; do
  export GUARD_FAIL
  GUARD_WS="$GUARD_TMP/ws-$GUARD_FAIL"
  if [ "$GUARD_FAIL" != clone ]; then
    "$GUARD_GIT" clone -q --single-branch --branch main "$BARE" "$GUARD_WS/main"
  fi
  cat > "$GUARD_TMP/kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$GUARD_TMP/app"
WORKSPACE_BASE="$GUARD_WS"
LOG_FILE="$GUARD_TMP/$GUARD_FAIL.log"
HEALTH_URL=""
NOTIFY_ON_SUCCESS="no"
BUILD_CMD="touch '$GUARD_TMP/build-ran'"
CFG
  GUARD_OUT="$(PATH="$GUARD_TMP/bin:$PATH" bash "$GUARD_TMP/kit/auto_deploy.sh" main 2>&1)"
  GUARD_STATUS=$?
  if [ "$GUARD_STATUS" -ne 0 ] && echo "$GUARD_OUT" | grep -q "$GUARD_FAIL failed" \
      && [ ! -f "$GUARD_WS/main/.deployed_sha" ] && [ ! -f "$GUARD_TMP/build-ran" ] \
      && [ ! -d "$GUARD_WS/.deploy-lock" ] && grep -qx 'keep me' "$GUARD_TMP/app/sentinel"; then
    ok "$GUARD_FAIL failure aborts before build and SHA recording"
  else
    bad "$GUARD_FAIL failure guard (exit $GUARD_STATUS): $GUARD_OUT"
  fi
done
unset GUARD_GIT GUARD_FAIL

# Mock only the command boundaries here: a failed rollback must stay retryable.
printf '#!/bin/bash\nexit 0\n' > "$GUARD_TMP/bin/rsync"
printf '#!/bin/bash\nexit 1\n' > "$GUARD_TMP/bin/curl"
printf '#!/bin/bash\nexit 1\n' > "$GUARD_TMP/kit/rollback.sh"
chmod +x "$GUARD_TMP/bin/curl"
GUARD_PREV="$(git -C "$GUARD_TMP/ws-fetch/main" rev-parse HEAD~1)"
echo "$GUARD_PREV" > "$GUARD_TMP/ws-fetch/main/.deployed_sha"
cat >> "$GUARD_TMP/kit/config.sh" <<CFG
WORKSPACE_BASE="$GUARD_TMP/ws-fetch"
BUILD_CMD=""
HEALTH_URL="http://example.test/"
HEALTH_WAIT="0"
HEALTH_RETRY="1"
AUTO_ROLLBACK_ON_FAIL="yes"
CFG
# Restore real git for this case; only curl, rsync and rollback are mocked.
GUARD_GIT="$(command -v git)"; export GUARD_GIT
GUARD_OUT="$(PATH="$GUARD_TMP/bin:$PATH" bash "$GUARD_TMP/kit/auto_deploy.sh" main 2>&1)"
GUARD_STATUS=$?
if [ "$GUARD_STATUS" -ne 0 ] && echo "$GUARD_OUT" | grep -q 'Auto-rollback FAILED' \
    && [ "$(cat "$GUARD_TMP/ws-fetch/main/.deployed_sha")" = "$GUARD_PREV" ] \
    && [ ! -f "$GUARD_TMP/ws-fetch/main/.failed_sha" ] \
    && [ ! -d "$GUARD_TMP/ws-fetch/.deploy-lock" ]; then
  ok "failed auto-rollback reports failure and permits retry"
else
  bad "failed auto-rollback guard (exit $GUARD_STATUS): $GUARD_OUT"
fi
unset GUARD_GIT
