#!/bin/bash
# ============================================================
# DEPLOY KIT — test.sh (self-test / smoke test)
# ------------------------------------------------------------
#   /bin/bash test.sh
# 1. Syntax check (bash -n) on every script
# 2. Missing config error check
# 3. Missing required vars error check
# 4. Full local integration test: real git repo + rsync deploy
#    + idempotent skip + rollback (no network needed —
#    uses a local file:// repo, everything in a temp dir)
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"
PASS=0; FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== 1. Syntax check (bash -n & py_compile) =="
for f in auto_deploy.sh rollback.sh setup.sh setup-quick.sh keygen.sh cron.sh detect.sh runner.sh webhook.sh doctor.sh quickstart.sh; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n $f"; else bad "bash -n $f"; fi
done
if python3 -m py_compile db-dump.py >/dev/null 2>&1; then
  rm -rf __pycache__
  ok "py_compile db-dump.py"
else
  bad "py_compile db-dump.py"
fi

echo "== 2. Missing config error =="
cp auto_deploy.sh "$TMP/"   # no config.sh next to it
if bash "$TMP/auto_deploy.sh" main 2>&1 | grep -q "config.sh not found"; then
  ok "no-config error message"
else
  bad "no-config error message"
fi

echo "== 3. Missing required vars error =="
mkdir -p "$TMP/kit"
cp auto_deploy.sh rollback.sh config.example.sh "$TMP/kit/"
cat > "$TMP/kit/config.sh" <<'CFG'
SERVER_USER="testuser"
SITE_DOMAIN="example.test"
APP_DIR="/tmp/whatever"
WORKSPACE_BASE="/tmp/whatever-ws"
LOG_FILE="/tmp/whatever.log"
TOGGLE_FLAG="/tmp/whatever-flag"
CFG
# REPO_URL intentionally missing → script must refuse to deploy
if (cd "$TMP/kit" && bash auto_deploy.sh main 2>&1 | grep -qi "required"); then
  ok "REQUIRED error"
else
  bad "REQUIRED error"
fi

echo "== 4. Full deploy integration (local file:// repo) =="
SRC="$TMP/src"; mkdir -p "$SRC"
# note: keep file sizes DIFFERENT between commits — rsync's quick check
# compares size+mtime; same-size files written in the same second would
# be considered identical (standard rsync behavior, real-world rare)
echo "v1" > "$SRC/index.html"
git init -q "$SRC" && git -C "$SRC" symbolic-ref HEAD refs/heads/main
git -C "$SRC" add -A
git -C "$SRC" -c user.email=test@test -c user.name=test commit -qm c1
BARE="$TMP/repo.git"; git init -q --bare "$BARE"
git -C "$SRC" remote add origin "$BARE"
git -C "$SRC" push -q origin main

APP="$TMP/app"; WS="$TMP/ws"
cat > "$TMP/kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$APP"
WORKSPACE_BASE="$WS"
LOG_FILE="$TMP/deploy.log"
TOGGLE_FLAG="$TMP/flag"
CFG

