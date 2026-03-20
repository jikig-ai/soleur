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
