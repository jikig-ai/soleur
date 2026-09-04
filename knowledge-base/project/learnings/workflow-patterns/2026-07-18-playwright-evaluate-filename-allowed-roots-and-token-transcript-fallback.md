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

## Addendum — 2026-09-03 (#7772): check for a suffix-variant sibling BEFORE reaching for the browser

This learning is about minting a vendor token *through the browser*, and its recipe is sound. What it
does not say — and what cost a full work-stream's worth of deferral on #7772 — is that the browser may
not be needed at all, and that the reason it looked needed can be a **second credential sitting next
to the first**.

`BETTERSTACK_API_TOKEN` (write-capable) and `BETTERSTACK_API_TOKEN_READONLY` both live in Doppler
`soleur/prd_terraform`. #7772 and ADR-198 recorded a per-source Better Stack Logs token as blocked on
"a provider that does not exist here or an operator mint", and that classification stood for months.
Measured in seconds once someone actually probed:

    POST /api/v2/sources {}  under BETTERSTACK_API_TOKEN           -> 422 (missing attributes)
    POST /api/v2/sources {}  under BETTERSTACK_API_TOKEN_READONLY  -> 403

The write capability was already provisioned. No Playwright, no dashboard, no operator step, no
token-mint recursion. The read-scoped sibling is what made the capability look absent — and note the
failure was *not* a token behaving outside its documented scope, so there was nothing anomalous to
notice. It was a naming adjacency.

**The cheap probe, and why it beats the browser recipe below.** Before concluding a vendor capability
is unavailable, list the credential NAMES you hold for that vendor (`doppler secrets --only-names |
grep -i <vendor>`) and probe the capability under EACH one with a deliberately-invalid body. A `422`
means authorized-but-malformed; a `403` means the credential lacks the scope. That distinction is
available without creating anything, and it settles in one call what an a-priori classification gets
wrong. A `403` from ONE token is not evidence the capability is unreachable — it is evidence about
that token.

This composes with `2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable.md` rather than
replacing it: that learning says a dashboard action is presumptively automatable and the burden is on
the operator-only claim. This one adds a rung *below* the browser — exhaust the credentials you
already hold before you open one.

**Credential hygiene carries over unchanged, and one addition.** The API token goes on **stdin**
(`printf 'header = "Authorization: Bearer %s"\n' "$TOK" | curl -K -`), never argv, because
`/proc/<pid>/cmdline` is world-readable. New here: **never let an unfiltered API body reach stdout** —
Better Stack's `GET /sources` returns *every* source's ingest token, including the shared credential
four production consumers depend on, so a bare `curl` would have put it in a public job log. Pipe
every read through `jq` selecting named fields. And the Doppler write must be silenced *and*
redirected: the set verb prints all remaining secrets in the config on success, which for
`prd_terraform` is ~160 names.

**One trap the recipe below does not cover.** `doppler run -p soleur -c <config>` injects a
read-scoped service token as `DOPPLER_TOKEN`, and a nested Doppler *write* inherits it and fails with
"This token does not have access to requested config". Run the write outside the wrapper, or with
`env -u DOPPLER_TOKEN`, so it authenticates as the local CLI instead.

## Tags
category: workflow-patterns
module: one-shot / work (vendor-token mint via Playwright MCP)