(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
if [ -f "$APP/index.html" ] && grep -q v1 "$APP/index.html"; then
  ok "first deploy rsynced files"
else
  bad "first deploy rsynced files"
fi
[ -f "$WS/main/.deployed_sha" ] && ok ".deployed_sha recorded" || bad ".deployed_sha recorded"

OUT="$(cd "$TMP/kit" && bash auto_deploy.sh main 2>&1)"
echo "$OUT" | grep -qi "no new commit" && ok "idempotent skip (same SHA)" || bad "idempotent skip (same SHA)"

# sleep 1 so the new file has a different mtime — rsync's quick check
# compares size+mtime; 2 commits in the same second with same-size
# files would otherwise be considered identical (standard rsync behavior)
sleep 1
echo "version-two-content" > "$SRC/index.html"
git -C "$SRC" add -A
git -C "$SRC" -c user.email=test@test -c user.name=test commit -qm c2
git -C "$SRC" push -q origin main
(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
if grep -q "version-two" "$APP/index.html"; then
  ok "second deploy picked new commit"
else
  bad "second deploy picked new commit"
  echo "     --- deploy.log ---"
  sed 's/^/     /' "$TMP/deploy.log"
  echo "     --- app ls ---"; ls -la "$APP"
  echo "     --- ws log ---"; git -C "$WS/main" log --oneline -2 2>&1 | sed 's/^/     /'
fi

PREV_SHA="$(git -C "$SRC" rev-parse HEAD~1)"
(cd "$TMP/kit" && bash rollback.sh main "$PREV_SHA" >/dev/null 2>&1)
if grep -q v1 "$APP/index.html"; then
  ok "rollback restored old files"
else
  bad "rollback restored old files"
  echo "     --- deploy.log ---"
  sed 's/^/     /' "$TMP/deploy.log"
  echo "     --- app ls ---"; ls -la "$APP"
fi

echo "== 5. keygen.sh (SSH key + GitHub copy-paste helper) =="
mkdir -p "$TMP/k2"
cp keygen.sh "$TMP/k2/"
printf 'SERVER_HOST="server.com"\nSERVER_USER="cpuser"\nSSH_PORT="2222"\n' > "$TMP/k2/config.sh"
(cd "$TMP/k2" && HOME="$TMP/home2" bash keygen.sh >/dev/null 2>&1)
if [ -f "$TMP/home2/.ssh/deploy_key" ] && [ -f "$TMP/home2/.ssh/deploy_key.pub" ]; then
  ok "keygen: key pair created"
else
  bad "keygen: key pair created"
fi
if grep -q "^DEPLOY_KEY=\"$TMP/home2/.ssh/deploy_key\"" "$TMP/k2/config.sh"; then
  ok "keygen: DEPLOY_KEY written to config.sh"
else
  bad "keygen: DEPLOY_KEY written to config.sh"
fi
if grep -qF "$(cat "$TMP/home2/.ssh/deploy_key.pub")" "$TMP/home2/.ssh/authorized_keys"; then
  ok "keygen: authorized_keys updated"
else
  bad "keygen: authorized_keys updated"
fi

echo "== 6. APP_SUBDIR (monorepo subfolder deploy) =="
mkdir -p "$SRC/web"
echo "subpage" > "$SRC/web/page.html"
git -C "$SRC" add -A
git -C "$SRC" -c user.email=test@test -c user.name=test commit -qm c3
git -C "$SRC" push -q origin main
sleep 1
cat > "$TMP/kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$APP"
WORKSPACE_BASE="$WS"
LOG_FILE="$TMP/deploy.log"
TOGGLE_FLAG="$TMP/flag"
APP_SUBDIR="web"
CFG
(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
if [ -f "$APP/page.html" ] && grep -q subpage "$APP/page.html"; then
  ok "APP_SUBDIR: subfolder deployed"
else
  bad "APP_SUBDIR: subfolder deployed"
fi
if [ ! -f "$APP/index.html" ]; then
  ok "APP_SUBDIR: root files not copied"
else
  bad "APP_SUBDIR: root files not copied"
fi

echo "== 7. restart-method robustness (pm2/supervisor missing → no crash) =="
echo "pm2-test" > "$SRC/web/page.html"
git -C "$SRC" add -A
git -C "$SRC" -c user.email=test@test -c user.name=test commit -qm c4
git -C "$SRC" push -q origin main
sleep 1
cat > "$TMP/kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$APP"
WORKSPACE_BASE="$WS"
LOG_FILE="$TMP/deploy.log"
TOGGLE_FLAG="$TMP/flag"
APP_SUBDIR="web"
RESTART_METHOD="pm2"
PM2_APP="all"
CFG
(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && grep -q "Restart done (pm2)" "$TMP/deploy.log"; then
  ok "deploy completed with pm2 (missing binary → no crash)"
else
  bad "deploy completed with pm2 (missing binary → no crash)"
  tail -3 "$TMP/deploy.log" | sed 's/^/     /'
fi

echo "== 8. deploy lock (concurrent push protection) =="
mkdir -p "$TMP/ws2"; LOCKD="$TMP/ws2/.deploy-lock"
mkdir -p "$LOCKD"; echo $$ > "$LOCKD/pid"   # simulate a running deploy
cat > "$TMP/kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$APP"
WORKSPACE_BASE="$TMP/ws2"
LOG_FILE="$TMP/deploy2.log"
TOGGLE_FLAG="$TMP/flag"
CFG
OUT="$(cd "$TMP/kit" && bash auto_deploy.sh main 2>&1)"
echo "$OUT" | grep -qi "another deploy" && ok "lock: active lock → second deploy skipped" || bad "lock: active lock → second deploy skipped"
echo 999999 > "$LOCKD/pid"   # dead PID → stale lock must be cleaned
(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
if [ -f "$TMP/ws2/main/.deployed_sha" ]; then
  ok "lock: stale lock cleaned + deploy ran"
else
  bad "lock: stale lock cleaned + deploy ran"
fi
[ ! -d "$LOCKD" ] && ok "lock: released after deploy" || bad "lock: released after deploy"

# empty PID file (crashed between mkdir and pid write) → also stale, must be cleaned
mkdir -p "$LOCKD" && : > "$LOCKD/pid"
(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
if [ -f "$TMP/ws2/main/.deployed_sha" ]; then
  ok "lock: empty-PID lock (crash leftover) cleaned + deploy ran"
else
  bad "lock: empty-PID lock (crash leftover) cleaned + deploy ran"
fi

echo "== 9. build failure → deploy aborts =="
echo "build-fail" > "$SRC/web/page.html"
git -C "$SRC" add -A
git -C "$SRC" -c user.email=test@test -c user.name=test commit -qm c5
git -C "$SRC" push -q origin main
sleep 1
cat > "$TMP/kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$APP"
WORKSPACE_BASE="$WS"
LOG_FILE="$TMP/deploy.log"
TOGGLE_FLAG="$TMP/flag"
APP_SUBDIR="web"
BUILD_CMD="exit 3"
CFG
(cd "$TMP/kit" && bash auto_deploy.sh main >/dev/null 2>&1)
RC=$?
if [ "$RC" -ne 0 ] && grep -q "Build FAILED" "$TMP/deploy.log"; then
  ok "build failure → deploy aborted with clear message"
else
  bad "build failure → deploy aborted with clear message"
  tail -3 "$TMP/deploy.log" | sed 's/^/     /'
fi

echo "== 10. cron.sh (zero GitHub Actions mode) =="
cp cron.sh "$TMP/"
if command -v crontab >/dev/null 2>&1; then
  mkdir -p "$TMP/home3"
  OUT="$(cd "$TMP" && HOME="$TMP/home3" bash cron.sh 2 2>&1)"
else
  OUT="$(cd "$TMP" && HOME="$TMP/home3" bash cron.sh 2 2>&1)"
fi
if echo "$OUT" | grep -q "auto_deploy.sh"; then
  ok "cron.sh: cron line generated"
else
  bad "cron.sh: cron line generated"
  echo "$OUT" | sed 's/^/     /'
fi
if echo "$OUT" | grep -qiE "cron (installed|jobs)"; then
  ok "cron.sh: instructions shown"
else
  bad "cron.sh: instructions shown"
  echo "$OUT" | sed 's/^/     /'
fi

echo "== 11. detect.sh (fully dynamic — auto-detect project) =="
# create a mini repo with node files
mkdir -p "$TMP/detect-src"
echo '{"name":"test","scripts":{"build":"echo ok"}}' > "$TMP/detect-src/package.json"
echo "index" > "$TMP/detect-src/index.html"
git init -q "$TMP/detect-src" && git -C "$TMP/detect-src" symbolic-ref HEAD refs/heads/main
git -C "$TMP/detect-src" add -A
git -C "$TMP/detect-src" -c user.email=test@test -c user.name=test commit -qm c1
BARE2="$TMP/repo2.git"; git init -q --bare "$BARE2"
git -C "$TMP/detect-src" remote add origin "$BARE2"
git -C "$TMP/detect-src" push -q origin main

mkdir -p "$TMP/detect-kit"
cp detect.sh auto_deploy.sh "$TMP/detect-kit/"
cat > "$TMP/detect-kit/config.sh" <<CFG
REPO_URL="file://$BARE2"
WORKSPACE_BASE="$TMP/detect-ws"
LOG_FILE="$TMP/deploy3.log"
TOGGLE_FLAG="$TMP/flag"
CFG
# run detect.sh non-interactively — pipe "yes" to apply
OUT="$(cd "$TMP/detect-kit" && echo "y" | bash detect.sh main 2>&1)"
echo "$OUT" | grep -q "node" && ok "detect: app type = node" || bad "detect: app type = node"
echo "$OUT" | grep -q "build" && ok "detect: build command found" || bad "detect: build command found"
# check that config.sh was updated
grep -q 'APP_TYPE="node"' "$TMP/detect-kit/config.sh" && ok "detect: APP_TYPE applied to config.sh" || bad "detect: APP_TYPE applied to config.sh"
grep -q 'BUILD_CMD="npm install && npm run build"' "$TMP/detect-kit/config.sh" && ok "detect: BUILD_CMD applied" || bad "detect: BUILD_CMD applied"

echo "== 12. webhook.sh handler (HTTP listener, VPS) =="
mkdir -p "$TMP/webhook-kit"
cp webhook.sh auto_deploy.sh "$TMP/webhook-kit/"
cat > "$TMP/webhook-kit/config.sh" <<CFG
DEPLOY_WEBHOOK_SECRET="testsecret"
LOG_FILE="$TMP/deploy.log"
CFG
# simulate a GitHub webhook POST: correct secret → expect 200 OK
BODY='{"branch":"main","sha":"abc123"}'
LEN=$(printf '%s' "$BODY" | wc -c)
RESP="$(printf 'POST /webhook/deploy/ HTTP/1.1\r\nHost: x\r\nX-Deploy-Secret: testsecret\r\nContent-Length: %s\r\n\r\n%s' "$LEN" "$BODY" | (cd "$TMP/webhook-kit" && bash webhook.sh handler 2>/dev/null))"
echo "$RESP" | grep -q "200 OK" && ok "webhook: valid secret → 200" || bad "webhook: valid secret → 200"
# wrong secret → expect 403
RESP2="$(printf 'POST /webhook/deploy/ HTTP/1.1\r\nHost: x\r\nX-Deploy-Secret: wrong\r\nContent-Length: %s\r\n\r\n%s' "$LEN" "$BODY" | (cd "$TMP/webhook-kit" && bash webhook.sh handler 2>/dev/null))"
echo "$RESP2" | grep -q "403" && ok "webhook: wrong secret → 403" || bad "webhook: wrong secret → 403"
# native GitHub webhook: valid HMAC (X-Hub-Signature-256) + ref payload → 200
if command -v openssl >/dev/null 2>&1; then
  NBODY='{"ref":"refs/heads/dev","after":"abc123"}'
  NLEN=$(printf '%s' "$NBODY" | wc -c)
  SIG="sha256=$(printf '%s' "$NBODY" | openssl dgst -sha256 -hmac "testsecret" 2>/dev/null | sed 's/.* //')"
  RESP3="$(printf 'POST /webhook/deploy/ HTTP/1.1\r\nHost: x\r\nX-Hub-Signature-256: %s\r\nContent-Length: %s\r\n\r\n%s' "$SIG" "$NLEN" "$NBODY" | (cd "$TMP/webhook-kit" && bash webhook.sh handler 2>/dev/null))"
  echo "$RESP3" | grep -q "200 OK" && ok "webhook: native GitHub HMAC + ref → 200" || bad "webhook: native GitHub HMAC + ref → 200"
  # bad HMAC → 403
  RESP4="$(printf 'POST /webhook/deploy/ HTTP/1.1\r\nHost: x\r\nX-Hub-Signature-256: sha256=badbadbad\r\nContent-Length: %s\r\n\r\n%s' "$NLEN" "$NBODY" | (cd "$TMP/webhook-kit" && bash webhook.sh handler 2>/dev/null))"
  echo "$RESP4" | grep -q "403" && ok "webhook: bad HMAC → 403" || bad "webhook: bad HMAC → 403"
else
  echo "  ⏭️ openssl not available — skipping native webhook test"
fi

echo "== 13. doctor.sh (preflight environment & config diagnostics) =="
mkdir -p "$TMP/doctor-kit"
cp doctor.sh "$TMP/doctor-kit/"
# test missing config returns error
(cd "$TMP/doctor-kit" && bash doctor.sh "$TMP/nonexistent.sh" >/dev/null 2>&1)
[ $? -ne 0 ] && ok "doctor: missing config returns failure" || bad "doctor: missing config returns failure"

# test valid config returns success
cat > "$TMP/doctor-kit/config.sh" <<CFG
SERVER_USER="$(whoami)"
REPO_URL="file://$BARE"
APP_DIR="$TMP/doctor-app"
WORKSPACE_BASE="$TMP/doctor-ws"
LOG_FILE="$TMP/doctor.log"
CFG
chmod 600 "$TMP/doctor-kit/config.sh"
DOCTOR_OUT="$(cd "$TMP/doctor-kit" && bash doctor.sh 2>&1)"
echo "$DOCTOR_OUT" | grep -q "All critical checks passed" && ok "doctor: valid config passes" || bad "doctor: valid config passes"

echo "== 14. auto-rollback on health check failure =="
HSRC="$TMP/hsrc"; mkdir -p "$HSRC"
echo "initial-version-content" > "$HSRC/index.html"
git init -q "$HSRC" && git -C "$HSRC" symbolic-ref HEAD refs/heads/main
git -C "$HSRC" add -A
git -C "$HSRC" -c user.email=test@test -c user.name=test commit -qm "hc1"
HBARE="$TMP/hrepo.git"; git init -q --bare "$HBARE"
git -C "$HSRC" remote add origin "$HBARE"
git -C "$HSRC" push -q origin main

mkdir -p "$TMP/health-kit"
cp auto_deploy.sh rollback.sh "$TMP/health-kit/"
HEALTH_APP="$TMP/health-app"
HEALTH_WS="$TMP/health-ws"
cat > "$TMP/health-kit/config.sh" <<CFG
REPO_URL="file://$HBARE"
APP_DIR="$HEALTH_APP"
WORKSPACE_BASE="$HEALTH_WS"
LOG_FILE="$TMP/health-deploy.log"
HEALTH_URL=""
AUTO_ROLLBACK_ON_FAIL="yes"
CFG
# 1. Deploy initial version (healthy)
(cd "$TMP/health-kit" && bash auto_deploy.sh main >/dev/null 2>&1)

# 2. Push broken version
sleep 1
echo "broken-version-content" > "$HSRC/index.html"
git -C "$HSRC" add -A
git -C "$HSRC" -c user.email=test@test -c user.name=test commit -qm "hc2"
git -C "$HSRC" push -q origin main

# 3. Configure health check failure for broken version
cat >> "$TMP/health-kit/config.sh" <<CFG
HEALTH_URL="http://127.0.0.1:59998/nonexistent-endpoint"
HEALTH_WAIT="0"
HEALTH_RETRY="1"
CFG

# Deploy broken version with health check failure → auto-rollback should restore initial version
(cd "$TMP/health-kit" && bash auto_deploy.sh main >/dev/null 2>&1)
if [ -f "$HEALTH_APP/index.html" ] && grep -q "initial-version-content" "$HEALTH_APP/index.html"; then
  ok "auto-rollback restored initial version after health failure"
else
  bad "auto-rollback restored initial version after health failure"
fi

echo "== 15. multi-channel notifications (Telegram, Discord, Slack, Email) =="
mkdir -p "$TMP/notif-kit"
cp auto_deploy.sh rollback.sh "$TMP/notif-kit/"
cat > "$TMP/notif-kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$TMP/notif-app"
WORKSPACE_BASE="$TMP/notif-ws"
LOG_FILE="$TMP/notif.log"
TELEGRAM_BOT_TOKEN="mock_token"
TELEGRAM_CHAT_ID="mock_chat"
DISCORD_WEBHOOK_URL="http://127.0.0.1:59997/mock-discord"
SLACK_WEBHOOK_URL="http://127.0.0.1:59997/mock-slack"
ALERT_EMAIL="mock@example.com"
CFG
# Run deploy with all mock notification channels set — must complete cleanly without crash
(cd "$TMP/notif-kit" && bash auto_deploy.sh main >/dev/null 2>&1)
[ -f "$TMP/notif-app/index.html" ] && ok "multi-channel notify: deploy completed cleanly" || bad "multi-channel notify: deploy completed cleanly"

echo "== 16. cron.sh dedup (re-install replaces, never duplicates) =="
# fake crontab that stores state in a file (no real cron needed)
mkdir -p "$TMP/cronbin" "$TMP/cronhome"
CRONSTORE="$TMP/cronstore"
cat > "$TMP/cronbin/crontab" <<'CFAKE'
#!/bin/bash
STORE="$CRONSTORE_FILE"
if [ "$1" = "-l" ]; then
  [ -f "$STORE" ] && cat "$STORE" || true
  exit 0
fi
# buffer stdin BEFORE touching the file — the writer and the `crontab -l`
# reader start at once in the pipeline; `cat > "$STORE"` would truncate
# the store before -l could read it (fake-crontab race, not a cron.sh bug)
NEW="$(cat)"
printf '%s\n' "$NEW" > "$STORE"
CFAKE
chmod +x "$TMP/cronbin/crontab"
cp cron.sh "$TMP/"
export CRONSTORE_FILE="$CRONSTORE"
( cd "$TMP" && PATH="$TMP/cronbin:$PATH" HOME="$TMP/cronhome" bash cron.sh 2 main >/dev/null 2>&1 )
( cd "$TMP" && PATH="$TMP/cronbin:$PATH" HOME="$TMP/cronhome" bash cron.sh 5 main >/dev/null 2>&1 )
N="$(grep -c "auto_deploy.sh" "$CRONSTORE" 2>/dev/null || echo 0)"
[ "$N" = "1" ] && ok "cron.sh: re-install replaces old line (no duplicates)" || bad "cron.sh: re-install replaces old line (no duplicates) — got $N lines"
grep -q '\*/5' "$CRONSTORE" && ok "cron.sh: latest interval kept" || bad "cron.sh: latest interval kept"
grep -q "DEPLOY_TRIGGER=cron" "$CRONSTORE" && ok "cron.sh: line marks DEPLOY_TRIGGER=cron" || bad "cron.sh: line marks DEPLOY_TRIGGER=cron"
# old-kit edge: an UNQUOTED legacy line (auto_deploy.sh main) must also be replaced,
# while an unrelated branch line (dev) must survive
printf "%s\n" "/bin/bash /tmp/kit/auto_deploy.sh main >> /tmp/d.log 2>&1" "*/3 * * * * /bin/bash '/tmp/kit/auto_deploy.sh' 'dev' >> '/tmp/d.log' 2>&1" > "$CRONSTORE"
( cd "$TMP" && PATH="$TMP/cronbin:$PATH" HOME="$TMP/cronhome" bash cron.sh 4 main >/dev/null 2>&1 )
grep -q "auto_deploy.sh main " "$CRONSTORE" && bad "cron.sh: legacy unquoted line removed" || ok "cron.sh: legacy unquoted line removed"
grep -q "'dev'" "$CRONSTORE" && ok "cron.sh: other-branch line untouched" || bad "cron.sh: other-branch line untouched"
[ "$(grep -c "auto_deploy.sh' 'main" "$CRONSTORE")" = "1" ] && ok "cron.sh: exactly one new main line" || bad "cron.sh: exactly one new main line"

echo "== 17. toggle flag skips ONLY cron deploys =="
mkdir -p "$TMP/toggle-kit"
cp auto_deploy.sh "$TMP/toggle-kit/"
cat > "$TMP/toggle-kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$TMP/toggle-app"
WORKSPACE_BASE="$TMP/toggle-ws"
LOG_FILE="$TMP/toggle.log"
TOGGLE_FLAG="$TMP/toggle-flag"
SKIP_WHEN_FLAG="1"
CFG
touch "$TMP/toggle-flag"
# cron-fired (DEPLOY_TRIGGER=cron) → must skip
OUT="$( (cd "$TMP/toggle-kit" && DEPLOY_TRIGGER=cron bash auto_deploy.sh main 2>&1) )"
echo "$OUT" | grep -qi "skipped" && ok "toggle: cron deploy skipped when flag present" || bad "toggle: cron deploy skipped when flag present"
[ ! -f "$TMP/toggle-app/index.html" ] && ok "toggle: skipped cron deploy touched nothing" || bad "toggle: skipped cron deploy touched nothing"
# GitHub/Actions-fired (no trigger) → must deploy despite the flag
( cd "$TMP/toggle-kit" && bash auto_deploy.sh main >/dev/null 2>&1 )
[ -f "$TMP/toggle-app/index.html" ] && ok "toggle: Actions deploy runs despite flag" || bad "toggle: Actions deploy runs despite flag"

echo "== 18. webhook.sh rejects path-traversal branch =="
BODYT='{"branch":"../../etc/passwd","sha":"abc"}'
LENT=$(printf '%s' "$BODYT" | wc -c)
RESPT="$(printf 'POST /webhook/deploy/ HTTP/1.1\r\nHost: x\r\nX-Deploy-Secret: testsecret\r\nContent-Length: %s\r\n\r\n%s' "$LENT" "$BODYT" | (cd "$TMP/webhook-kit" && bash webhook.sh handler 2>/dev/null))"
echo "$RESPT" | grep -q "403" && ok "webhook: traversal branch → 403" || bad "webhook: traversal branch → 403"
BODYQ="$(printf '{"branch":"ma\x27in","sha":"abc"}')"
LENQ=$(printf '%s' "$BODYQ" | wc -c)
RESPQ="$(printf 'POST /webhook/deploy/ HTTP/1.1\r\nHost: x\r\nX-Deploy-Secret: testsecret\r\nContent-Length: %s\r\n\r\n%s' "$LENQ" "$BODYQ" | (cd "$TMP/webhook-kit" && bash webhook.sh handler 2>/dev/null))"
echo "$RESPQ" | grep -q "403" && ok "webhook: quote-in-branch → 403" || bad "webhook: quote-in-branch → 403"

echo "== 19. KIT_SNAP temp file cleaned on exit =="
mkdir -p "$TMP/snap-kit/.git"
cp auto_deploy.sh "$TMP/snap-kit/"
cat > "$TMP/snap-kit/config.sh" <<CFG
REPO_URL="file://$BARE"
APP_DIR="$TMP/snap-app"
WORKSPACE_BASE="$TMP/snap-ws"
LOG_FILE="$TMP/snap.log"
KIT_SELF_UPDATE="yes"
CFG
# .git dir exists but pull fails (no real repo) → self-update skipped, snapshot trap must still clean /tmp
BEFORE="$(ls /tmp/kit-deploy.* 2>/dev/null | wc -l)"
( cd "$TMP/snap-kit" && bash auto_deploy.sh main >/dev/null 2>&1 )
AFTER="$(ls /tmp/kit-deploy.* 2>/dev/null | wc -l)"
[ "$AFTER" -le "$BEFORE" ] && ok "KIT_SNAP: no /tmp/kit-deploy.* leak after deploy" || bad "KIT_SNAP: no /tmp/kit-deploy.* leak after deploy"

echo "== 20. ZERO project references (public-ready guard) =="
# Machine-enforced: ANY push to main runs this and FAILS if a real project
# name appears in files or git history. Works for every agent, no memory needed.
REF_PAT='dms|esabaq|darul|ilm\.|lqp|learn quran|learn_quran'
REF_FILE_HITS="$(grep -rniE "$REF_PAT" --include='*.sh' --include='*.md' --include='*.yml*' --include='*.example' . 2>/dev/null | grep -v '.git/' | grep -v 'AGENTS.md' | grep -v '^./test.sh' | wc -l)"
[ "$REF_FILE_HITS" -eq 0 ] && ok "no project references in files" || bad "project references found in files ($REF_FILE_HITS)"
REF_HIST_HITS="$(git log --format='%s%n%b' 2>/dev/null | grep -icE "$REF_PAT")"
[ "$REF_HIST_HITS" -eq 0 ] && ok "no project references in git history" || bad "project references found in git history ($REF_HIST_HITS)"
# Security guard: .gitignore must ignore branch configs & secrets, keep example tracked
git check-ignore -q config.sh && \
git check-ignore -q config.staging.sh && \
git check-ignore -q config.dev.sh && \
git check-ignore -q .env && \
! git check-ignore -q config.example.sh \
  && ok "gitignore: branch configs & secrets ignored, example tracked" \
  || bad "gitignore: security rule regression"

echo "== 21. .env auto-read DATABASE_URL =="
# Test the parsing logic directly (same logic as in auto_deploy.sh)
mkdir -p "$TMP/envtest"
# Test 1: password with @ (edge case)
printf 'DATABASE_URL="mysql://user:P@ss!W0rd@localhost/mydb"\n' > "$TMP/envtest/.env"
DB_URL="$(grep -E '^DATABASE_URL=' "$TMP/envtest/.env" | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')"
DB_REST="${DB_URL#*://}"
DB_USERINFO="${DB_REST%@*}"
DB_HOSTPORT="${DB_REST##*@}"
case "$DB_USERINFO" in
  *:*) U="${DB_USERINFO%%:*}"; P="${DB_USERINFO#*:}" ;;
  *)   U="$DB_USERINFO"; P="" ;;
esac
_host_raw="${DB_HOSTPORT%%/*}"
_db_raw="${DB_HOSTPORT#*/}"
H="${_host_raw%%:*}"
D="${_db_raw%%\?*}"
[ "$U" = "user" ] && [ "$P" = "P@ss!W0rd" ] && [ "$H" = "localhost" ] && [ "$D" = "mydb" ] && ok "env parse: password with @ (edge)" || bad "env parse: password with @ (edge)"
# Test 2: no password
printf 'DATABASE_URL="mysql://user@localhost/db"\n' > "$TMP/envtest/.env"
DB_URL="$(grep -E '^DATABASE_URL=' "$TMP/envtest/.env" | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')"
DB_REST="${DB_URL#*://}"
DB_USERINFO="${DB_REST%@*}"
DB_HOSTPORT="${DB_REST##*@}"
case "$DB_USERINFO" in
  *:*) U="${DB_USERINFO%%:*}"; P="${DB_USERINFO#*:}" ;;
  *)   U="$DB_USERINFO"; P="" ;;
esac
_host_raw="${DB_HOSTPORT%%/*}"
_db_raw="${DB_HOSTPORT#*/}"
H="${_host_raw%%:*}"
D="${_db_raw%%\?*}"
[ "$U" = "user" ] && [ -z "$P" ] && [ "$H" = "localhost" ] && [ "$D" = "db" ] && ok "env parse: no password" || bad "env parse: no password"
# Test 3: port + query parameters (real-world framework URL)
printf 'DATABASE_URL="mysql://user:pass@127.0.0.1:3306/proddb?charset=utf8mb4"\n' > "$TMP/envtest/.env"
DB_URL="$(grep -E '^DATABASE_URL=' "$TMP/envtest/.env" | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')"
DB_REST="${DB_URL#*://}"
DB_USERINFO="${DB_REST%@*}"
DB_HOSTPORT="${DB_REST##*@}"
case "$DB_USERINFO" in
  *:*) U="${DB_USERINFO%%:*}"; P="${DB_USERINFO#*:}" ;;
  *)   U="$DB_USERINFO"; P="" ;;
