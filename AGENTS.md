# Project Agent Rules — Deploy Kit

> Shared project instructions for AI coding agents working on the Deploy Kit.
> This is a STANDALONE, public-ready project (currently private on GitHub).
> It must stay 100% generic — NO project-specific info, NO real secrets/data.

---

## What this project is

A lightweight, config-driven auto-deployment kit for any project (Python / Node / PHP / WordPress / Ruby / Java / Go / static / Docker) on shared hosting (cPanel) or VPS.

**Flow:** GitHub push → GitHub Actions trigger (~6s, fire-and-forget SSH) → server runs `auto_deploy.sh <branch>` → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → [health check] → [Telegram]. The `[ ]` steps are OPTIONAL — empty config = skipped.

**Resource principle:** Runner does ONLY the trigger (~6s). All deploy work (fetch, rsync, build, backup, migrate, restart, health, Telegram) happens on the server. Nothing else runs on the runner — no checkout, no build, no migrate. Minimum resource, maximum efficiency.

---

## Where rules live

- **`AGENTS.md`** — core project rules (this file). Auto-loaded.
- **`.agents/MEMORY.md`** — project knowledge index. Grep, never read whole file.
- **`.agents/reference_config.md`** — every config key explained (read on demand).
- **`.agents/reference_deploy_flow.md`** — deploy flow, toggle, rollback, troubleshooting (read on demand).
- **`README.md`** — user-facing guide (setup, config table, checklist).

---

## User

- Speaks Roman Urdu — respond in Roman Urdu
- Wants practical, direct answers — no long explanations
- **All docs and files in this project: SIMPLE ENGLISH** (user request — the whole kit is English)
- Code comments in English are fine

---

## Golden Rules (CRITICAL — never violate)

1. **100% GENERIC** — this kit can become PUBLIC anytime. Never add:
   - Any real project's data, domains, usernames, DB names
   - Real secrets, tokens, keys, passwords (only placeholders in examples)
