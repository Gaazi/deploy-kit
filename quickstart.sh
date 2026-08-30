#!/bin/bash
# ============================================================
# DEPLOY KIT — quickstart.sh (1 command, everything)
# ------------------------------------------------------------
#   /bin/bash quickstart.sh
# RUN THIS ONE COMMAND — nothing else to read or remember.
# It does:
#   1. setup.sh      → creates config.sh (press Enter = recommended)
#   2. keygen.sh     → SSH keys + GitHub copy-paste blocks
#   3. detect.sh     → detects your project (APP_TYPE etc.)
#   4. test.sh       → verifies the kit itself
# Then just copy the workflow to GitHub + push. Done.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "═══════════════════════════════════════════════════"
echo "  DEPLOY KIT — Quickstart (1 command)"
echo "  * Press Enter — you get the recommended answer"
echo "  * No technical questions you don't understand"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Setup wizard → config.sh ──
echo "【1/4】 Setup (config.sh)"
echo "      Press Enter, paste required values"
echo ""
/bin/bash setup.sh || { echo "❌ setup.sh failed"; exit 1; }

# ── 2. SSH keys + GitHub copy-paste ──
echo ""
echo "【2/4】 SSH keys + GitHub copy-paste"
echo ""
/bin/bash keygen.sh || { echo "⚠️ keygen.sh skipped/failed"; }

# ── 3. Auto-detect project ──
echo ""
echo "【3/4】 Auto-detect your project (fully dynamic)"
echo ""
/bin/bash detect.sh <<< "y" 2>/dev/null || /bin/bash detect.sh

# ── 4. Self-test ──
echo ""
echo "【4/4】 Kit self-test"
echo ""
/bin/bash test.sh

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ QUICKSTART COMPLETE"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  Only 2 steps left (2 min):"
echo ""
echo "  1. Copy the workflow into your GitHub repo:"
echo "     cp ~/deploy-kit/.github/workflows/deploy.yml.example"
echo "        .github/workflows/deploy.yml"
echo ""
echo "  2. Push → deploy happens automatically 🎉"
echo ""
echo "  Need more detail? Read README.md (optional)"
echo "═══════════════════════════════════════════════════"