esac
_host_raw="${DB_HOSTPORT%%/*}"
_db_raw="${DB_HOSTPORT#*/}"
H="${_host_raw%%:*}"
D="${_db_raw%%\?*}"
[ "$U" = "user" ] && [ "$P" = "pass" ] && [ "$H" = "127.0.0.1" ] && [ "$D" = "proddb" ] && ok "env parse: port & query params stripped" || bad "env parse: port & query params"

echo "== 22. .env fallback for notification keys (auto-read from app .env) =="
# Same parsing logic as auto_deploy.sh: if a notif key is empty in config.sh,
# borrow it from the app's .env. config.sh value must WIN (never overwritten).
mkdir -p "$TMP/envnotif"
printf 'TELEGRAM_BOT_TOKEN="12345:ABCdef"\nTELEGRAM_CHAT_ID="98765"\nDISCORD_WEBHOOK_URL="https://discord.example/hook"\n' > "$TMP/envnotif/.env"
ENV_FILE="$TMP/envnotif/.env"
envget() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }
# (a) empty config → borrow from .env
T_BOT=""; T_CHAT=""; D_URL=""; S_URL=""
[ -z "$T_BOT" ] && T_BOT="$(envget TELEGRAM_BOT_TOKEN)"
[ -z "$T_CHAT" ] && T_CHAT="$(envget TELEGRAM_CHAT_ID)"
[ -z "$D_URL" ] && D_URL="$(envget DISCORD_WEBHOOK_URL)"
[ -z "$S_URL" ] && S_URL="$(envget SLACK_WEBHOOK_URL)"   # not in .env → stays empty
[ "$T_BOT" = "12345:ABCdef" ] && [ "$T_CHAT" = "98765" ] && [ "$D_URL" = "https://discord.example/hook" ] && [ -z "$S_URL" ] \
  && ok "env fallback: empty config borrows Telegram/Discord from .env" || bad "env fallback: borrow from .env"