2. **`config.sh` NEVER committed** — `.gitignore` has it. Secrets live only on the server.
3. **Everything OPTIONAL** — only `REPO_URL` + `APP_DIR` are required. Backup, build, migrate, restart, health check, Telegram, toggle — all optional; empty config = skip, never crash.
4. **No heavy dependencies** — pure bash + git + rsync + curl. No Docker requirement, no daemon, no root. Must work on shared hosting.
5. **Extend, don't rewrite** — keep existing scripts compatible (setup.sh, setup-quick.sh, config.example.sh).
6. **Test before commit** — `bash -n` every script, and run a quick smoke test if logic changed.
7. **ZERO PROJECT REFERENCES — EVERYWHERE, ALWAYS.** This kit is public. Any specific real project (a user's app, a deployment target) must NEVER be named in: files, README/docs, `.agents/` (MEMORY/references), commit message subjects OR bodies, branch names, or anywhere in git history. The history has already been rewritten once — any new reference forces another filter-branch rewrite + force push (disruptive). **Before every commit, run:**
   ```bash
   grep -rniE 'dms|esabaq|darul|ilm\.|lqp|learn quran|learn_quran' --include='*.sh' --include='*.md' --include='*.yml*' --include='*.example' . | grep -v '.git/' | grep -v 'AGENTS.md' && echo "STOP — references found"
   git log --format='%s%n%b' | grep -iE 'dms|esabaq|darul|ilm\.|lqp|learn quran|learn_quran' && echo "STOP — history refs found"
   ```
   If anything prints, FIX IT before committing. When describing a lesson learned from a real deployment, write generic phrases only ("a real deployment", "one user's server") — never the project name. The grep pattern itself lives in the rule as a self-check; it's not a project reference.

---

## Resource Principle (kept in mind — MAIN GOAL)

**Main goal: server + GitHub resource = minimum, so free limits never run out.**

- **Runner does ONLY the trigger** (~6s SSH, or 0 with webhook/cron). All deploy work (fetch, rsync, build, backup, migrate, restart, health, Telegram) runs on the server via `auto_deploy.sh`. Never add deploy logic to the workflow — it belongs in `auto_deploy.sh` (or `rollback.sh`).
- **GitHub resource budget:** hosted Actions = ~1 min/deploy (VM boot + 6s job). Zero-cost options: native webhook (0 runner), cron (`cron.sh`), self-hosted runner (`runner.sh`). Doc-only pushes skip the workflow entirely (`paths-ignore`).
- **Server resource budget:** `--single-branch` clone (min network/disk), SHA-skip (idle = instant), log rotation (1MB), `DB_BACKUP_KEEP` (configurable), deploy lock (no duplicate runs), optional steps only when configured.
- **CI catches breaks**: the kit's own `.github/workflows/test.yml` runs `test.sh` on every push to `main` — a broken test = red CI.

---

## Common Change → What to Touch

When you modify the kit, this table tells you which files to update. Anything not listed → at least run `test.sh`.

| If you change... | Also update these |
|---|---|
| **A config key** | `config.example.sh` (default + comment) + `setup.sh` heredoc + `setup-quick.sh` heredoc + `README.md` config table + `.agents/reference_config.md` |
| **A script** (auto_deploy/rollback/detect/cron/runner/webhook) | Run `test.sh` — it covers syntax + integration |
| **setup.sh / setup-quick.sh** | `config.example.sh` (keys must match) + `README.md` (setup methods) |
| **keygen.sh** | Verify `--single-branch` not broken; test.sh covers keygen |
| **Workflow YAML** (`.github/workflows/*.yml`) | Update the corresponding `.example` file + `.agents/reference_deploy_flow.md` |
| **README.md** | `AGENTS.md` file structure + `README.md` files table (keep file counts in sync) |
| **Behavior / flow** | `.agents/reference_deploy_flow.md` + `.agents/MEMORY.md` (history) |
| **test.sh** | `.github/workflows/test.yml` (CI job name mentions check count) + `.agents/MEMORY.md` (self-test section) |

**After ANY change:** `bash -n` every script → `test.sh` → commit + push to `main`.

---

## File Structure (23 files + .agents/)

| File | Purpose |
|------|---------|
| `quickstart.sh` | **1 command — everything** (setup + keygen + detect + test) |
| `auto_deploy.sh` | Main deploy script — git → rsync → optional steps → health → notifications |
| `rollback.sh` | Roll back to previous commit + optional DB restore |
| `doctor.sh` | **Preflight check** — diagnose server environment, config, tools, and permissions |
| `setup.sh` | Beginner YES/NO setup wizard (Enter = recommended, creates config.sh, auto-runs keygen.sh at end) |
| `setup-quick.sh` | Paste setup (KEY=VALUE lines, Ctrl+D, no questions) |
| `keygen.sh` | SSH key helper — one key pair both ways + 3 copy-paste blocks for GitHub |
| `detect.sh` | **Fully dynamic** — reads your repo, auto-detects APP_TYPE/BUILD/MIGRATE/RESTART |
| `cron.sh` | **Zero GitHub Actions** — install cron job, deploy every N min, 0 Actions minutes |
| `runner.sh` | **~6s deploys (VPS)** — install a self-hosted GitHub runner: no VM boot, 0 Actions minutes |
| `webhook.sh` | **~1-2s deploys (VPS)** — socat HTTP listener: GitHub POST → auto_deploy.sh, secret-verified |
| `test.sh` | Self-test — bash -n + missing-config errors + full local file:// integration test (deploy → skip → rollback) |
| `config.example.sh` | Settings template — copy to `config.sh` and fill |
| `.github/workflows/deploy.yml.example` | GitHub Actions trigger (hosted runner, ~1 min; bootstraps kit on server if missing) |
| `.github/workflows/deploy-selfhosted.yml.example` | GitHub Actions trigger (self-hosted runner, ~6s) |
| `.github/workflows/deploy-webhook.yml.example` | GitHub Actions trigger (webhook, ~1-2s) |
| `.github/workflows/test.yml` | CI self-test (runs test.sh on push/PR) |
| `README.md` | User guide (quickstart + 3 setup methods, config table, checklist) |
| `.gitignore` | Protects `config.sh` / secrets |
| `.htaccess` | Denies web access if kit is inside the app dir (protects config.sh) |
| `opencode.json` | Editor/tool config for coding agents |
| `AGENTS.md` | Project agent rules (this file) |
| `LICENSE` | MIT |

---

## Setup Methods (keep all 3)

```bash
/bin/bash setup.sh          # Method A — beginner YES/NO wizard (recommended)
/bin/bash setup-quick.sh    # Method B — paste KEY=VALUE lines, then Ctrl+D
cp config.example.sh config.sh && nano config.sh   # Method C — manual
```

---

## Sync Strategy (IMPORTANT)

The kit is a **100% standalone project** — no other project is tied to it.

1. **Work in `dev` branch** — all development, fixes, improvements happen here.
2. **Push `dev`** any time — that's always fine.
3. **NO AUTO-MERGE to `main`** — merging to `main` is user territory. Only merge when the user explicitly says "merge karo" or "merge and push". Never promote dev→demo→main on my own.
4. **User's server** `~/deploy-kit/` — deployed files, user copies manually.

---

## Git Rules

- Push directly to `main` (it IS the main).
- Keep the repo public-ready: no real data, no secrets.

---

## Context Lookup

1. Grep `.agents/MEMORY.md` for project history/decisions.
2. Read `.agents/reference_config.md` for config keys.
3. Read `.agents/reference_deploy_flow.md` for flow/toggle/rollback.
4. Inspect the actual script as last resort.

---

## After ANY Change (MANDATORY)

- Update `.agents/MEMORY.md` if the change is non-obvious/expensive to rediscover.
- Update relevant reference file if a behavior changed.
- Re-run `bash -n` on all scripts (and `test.sh` if logic changed).
- Commit + push to `main`.
