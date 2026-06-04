---
title: "cc-soleur-go ToolStatusChip e2e: drive the real routing chip, and the harness caps the chat column at ~265px"
date: 2026-06-03
category: test-failures
module: apps/web-platform/components/chat
tags: [playwright, e2e, cc-soleur-go, message-bubble, tool-status-chip, harness-fidelity, layout]
related_pr: 4866
related_issues: [4852]
---

# Learning: the Concierge ToolStatusChip is NOT rendered by a `tool_use` stream event, and the offline e2e harness can't show a wide chat column

## Problem

Fixing the Concierge status-box overflow (`ToolStatusChip` label "Routing to the
right experts..." spilling past the card's right border — the inverse of #4852's
bare `whitespace-nowrap`). The CSS fix (`whitespace-nowrap` →
`min-w-0 [overflow-wrap:anywhere]`, message-bubble.tsx:27) was trivial and
vitest-green. The Playwright e2e proof is where the time went — two wrong
premises, each caught only by actually running the test.

## Root causes (two distinct e2e premises that were wrong)

### 1. A `tool_use` StreamEvent renders the lifecycle chip, NOT the ToolStatusChip

In `e2e/cc-soleur-go-bubbles.e2e.ts`, the first test did:

```ts
injector.send({ type: "tool_use", leaderId: "cc_router", label: LONG_LABEL });
const chip = page.locator('[data-testid="tool-status-chip"]'); // never appears
```

A `tool_use` stream event creates a **lifecycle tool chip** (`[data-tool-chip-id^="cc_router-…"]`,
the existing tests assert on that), which is a DIFFERENT element from
`ToolStatusChip` (`data-testid="tool-status-chip"`). The actually-overflowing
`ToolStatusChip` renders only via:

- the `isClassifying` **routing chip** at `chat-surface.tsx:737-755`
  (`MessageBubble role=assistant messageState="tool_use" toolLabel="Routing to
  the right experts..."`, wrapper `data-testid="routing-chip"`, FIXED label), or
- a general assistant message in `messageState="tool_use"` with an arbitrary
  `toolLabel`.

`isClassifying` (`chat-surface.tsx:456-462`) = `hasUserMessage &&
!hasAssistantMessage && routeSource === null && workflow.state === "idle" &&
!historyLoading && resumedFrom === null`.

### 2. The input is disabled offline; seed history instead

Driving the chip via `getByPlaceholder(...)` + "Send message" failed: the
ChatInput is `disabled={status !== "connected"}` and the offline mock-WS harness
never reports `status === "connected"` (textbox renders "Reconnecting...").
**But the routing chip does NOT depend on connection status** — only on reducer
state. The deterministic trigger is to seed the mount-time history fetch
(`/api/conversations/:id/messages`, ws-client.ts:1041) with a single USER
message:

```ts
await page.route("**/api/conversations/*/messages", (route) =>
  route.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ messages: [{ id: "u1", role: "user",
      content: "…", leader_id: null }], totalCostUsd: 0 }) }));
// then bootChat(page) → isClassifying fires on mount → routing chip renders.
```

`workflow.state` stays `"idle"` (only a `workflow_started` event activates it —
the mock conversation's `active_workflow: "cc-router"` is NOT hydrated into it),
so `isClassifying` is true.

### 3. The harness caps the chat column at ~265px (behavioral single-line is unprovable)

Diagnostics at a 1280px viewport: `rowParentClientWidth=265`, `rowClientWidth=212`
(`max-w-[90%]`), `cardClientWidth=168`, label single-line width ~210px. The
dashboard chat column renders at ~265px **regardless of browser viewport**, so
the routing chip card never gets the ~210px it needs to show the fixed label on
one line — it ALWAYS wraps here. The #4852 "single-line when horizontal space is
available" non-regression therefore **cannot be exhibited at the Playwright
layer** (production columns are far wider). This is the same class as
constitution line 312 (jsdom returns 0 for layout): some properties are
structurally unrenderable in the harness and must be pinned elsewhere.

`w-fit` on the card (plan Option B) did NOT help — the binding constraint is the
265px row, not the card's intrinsic sizing — so it was reverted; clean Option A
(label `[overflow-wrap:anywhere]`) is the whole fix.

## Solution

- Drive the **real** routing chip via seeded history (not a synthetic event, not
  the disabled input). Anchor measurement on `data-testid="message-bubble-card"`
  (added to the card), not a generic `.rounded-xl` utility class.
- Assert the provable invariant (**no horizontal overflow**) at default + narrow
  viewports, with a non-vacuity guard that the label **actually wrapped** (≥2
  line-boxes) — the exact state pre-fix `nowrap` spilled in. RED-verified: both
  fail against `nowrap`, pass against the fix.
- Pin the "single-line when space available" #4852 non-regression **structurally**
  via the vitest className assertion (`[overflow-wrap:anywhere]` present,
  `whitespace-nowrap` absent) — `overflow-wrap: anywhere` introduces a soft-wrap
  opportunity ONLY on overflow by CSS definition, so it cannot force a premature
  break when the line fits.

## Key Insight

For cc-soleur-go bubble e2e: **match the StreamEvent/state to the exact element
you're asserting on** — `tool_use` events → lifecycle `data-tool-chip-id` chips;
the `ToolStatusChip` needs the `isClassifying` routing-chip state (seed one user
message in the history mock, no WS "connected" needed). And know the harness's
structural limits: the offline dashboard chat column is ~265px regardless of
viewport, so width-dependent *behavioral* assertions belong in vitest className
checks, not Playwright. A green CSS-className unit test does not prove the layout;
only running the real component in real Chromium does — and the QA phase, not the
review phase, is what caught the wrong-element test.

## Session Errors

1. **e2e test asserted on `data-testid="tool-status-chip"` but injected a
   `tool_use` event** (renders the lifecycle `data-tool-chip-id` chip instead) —
   element never appeared; 3 tests failed at `toBeVisible`. Recovery: traced the
   real render path (`isClassifying` routing chip) and rewrote the test.
   **Prevention:** when writing a bubble e2e, grep the component for the
   `data-testid`/`data-*` you assert on and confirm which StreamEvent/state path
   actually renders it before injecting events.
2. **Drove the chip via the chat input** — failed because ChatInput is disabled
   (`status !== "connected"`) in the offline harness. Recovery: seeded the
   history fetch with a user message. **Prevention:** the offline mock-WS harness
   never reaches "connected"; reducer-state-only UI (chips, bubbles) must be
   driven by injected frames or seeded history, never by input interaction.
3. **"single-line at desktop" assertion failed** — harness caps the chat column
   at ~265px regardless of viewport. Recovery: dropped the unprovable behavioral
   assertion, pinned the non-regression via vitest className. **Prevention:**
   before asserting a width-dependent behavior in this harness, measure the
   actual container width — it does not track the browser viewport.
4. **tsc false error in `.next/types/app/(dashboard)/layout.ts`** (unrelated
   `PaymentWarningBanner`) after the Playwright dev build regenerated `.next`.
   Recovery: `rm -rf .next/types && tsc --noEmit` → clean. **Prevention:** a
   stale/regenerated `.next/types` can introduce generated-type errors unrelated
   to the diff; rebuild `.next/types` before treating a Next.js tsc error in a
   `.next/types/**` path as real.
5. **(forwarded from session-state.md)** plan Write blocked by bare-root guard
   (re-wrote to worktree path); Task tool unavailable in planning env (inline
   fan-out). Already recovered in the planning phase.

## Tags
category: test-failures
module: apps/web-platform/components/chat