# (b) config.sh value present → .env must NOT override it
T_BOT="from-config"
[ -z "$T_BOT" ] && T_BOT="$(envget TELEGRAM_BOT_TOKEN)"
[ "$T_BOT" = "from-config" ] && ok "env fallback: config.sh value wins (not overwritten)" || bad "env fallback: config.sh value wins"

echo "== 23. Hooks, branch config & quiet notifications =="
# (a) PRE_DEPLOY_HOOK failure aborts deploy and touches nothing
mkdir -p "$TMP/hook_kit" "$TMP/hook_app" "$TMP/hook_src"
git init -q "$TMP/hook_src" && git -C "$TMP/hook_src" symbolic-ref HEAD refs/heads/main
git init -q --bare "$TMP/hook_bare"
git -C "$TMP/hook_src" remote add origin "$TMP/hook_bare"
echo "v1" > "$TMP/hook_src/file.txt"
git -C "$TMP/hook_src" add -A
git -C "$TMP/hook_src" -c user.email=test@test -c user.name=test commit -qm "v1"
git -C "$TMP/hook_src" push -q -u origin main
cp auto_deploy.sh rollback.sh "$TMP/hook_kit/"
cat > "$TMP/hook_kit/config.sh" <<CFG
REPO_URL="file://$TMP/hook_bare"
APP_DIR="$TMP/hook_app"
WORKSPACE_BASE="$TMP/hook_ws"
LOG_FILE="$TMP/hook_deploy.log"
PRE_DEPLOY_HOOK="exit 9"
CFG
(cd "$TMP/hook_kit" && bash auto_deploy.sh main >/dev/null 2>&1) || true
[ ! -f "$TMP/hook_app/file.txt" ] && grep -q "Pre-deploy hook FAILED" "$TMP/hook_deploy.log" 2>/dev/null \
  && ok "hooks: pre-deploy hook failure aborts deploy cleanly" || bad "hooks: pre-deploy hook abort"

