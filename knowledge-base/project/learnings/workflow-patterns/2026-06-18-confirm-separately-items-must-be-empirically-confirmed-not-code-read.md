---
title: "An issue's 'confirm separately' item must be EMPIRICALLY confirmed (run it), not reasoned away from a code-read — and a necessary-but-insufficient fix hides behind a broken verification path"
date: 2026-06-18
category: workflow-patterns
module: apps/web-platform/scripts/live-verify
tags: [live-verify, harness, plan-quality, verification, assertion-drift, e2e, 5501]
related: 2026-06-18-live-verify-harness-needs-the-same-wayland-launch-flags-as-mcp.md
---

# Learning: confirm "confirm-separately" items by running them; don't reason them away

## Problem

Issue #5501 ("synthetic principal's chat send does not persist → harness can never emit PASS")
listed three items; **item 3** explicitly said: *"Confirm separately whether the current app
still navigates to `/dashboard/chat/<uuid>` on a persisted send, or whether the harness's
`waitForURL` assertion also needs updating."* The #5501 plan's Research Reconciliation read the
code, concluded *"No harness change needed; the seed fix restores the persist→nav chain,"* and
shipped the binding fix alone.

That conclusion was **wrong**. The deployed app no longer navigates to `/dashboard/chat/<uuid>`
on a fresh send — since the #5391/#5436 rail-race fix it materializes the conversation **in
place** by dispatching `CONVERSATION_CREATED_EVENT` so the rail refetches (`chat-surface.tsx:373-402`;
`/dashboard/chat` redirects to `/new`; `onRealConversationId` navigates only in the KB-sidebar
surface). So the harness's `page.waitForURL(/\/dashboard\/chat\/<uuid>$/)` could **never** match
the current app and always timed out at `CANT-RUN:forURL`. The binding fix (#5501/#5502) was
**necessary but insufficient**: the harness still could not emit PASS.

This stayed hidden for two extra layers: the local harness first crashed (Wayland GPU — separate
fix #5511) and then timed out under a CPU throttle — both masked the real assertion bug until the
crash + throttle were cleared and the harness ran cleanly to the same `forURL` timeout every time.

## Solution

Fix the harness to assert what the app actually does: wait for the WS-connected Send button,
**poll the persisted `conversations` row** (authoritative, browser-independent) as the
materialization signal, derive the id from it (not the URL), and keep the rail-row assertion.
Verified 3/3 live `RESULT: PASS` against prod.

## Key Insight

1. **A "confirm separately" / "verify X" item in an issue is a RUN-IT instruction, not a
   reason-about-it one.** When the claim is about *live app behavior* (does it navigate? does the
   selector still match? does the endpoint return shape Y?), a code-read is a hypothesis — confirm
   it by executing the actual path. The #5501 plan's code-read reached the opposite of reality
   because the app's behavior had changed under it (#5391). Cheapest gate: if an item says
   "confirm whether the app still does X," the plan's Acceptance Criteria must include *running*
   the thing, not a prose reconciliation.

2. **"Necessary but insufficient" hides when the verification path itself is broken.** The binding
   fix was real and correct, but the only way to *observe* its success — the harness — had its own
   independent bug (stale assertion). A fix whose proof-of-success runs through a broken verifier
   looks unverifiable, not wrong. When a fix "can't be confirmed," suspect the verifier before
   concluding the fix failed: here the DB showed the binding live and a direct poll showed the
   conversation persisting — the `waitForURL` was the only thing failing.

3. **Layered failures mask the root one.** Crash (Wayland) → timeout (throttle) → stale assertion
   were three independent issues stacked on one symptom. Peel them in order and re-observe after
   each; don't assume the first cause you fix is the only one.

## Tags
category: workflow-patterns
module: apps/web-platform/scripts/live-verify
