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
for f in auto_deploy.sh rollback.sh setup.sh setup-quick.sh; do
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