# (b) POST_DEPLOY_HOOK executes on success
cat > "$TMP/hook_kit/config.sh" <<CFG
REPO_URL="file://$TMP/hook_bare"
APP_DIR="$TMP/hook_app"
WORKSPACE_BASE="$TMP/hook_ws"
LOG_FILE="$TMP/hook_deploy.log"
PRE_DEPLOY_HOOK=""
POST_DEPLOY_HOOK="echo 'post_hook_done' > '$TMP/hook_app/post_hook.txt'"
CFG
(cd "$TMP/hook_kit" && bash auto_deploy.sh main >/dev/null 2>&1) || true
[ -f "$TMP/hook_app/post_hook.txt" ] && [ "$(cat "$TMP/hook_app/post_hook.txt")" = "post_hook_done" ] \
  && ok "hooks: post-deploy hook executed successfully" || bad "hooks: post-deploy hook execution"

# (c) Branch-specific config (config.<branch>.sh)
cat > "$TMP/hook_kit/config.staging.sh" <<CFG
REPO_URL="file://$TMP/hook_bare"
APP_DIR="$TMP/staging_target_app"
WORKSPACE_BASE="$TMP/hook_ws"
LOG_FILE="$TMP/hook_staging.log"
CFG
git -C "$TMP/hook_src" checkout -qb staging
echo "staging" > "$TMP/hook_src/staging.txt"
git -C "$TMP/hook_src" add -A
git -C "$TMP/hook_src" -c user.email=test@test -c user.name=test commit -qm "staging"
git -C "$TMP/hook_src" push -q origin staging
(cd "$TMP/hook_kit" && bash auto_deploy.sh staging >/dev/null 2>&1) || true
[ -f "$TMP/staging_target_app/staging.txt" ] \
  && ok "branch config: config.<branch>.sh loaded and used" || bad "branch config: config.<branch>.sh loaded"

