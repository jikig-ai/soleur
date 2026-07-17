---
title: "browser_evaluate(filename) writes only within Playwright MCP allowed roots — and a crashing browser forces the token into the transcript"
date: 2026-07-18
category: workflow-patterns
tags: [playwright-mcp, vendor-token-mint, credential-handling, browser-instability]
issue: 6635
pr: 6648
module: one-shot / work (vendor-token mint)
---

# Learning: Playwright `browser_evaluate(filename:…)` allowed-roots + token-transcript fallback under browser instability

## Problem

Minting a Read-scoped Better Stack API token during `/one-shot #6635`, the canonical hygiene rule
(extract vendor tokens via `browser_evaluate(filename:…)` from the FIRST attempt so the value never
enters the conversation transcript — `hr` vendor-token-extraction) hit two walls:

1. **`filename` rejected outside allowed roots.** The first single-shot mint evaluate wrote its result
   to the session scratchpad (`/tmp/claude-.../scratchpad/bs-readonly-token.json`) and was rejected:
   `File access denied: … is outside allowed roots. Allowed roots:
   /home/…/soleur/.playwright-mcp, /home/…/soleur`. **The evaluate function STILL RAN** (it clicked
   Create and polled) — so the token was minted, but its return value was discarded with the
   file-write error. Net effect: a real token created, value not captured.

2. **Browser context crashed every ~2–3 tool calls.** The known Wayland/Vulkan launch-instability
   (`Connection closed` -32000; `Target page, context or browser has been closed`) recurred ~4×
   despite the committed `--ozone-platform=x11 --disable-gpu` mitigation, so a clean second
   `browser_evaluate(filename)` recapture could not complete. Recovery was a `browser_snapshot`, which
   surfaced the token value into the transcript — the exact exposure the filename-first rule exists to
   avoid.

## Solution

- **`browser_evaluate(filename:…)` writes ONLY within the Playwright MCP allowed roots** — the repo
  root or `.playwright-mcp/` (both under the worktree). NOT `/tmp`, NOT the session scratchpad. Write
  token captures to `.playwright-mcp/<name>.json` (gitignored) and process them with a redaction-aware
  bash script (`python3 -c 'json.load...'` → pipe to `doppler secrets set` via stdin; never `cat`).
- **The mint side-effect fires before the filename write is validated.** If a filename-rejected
  evaluate performed a create/POST, the resource already exists — re-navigate and do an **idempotent**
  read (find-or-skip on the resource name) rather than blindly re-creating, to avoid duplicate tokens.
- **When the browser is too unstable to complete a filename-capture, a read-only/low-blast token is an
  acceptable transcript exposure** (`brand_survival_threshold: none`; the token can only `GET`).
  Store it in Doppler, remove the `.playwright-mcp/` snapshots, and note the transit. If a token were
  write-scoped or higher-blast, prefer revoke-and-remint via a clean filename-capture over accepting
  the transcript exposure.
- **Verify the mint's scope from the dashboard, not just a read success.** A `GET → 200` proves auth,
  not least-privilege (an r/w token GETs too). The Better Stack list row showed a `Read-only` badge
  next to the new token — that badge (the scope set at mint time by the dropdown) is the authoritative
  scope control.

## Key Insight

`browser_evaluate`'s `filename` is sandboxed to the Playwright MCP roots, and the evaluated function
runs **before** the write is validated — so a path mistake on a mint evaluate creates the resource but
loses its value. Use `.playwright-mcp/` for captures, make mint evaluates idempotent (find-or-create),
and accept that a crashing browser degrades the filename-first hygiene to a snapshot fallback whose
transcript exposure is tolerable only for low-blast (read-only) credentials.

## Session Errors

- **Playwright MCP `✘ Failed to connect` at session start.** Recovery: cleared stale
  `~/.cache/playwright-mcp-profile/Singleton*` locks + killed the orphaned `playwright-mcp` process;
  the operator reconnected via `/mcp`. **Prevention:** known recurring env flake (existing learnings);
  the profile-lock cleanup is the standard first step before a reconnect.
- **Browser context crashed on `browser_navigate` (~4×).** Recovery: re-navigate after each crash;
  collapse fill+create+capture into a single evaluate to minimize the crash window. **Prevention:**
  documented in `2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md`; the X11+disable-gpu
  mitigation reduces but does not eliminate the crashes — design mint flows to be resumable/idempotent.
- **`browser_evaluate(filename)` scratchpad path rejected "outside allowed roots".** Recovery: switched
  captures to `.playwright-mcp/`. **Prevention:** this learning — filename must be under the repo
  root / `.playwright-mcp/`.
- **Token value transited the transcript via `browser_snapshot`.** Recovery: stored in Doppler, removed
  `.playwright-mcp/` snapshots; acceptable for a read-only token. **Prevention:** filename-first from a
  stable browser; revoke-and-remint for higher-blast credentials.

## Tags
category: workflow-patterns
module: one-shot / work (vendor-token mint via Playwright MCP)
