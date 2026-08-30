#!/bin/bash
# ============================================================
# DEPLOY KIT — keygen.sh (SSH key helper + GitHub copy-paste)
# ------------------------------------------------------------
#   /bin/bash keygen.sh
# Run on the server. Creates/reuses ONE SSH key pair that works
# BOTH ways:
#   server → GitHub : clone the repo (GitHub Deploy key)
#   GitHub → server : fire the deploy (Actions secret)
# Then prints 3 ready-to-copy blocks for GitHub (~2 minutes).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

KEY="${DEPLOY_KEY:-$HOME/.ssh/deploy_key}"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" 2>/dev/null

# ── 1. Create / reuse the key ────────────────────
if [ ! -f "$KEY" ]; then
  echo "🔑 Creating new SSH key (ed25519)..."
  if ! ssh-keygen -t ed25519 -f "$KEY" -N "" -C "deploy-kit" >/dev/null 2>&1; then
    echo "   ed25519 not supported here — falling back to RSA 4096"
    ssh-keygen -t rsa -b 4096 -f "$KEY" -N "" -C "deploy-kit" >/dev/null 2>&1
  fi
else
  echo "🔑 Using existing key: $KEY"
fi
chmod 600 "$KEY" 2>/dev/null

# ── 2. Set DEPLOY_KEY in config.sh ───────────────
if [ -f "$CONFIG_FILE" ]; then
  if grep -q "^DEPLOY_KEY=" "$CONFIG_FILE"; then
    sed -i "s|^DEPLOY_KEY=.*|DEPLOY_KEY=\"$KEY\"|" "$CONFIG_FILE"
  else
    echo "DEPLOY_KEY=\"$KEY\"" >> "$CONFIG_FILE"
  fi
  echo "✅ DEPLOY_KEY set in config.sh"
fi

# ── 3. Authorize GitHub Actions → server login ───
if grep -qF "$(cat "$KEY.pub" 2>/dev/null)" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
  echo "✅ Public key already authorized in ~/.ssh/authorized_keys"
else
  # ensure trailing newline so new key doesn't merge into last existing line
  if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
    tail -c1 "$HOME/.ssh/authorized_keys" | read -r _ || echo "" >> "$HOME/.ssh/authorized_keys"
  fi
  if cat "$KEY.pub" >> "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null
    echo "✅ Public key authorized in ~/.ssh/authorized_keys"
  else
    echo "⚠️  Could not write ~/.ssh/authorized_keys (shared hosting?)"
    echo "    → cPanel: SSH Access → Manage SSH Keys → Import this public key → Authorize"
  fi
fi

# ── 4. Copy-paste blocks for GitHub ──────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  COPY-PASTE FOR GITHUB — 3 steps, ~2 minutes"
echo "════════════════════════════════════════════════════════"
echo ""
echo "STEP 1 — GitHub → your repo → Settings → Deploy keys → Add deploy key"
echo "         Title: deploy-kit"
echo "         Key: (copy this ENTIRE line)"
echo ""
cat "$KEY.pub" 2>/dev/null
echo ""
echo "STEP 2 — GitHub → your repo → Settings → Secrets and variables → Actions"
echo "         → New repository secret"
echo "         Name: SSH_PRIVATE_KEY"
echo "         Value: (copy EVERYTHING, from -----BEGIN to -----END)"
echo ""
cat "$KEY" 2>/dev/null
echo ""
echo "STEP 3 — Same page → New repository secret (add these 3):"
echo "         SERVER_HOST = ${SERVER_HOST:-<your server host/IP>}"
echo "         SERVER_USER = ${SERVER_USER:-<your server username>}"
echo "         SSH_PORT    = ${SSH_PORT:-22}"
echo ""
echo "  Done! Now push a commit → GitHub Actions deploys automatically 🚀"
echo "  (Deploy keys are per-repo: for each NEW repo, repeat STEP 1 only.)"
