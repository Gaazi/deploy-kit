#!/bin/bash
# ============================================================
# DEPLOY KIT — runner.sh (self-hosted GitHub Actions runner)
# ------------------------------------------------------------
#   /bin/bash runner.sh
# Installs a GitHub SELF-HOSTED runner on THIS server (VPS only).
# → NO VM boot → each deploy's GitHub run finishes in ~5-6s.
# Pair with: .github/workflows/deploy-selfhosted.yml.example
#
# ⚠️  VPS ONLY (needs systemd). NOT for shared hosting.
#     Install it as the SAME user that has ~/deploy-kit/.
# ============================================================

echo "═ Deploy Kit — self-hosted runner installer ═"
echo "⚠️  VPS only (needs systemd). Not for shared hosting."
echo ""

# ── 0. prereqs ──
for c in curl tar; do
  command -v "$c" >/dev/null || { echo "❌ missing command: $c"; exit 1; }
done

# ── 1. repo + token (user pastes from GitHub UI) ──
read -rp "GitHub username: " GH_USER
read -rp "GitHub repo name: " GH_REPO
if [ -z "$GH_USER" ] || [ -z "$GH_REPO" ]; then
  echo "❌ username and repo are required"; exit 1
fi
echo ""
echo "Get the token: GitHub → your repo → Settings → Actions → Runners →"
echo "  'New self-hosted runner' → copy the --token value"
read -rp "Registration token: " TOKEN
if [ -z "$TOKEN" ]; then
  echo "❌ token is required"; exit 1
fi

# ── 2. arch + download latest runner ──
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)           RUNNER_ARCH="x64" ;;
  aarch64|arm64)    RUNNER_ARCH="arm64" ;;
  *) echo "❌ unsupported arch: $ARCH"; exit 1 ;;
esac
echo "📦 Arch: $RUNNER_ARCH — downloading latest runner..."
LATEST="$(curl -s https://api.github.com/repos/actions/runner/releases/latest \
  | grep -oP '"tag_name":\s*"v\K[^"]+' | head -1)"
if [ -z "$LATEST" ]; then
  echo "❌ could not get the latest runner version (network?)"; exit 1
fi
RUNNER_DIR="$HOME/actions-runner"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
curl -sL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${LATEST}/actions-runner-linux-${RUNNER_ARCH}-${LATEST}.tar.gz"
tar xzf runner.tar.gz
rm -f runner.tar.gz

# ── 3. register ──
echo "🔗 Registering runner..."
./config.sh --url "https://github.com/$GH_USER/$GH_REPO" \
  --token "$TOKEN" --unattended --replace >/dev/null

# ── 4. install as a service ──
echo "🚀 Installing as a service..."
(sudo ./svc.sh install >/dev/null 2>&1 || ./svc.sh install >/dev/null 2>&1)
(sudo ./svc.sh start >/dev/null 2>&1 || ./svc.sh start >/dev/null 2>&1)

echo ""
echo "✅ Self-hosted runner installed + running ($RUNNER_DIR)"
echo ""
echo "Next steps:"
echo "  1. In your repo: cp ~/deploy-kit/.github/workflows/deploy-selfhosted.yml.example"
echo "     .github/workflows/deploy-selfhosted.yml  (edit branch names)"
echo "  2. Runner shows green: GitHub → repo → Settings → Actions → Runners"
echo "  3. Push → deploy runs in ~5-6s (no VM boot, no Actions minutes used)"
echo ""
echo "Remove later:  $RUNNER_DIR/svc.sh stop && ./svc.sh uninstall"