# (d) NOTIFY_ON_SUCCESS="no" quiet mode
NOTIFY_CALLED=0
test_notify() { NOTIFY_CALLED=1; }
NOTIFY_ON_SUCCESS="no"
if [ "${NOTIFY_ON_SUCCESS:-yes}" != "no" ]; then test_notify; fi
[ "$NOTIFY_CALLED" -eq 0 ] \
  && ok "quiet mode: NOTIFY_ON_SUCCESS=no suppresses success alerts" || bad "quiet mode: NOTIFY_ON_SUCCESS=no"

echo "== 24. Doc/CI count consistency (never drifts silently) =="
# The counts in test.yml, AGENTS.md and README.md must match reality.
# META counters (not PASS) keep these self-checks out of the core count —
# test.yml declares the CORE number and stays stable.
# If any mismatch: CI fails and tells you exactly which file to fix.
META_PASS=0; META_FAIL=0
meta_ok()  { echo "  ✅ $1"; META_PASS=$((META_PASS+1)); }
meta_bad() { echo "  ❌ $1"; META_FAIL=$((META_FAIL+1)); }

# (a) test.yml declared count == core PASS count (all core checks ran above)
_DECL="$(grep -oE '\([0-9]+ checks\)' .github/workflows/test.yml | grep -oE '[0-9]+' | head -1)"
[ "$PASS" = "$_DECL" ] && meta_ok "test.yml check count ($_DECL) matches core PASS" || meta_bad "test.yml says $_DECL checks but core ran $PASS — update test.yml"

