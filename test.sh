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

echo "== 1. Syntax check (bash -n) =="
for f in auto_deploy.sh rollback.sh setup.sh setup-quick.sh keygen.sh cron.sh detect.sh runner.sh webhook.sh; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n $f"; else bad "bash -n $f"; fi
done

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
# compares size+mtime; two commits in the same second with same-size
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

echo ""
echo "============================================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "============================================="
if [ "$FAIL" -eq 0 ]; then
  echo "✅ All tests passed"
  exit 0
else
  echo "❌ $FAIL test(s) failed"
  exit 1
fi
