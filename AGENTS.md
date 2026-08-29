# Project Agent Rules — Deploy Kit

> Shared project instructions for AI coding agents working on the Deploy Kit.
> This is a STANDALONE, public-ready project (currently private on GitHub).
> It must stay 100% generic — NO project-specific info, NO real secrets/data.

---

## What this project is

A lightweight, config-driven auto-deployment kit for any project (Python / Node / PHP / static / Docker) on shared hosting (cPanel) or VPS.

**Flow:** GitHub push → GitHub Actions trigger (~6s, fire-and-forget SSH) → server runs `auto_deploy.sh <branch>` → git fetch → rsync → [build] → [db backup] → [migrate] → [restart] → [health check] → [Telegram]. The `[ ]` steps are OPTIONAL — empty config = skipped.

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

---

## File Structure (8 files + .agents/)

| File | Purpose |
|------|---------|
| `auto_deploy.sh` | Main deploy script — git → rsync → optional steps → health → telegram |
| `rollback.sh` | Roll back to previous commit + optional DB restore |
| `setup.sh` | Beginner YES/NO setup wizard (Enter = recommended, creates config.sh) |
| `setup-quick.sh` | Paste setup (KEY=VALUE lines, Ctrl+D, no questions) |
| `keygen.sh` | SSH key helper — one key pair both ways + 3 copy-paste blocks for GitHub |
| `config.example.sh` | Settings template — copy to `config.sh` and fill |
| `.github/workflows/deploy.yml.example` | GitHub Actions trigger (fire-and-forget ~6s) |
| `README.md` | User guide (3 setup methods, config table, checklist) |
| `.gitignore` | Protects `config.sh` / secrets |
| `LICENSE` | MIT |

---

## 3 Setup Methods (keep all 3)

```bash
/bin/bash setup.sh          # Method A — interactive Q&A
/bin/bash setup-quick.sh    # Method B — paste KEY=VALUE lines, then Ctrl+D
cp config.example.sh config.sh && nano config.sh   # Method C — manual
```

---

## Sync Strategy (IMPORTANT)

The kit is a **100% standalone project** — no other project is tied to it.

1. **Standalone repo** `Gaazi/deploy-kit` (local: `/run/media/ghazi/Data/coding/projects/deploy-kit`, remote: `git@github.com:Gaazi/deploy-kit.git`, branch `main`)
2. **User's server** `~/deploy-kit/` (deployed files — user copies manually)

**After any change:** commit + push to `main`. That's it — nothing else to sync.

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
