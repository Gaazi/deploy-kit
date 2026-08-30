#!/bin/bash
# ============================================================
# DEPLOY KIT — quickstart.sh (1 command, sab kuch)
# ------------------------------------------------------------
#   /bin/bash quickstart.sh
# SIRF YEHI EK COMMAND CHALAO — kuch aur padhna/yaad nahi.
# Yeh kar deta hai:
#   1. setup.sh      → config.sh banta hai (Enter dabao = recommended)
#   2. keygen.sh     → SSH keys + GitHub ke liye copy-paste blocks
#   3. detect.sh     → aapka project khud pehchanta hai (APP_TYPE etc.)
#   4. test.sh       → kit khud ko test karta hai
# Phir bas GitHub pe workflow copy + push karo. Done.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "═══════════════════════════════════════════════════"
echo "  DEPLOY KIT — Quickstart (1 command)"
echo "  * Enter dabate jao — recommended answer aa jata hai"
echo "  * Kuch technical nahi poochte jo aap na jante ho"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Setup wizard → config.sh ──
echo "【1/4】 Setup (config.sh)"
echo "      Enter dabate jao, zaroori values paste karo"
echo ""
/bin/bash setup.sh || { echo "❌ setup.sh failed"; exit 1; }

# ── 2. SSH keys + GitHub copy-paste ──
echo ""
echo "【2/4】 SSH keys + GitHub copy-paste"
echo ""
/bin/bash keygen.sh || { echo "⚠️ keygen.sh skipped/failed"; }

# ── 3. Auto-detect project ──
echo ""
echo "【3/4】 Auto-detect your project (bilkul dynamic)"
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
echo "  Ab sirf yeh 2 cheezein baqi hain (2 min):"
echo ""
echo "  1. GitHub repo mein workflow copy karo:"
echo "     cp ~/deploy-kit/.github/workflows/deploy.yml.example"
echo "        .github/workflows/deploy.yml"
echo ""
echo "  2. Push karo → deploy automatic 🎉"
echo ""
echo "  Zaroorat ho to yeh padho: README.md (optional)"
echo "═══════════════════════════════════════════════════"
