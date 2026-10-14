---
title: Pencil headless CLI install fails on hosts with a global libvips, and pen.dev .pen files trip the secret scanner
date: 2026-09-25
category: tooling
tags: [pencil, pen.dev, sharp, libvips, gitleaks, ux-design-lead, wireframe-gate]
symptoms: [npm i -g @pen.dev/cli fails with sharp build error, gitleaks-staged blocks .pen commits with generic-api-key on fileToken]
module: System
component: tooling
problem_type: workflow_issue
resolution_type: workflow_improvement
root_cause: environment_specific
severity: medium
---

# Pencil headless CLI: two environment landmines that block the mandatory wireframe path

## Problem

The `wg-ui-feature-requires-pen-wireframe` gate makes `.pen` wireframes mandatory for UI features. On a host with (a) a system libvips and (b) a very new Node, the documented `check_deps.sh --auto` install path fails three different ways before a `.pen` can be authored.

## Root cause

1. **sharp source-build:** `sharp@0.34.5`'s `install/check.js` calls `useGlobalLibvips()`; on this host `pkg-config --modversion vips` answers 8.18.6 (`/usr/bin/vips` ships with Omarchy), so check.js exits 1 and npm falls back to `node-gyp`, which fails (no node-addon-api/headers). This fires on Node 22 AND Node 26 — it is NOT an ABI/prebuild problem. Fix: `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm i -g @pen.dev/cli` forces the prebuilt path. Also note `@pencil.dev/cli` is deprecated → install `@pen.dev/cli` (binaries `pen`/`pencil`), auth via `PEN_CLI_KEY` (renamed from `PENCIL_CLI_KEY`; same Doppler `soleur/dev` secret works).
2. **gitleaks `fileToken`:** pen.dev CLI 0.3.x `.pen` files embed `"fileToken": "<uuid>"` (a cloud-sync document ID absent from the older 2.11-format files already in repo). `generic-api-key` flags it. The repo-shape inline waiver comment is impossible — JSON has no comments. Fix used: `.gitleaksignore` with per-file `<path>:generic-api-key:<line>` fingerprints. Every *new* `.pen` file will re-trip this; a durable fix (scoped `.gitleaks.toml` waiver or stripping `fileToken` before commit) is filed separately.
3. **Agent exhaustion:** `pen --agent claude` hit the account's weekly limit mid-run, `--agent codex` was rate-limited, and the Doppler `GEMINI_API_KEY` was invalid. The `pen interactive` shell (deterministic `execute`/`Insert`/`save`/`Export` ops — no LLM) is the working fallback; ux-design-lead authored all 3 variants through it.

## Solution

```bash
export PATH="$HOME/.local/share/mise/installs/node/22.12.0/bin:$PATH"
export PEN_CLI_KEY="$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain)"
SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm i -g @pen.dev/cli
pen --out <file.pen> --prompt "..."   # or: pen interactive  (LLM-free fallback)
```

Before committing `.pen` files: `gitleaks git --staged --verbose`; add `fileToken` fingerprints to `.gitleaksignore`.

## Session Errors

1. **`gh issue create --body-file` rejected 4×.** The filing gate reads the file at PreToolUse, so (a) a rejected compound command runs nothing — the `mv` producing the file never executed, and (b) relative paths resolve against the hook's CWD, not the shell's. **Prevention:** write the body file in a dedicated step under a plain (non-dotfile) name, then invoke `gh` with the absolute path; expect the `User-Impact:`/`Fix-Size:` or `Mandated-By:` justification on every `gh issue create`, not just deferrals.
2. **Lethook rejection buried in truncated output.** `git commit && git push` printed "Everything up-to-date" after the commit was actually blocked by `gitleaks-staged` — the push was a no-op over an uncommitted tree. **Prevention:** after any `commit && push` chain, verify `git log --oneline -1` before trusting the push line.
3. **`rg --type tsx` invalid.** **Prevention:** use `-g '*.tsx'` globs.

## Prevention

- `pencil-setup/scripts/check_deps.sh` should export `SHARP_IGNORE_GLOBAL_LIBVIPS=1` around the npm install (tracked as machinery issue — filed from this session).
- A durable `.pen`/`fileToken` waiver (scoped `.gitleaks.toml` allowlist, or stripping `fileToken` pre-commit in ux-design-lead) tracked as machinery issue.
