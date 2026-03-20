---
title: "Playwright shared cache causes version coupling between independent tools"
date: 2026-03-20
category: dependency-management
tags: [playwright, agent-browser, browser-automation, dependency-management]
module: plugins/soleur/skills/agent-browser
---

# Learning: Playwright shared cache causes version coupling between independent tools

## Problem

When two tools share `~/.cache/ms-playwright/`, their Playwright versions must match exactly. Playwright's browser lookup is exact-match on revision number — no forward compatibility. If tool A installs `chromium-1208` and tool B expects `chromium-1200`, tool B fails with "Version mismatch."

## Context

`agent-browser@0.5.0` depended on `playwright-core@1.57.0` (expects revision 1200). The Playwright MCP plugin installed revision 1208 (Playwright 1.58.2). Only `chromium-1208/` existed in the cache, so agent-browser couldn't find a usable browser.

## Solution

Upgraded to `agent-browser@0.21.4`, which is a Rust native CLI using Chrome for Testing instead of Playwright's Chromium. It stores browsers in `~/.agent-browser/browsers/`, completely decoupling from the Playwright cache.

## Key Insight

1. Self-contained packages that use Chrome for Testing (like agent-browser 0.21.1+) eliminate shared-cache coupling entirely
2. Playwright's browser revision lookup is exact-match — there is no forward compatibility between revisions
3. When two tools depend on the same browser cache, upgrading either tool can break the other
4. Pin global npm installs to specific versions (`agent-browser@0.21.4`, not `@latest`)
5. On Linux, `agent-browser install --with-deps` may be needed for system library dependencies
6. The `--session` flag was renamed to `--session-name` in agent-browser 0.21.x — documentation must track CLI flag renames across major version jumps
7. When `npm install -g` fails with EACCES (no sudo), use `npm install --prefix ~/.local -g` — but ensure `~/.local/bin` is prepended (not appended) to PATH so it shadows system binaries
8. Plans that claim "no changes needed" for adjacent files are often wrong — review agents caught 6 missed references that the plan said were fine. Always grep comprehensively rather than trusting plan assertions

## Session Errors

1. `npm install -g` EACCES — resolved via `--prefix ~/.local`
2. PATH ordering: `~/.local/bin` appended instead of prepended, old binary shadowed new
3. Chrome sandbox failure on Linux — `--args "--no-sandbox"` needed
4. one-shot referenced wrong path for `setup-ralph-loop.sh`
5. Review found 6 unpinned install references the plan missed
6. `gh issue create --label "refactor"` failed (label doesn't exist)
