---
title: "A grep-based assertion over a script body false-matches the script's OWN comments/header-inventory — anchor on the write construct"
date: 2026-06-17
category: test-failures
module: apps/web-platform/scripts
tags: [bash, static-grep-test, negative-assertion, seed-script, live-verify, false-positive]
issue: "#5501"
---

# Learning: grep assertions over a script body must anchor on the write construct, not the bare token

## Problem

Adding a `user_session_state` upsert to `seed-live-verify-user.sh` (#5501) plus
static-grep assertions in `seed-live-verify-user.test.sh` hit two false failures of
the SAME class — a grep that scans the whole script body matched the script's own
**comments / header-inventory**, not just the executable line it was meant to gate:

1. **Negative assertion tripped by an explanatory comment.** The test asserts the seed
   does NOT route the binding through the RPC: `! grep -qE '/rpc/set_current_workspace_id'`.
   The seed's GREEN run FAILed because a code comment said *"NOT `/rpc/set_current_workspace_id`:
   that RPC needs auth.uid()…"* — the literal in the comment satisfied the grep, so the
   negative assertion fired even though no `/rpc/` call existed.

2. **Write-order assertion tripped by the header-inventory comment.** The plan's literal
   AC3 verify command was `grep -n user_session_state … | head -1` and required the upsert
   line number to exceed the `workspace_members` lookup line. After the task ALSO required
   adding `user_session_state` to the script's header provisioned-state inventory (a comment
   near the top of the file), `head -1` returned the COMMENT line (~line 27) instead of the
   upsert call (~line 239) → the order check false-failed even though the real write order
   was correct.

## Solution

Anchor every grep-based assertion over a script body on the **actual write/call construct**,
not a bare token that also appears in prose:

- Order/presence checks → grep `rest/v1/<table>` (the REST call), not bare `<table>`.
  `grep -nE 'rest/v1/user_session_state'` matches only the curl line; the header comment
  says bare `user_session_state` and is correctly ignored.
- Negative "must-not-call" checks → keep the forbidden literal out of the script's own
  comments (reword to *"NOT the `set_current_workspace_id` RPC"* — no `/rpc/` prefix), OR
  scope the grep to non-comment lines. Rewording the comment is the cheaper, clearer fix.

Both the test's order check and the plan's AC3 command were anchored on `rest/v1/`; the
seed comment was reworded to drop the `/rpc/` literal. All assertions then passed (13/13).

## Key Insight

A static-grep test over a file is **not** scoped to executable lines — it sees the file's
own comments, header inventories, and documentation prose. The moment a task requires both
(a) a "must / must-not contain literal X" assertion AND (b) documenting X in a comment, the
two collide. Anchor the assertion on the syntactic construct that can only appear in real
code (a REST path, a function-call shape), and write forbidden-literal-avoiding comments.
This is the bash/seed-script analogue of the source-reading-regex-test guidance: assert the
narrowest construct that proves the behavior, never a bare identifier the file also narrates.

## Session Errors

- **Negative-grep matched the seed's own comment** — Recovery: reworded the comment to avoid
  the `/rpc/set_current_workspace_id` literal. **Prevention:** anchor negative assertions on a
  construct only real code carries, or keep the forbidden literal out of comments.
- **Bare `user_session_state` grep matched the header-inventory comment** — Recovery: anchored
  the plan's AC3 verify command (and the test's order check) on `rest/v1/user_session_state`.
  **Prevention:** the same anchoring rule; never `grep | head -1` a bare token that the file
  also documents in prose.
- **Ad-hoc AC-sweep path typo** (`$SEED.test.sh` → `…sh.test.sh`) produced a false AC5 FAIL —
  Recovery: used the real `seed-live-verify-user.test.sh` path. **Prevention:** one-off; run
  the real test file directly rather than constructing its name by suffixing the script path.
- **(Forwarded) plan-phase write-boundary hook block** on a quoted `doppler secrets set`
  substring — Recovery: reworded prose + `iac-routing-ack`. **Prevention:** one-off; quote
  secret-mutation commands as prose, not verbatim, in plan bodies.

## Tags
category: test-failures
module: apps/web-platform/scripts