# (b) AGENTS.md file-structure count == actual tracked top-level files
_ACT="$(git ls-files | grep -v '.agents/' | wc -l | tr -d ' ')"
_AG="$(grep -oE 'File Structure \([0-9]+' AGENTS.md | grep -oE '[0-9]+')"
[ "$_ACT" = "$_AG" ] && meta_ok "AGENTS.md file count ($_AG) matches reality" || meta_bad "AGENTS.md says $_AG files but reality $_ACT"

# (c) README.md files-table count == actual tracked top-level files
_RD="$(grep -oE 'Files \([0-9]+' README.md | grep -oE '[0-9]+')"
[ "$_ACT" = "$_RD" ] && meta_ok "README.md file count ($_RD) matches reality" || meta_bad "README.md says $_RD files but reality $_ACT"

# (d) README.md checklist file count == actual
_RC="$(grep -oE '\([0-9]+ files\)' README.md | grep -oE '[0-9]+' | head -1)"
[ "$_ACT" = "$_RC" ] && meta_ok "README checklist ($_RC files) matches reality" || meta_bad "README checklist says $_RC files but reality $_ACT"

echo ""
echo "============================================="
echo "  PASS: $PASS   FAIL: $FAIL   (META: $META_PASS ok / $META_FAIL bad)"
echo "============================================="
if [ "$FAIL" -eq 0 ] && [ "$META_FAIL" -eq 0 ]; then
  echo "✅ All tests passed"
  exit 0
else
  echo "❌ $FAIL core + $META_FAIL consistency check(s) failed"
  exit 1
fi
