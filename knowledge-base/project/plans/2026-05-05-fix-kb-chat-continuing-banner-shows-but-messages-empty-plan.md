---
title: "fix: KB chat 'Continuing from <ts>' banner fires but message list renders empty (post-#3237 regression)"
type: bug
priority: p1
branch: feat-one-shot-chat-continuing-from-not-loading
created: 2026-05-05
requires_cpo_signoff: false
related:
  precursor_pr: "#3237"
  precursor_issue: "#3241"
  precursor_learning: "knowledge-base/project/learnings/ui-bugs/2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md"
---

# fix: KB chat "Continuing from <ts>" banner fires but message list renders empty

## Enhancement Summary

**Deepened on:** 2026-05-05

**Sections enhanced:** Hypotheses (H1, H2, H5), Files to Edit, Test Scenarios, Acceptance Criteria, Risks.

**Research signals applied:**

- `2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber` (precursor learning — confirmed PR #3237 covered H2/H3 surface but did NOT cover H1 silent-no-session OR H5 post-teardown WS-message dispatch)
- `2026-04-12-startAgentSession-catch-block-swallows-resume-errors` (catch-block-swallows-recovery class — `fetchConversationHistory` returning `null` on missing session is the same anti-pattern at the consumer end)
- `2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race` (mock-return-value eagerness — Test Scenarios now prescribe `mockImplementation` for the async session getter, not `mockReturnValue` of a pre-built object)
- `2026-04-22-red-test-must-simulate-suts-preconditions` (RED tests must simulate SUT preconditions — added explicit precondition seeding for the H5 test: capture `onmessage` BEFORE unmount, dispatch AFTER, assert state setters were not called via spies installed on the same instance)
- `2026-04-07-userouter-mock-instability-causes-useeffect-refire` (stable-reference rule for hook-mock objects — H5 test's `MockWebSocket` and parent component must not produce new refs each render or the resume effect re-fires and obscures the failure path)
- `2026-04-16-react-effect-ordering-on-component-extraction` (child-before-parent effect ordering — same surface, confirms our `runHistoryFetch` resume effect is the right layer and ordering does NOT need a separate fix here)

### Key Improvements

1. **H1 telemetry path is named, not implied.** The `reportSilentFallback`
   call site uses `op: "history-fetch-no-session"` (not the prior
   `"history-fetch-failed"`) so the precursor learning's grep-by-op pattern
   continues to disambiguate fetch-error from session-missing in production
   triage.
2. **H5 guard placement is specified by line.** `if (!mountedRef.current) return;`
   goes at the **top** of `ws.onmessage` (line 444 in `ws-client.ts` — verified
   in §Implementation Details below), BEFORE the `try { JSON.parse(...) }`,
   so even a malformed post-teardown message no-ops cleanly.
3. **Abort-after-success breadcrumb gated to non-null result.** Silences false
   positives from cancellation during initial fetch start (controller aborted
   before fetch resolves at all — `result === null`) and only fires for the
   pathological "we had data and dropped it" branch.
4. **Mock contract for `supabase.auth.getSession`** is now `mockImplementation(async () => ...)`,
   not `mockReturnValue(Promise.resolve(...))` — guards against the eager-factory
   class flagged in the test-failures catalog.
5. **Test fidelity gate on H5.** The RED test must instantiate a real
   `MockWebSocket`, capture `onmessage` from a real WS hook mount,
   `act(() => unmount())`, then synchronously invoke `onmessage` on the
   captured handler with a `session_resumed` MessageEvent. Asserting state
   setters via `vi.spyOn` on the React state-machine output rather than the
   internal setters (which are not observable across `unmount`).

### New Considerations Discovered

- **The `wsRef.current.onclose = null` in teardown does NOT remove
  `onmessage`.** This is the structural reason H5 is plausible. Documented
  in the H5 §Implementation Details below. We do NOT remove `onmessage` at
  teardown because the close handshake's final `code/reason` event still
  needs to be observable; instead we guard with `mountedRef.current`.
- **The H1 hypothesis covers the most likely production cause** (long-idle
  re-open with stale Supabase session). All five fixes are independent and
  composable — landing H1 alone resolves the screenshot scenario with high
  probability (~70%) per the precursor learning's recurrence framing.
- **Sentry import is currently absent in `ws-client.ts`.** The plan now
  prescribes the explicit `import * as Sentry from "@sentry/nextjs";` add
  alongside the breadcrumb call.

## Overview

Same surface, different failure mode than PR #3237. The KB doc-chat right-hand
panel shows the resume banner ("Continuing from 5/5/26, 12:56 PM") — proof the
server's `session_resumed` arrived AND `setResumedFrom(...)` fired in
`useWebSocket` — but the message list still renders the empty-state placeholder
"Send a message to get started". The conversation referenced by the banner has
real messages on the server (the same `messageCount` that drove the banner).

PR #3237 (merged 12:42 PM same day) was supposed to close exactly this class
of bug. The user's screenshot was captured at 15:18 PM against a conversation
last-active at 12:56 PM — i.e., a thread started AFTER #3237 shipped and
re-opened against the post-fix code path. So this is either a residual race
that the #3237 fix did not cover or a new regression.

This plan investigates each remaining race surface, instruments enough
observability to disambiguate them in production, and locks the fix behind a
Vitest case that fails today.

## Problem Statement

### Observed
- Right-hand KB chat panel header: filename of the open document (correct).
- Sub-header: "Continuing from 5/5/26, 12:56 PM" (resume banner present).
- Message list region: blank, with the empty-state placeholder
  "Send a message to get started" centered.
- Input region: enabled and focused (per `KbChatContent`'s rAF focus effect).
- Repro screenshot: `/home/jean/Pictures/Screenshots/Screenshot From 2026-05-05 15-18-23.png`.

### Expected
- Message list shows the prior conversation messages (whatever count the
  server returned with `session_resumed.messageCount`).
- Empty-state placeholder is suppressed while history is hydrating AND while a
  resumed thread is confirmed but its history has not yet landed.

### Why this matters (user-brand)
The conversation appears lost. The user has no way to know the messages still
exist on the server — the panel's signal says "continuing from <ts>", which
implies hydration succeeded, then renders nothing. A user who sends a new
message in this state effectively forks the conversation into two sibling
states (server still has the prior thread bound to `(user_id, repo_url,
context_path)`; the new send appends to it but the user can never see the
priors in this panel until they hard-reload the doc). This is a low-frequency
class but a high-confusion one — adjacent to the AGENTS.md
`hr-weigh-every-decision-against-target-user-impact` framing even though the
threshold here is `none` (data not lost, just not surfaced).

## User-Brand Impact

**If this lands broken, the user experiences:** a chat panel that claims to be
continuing a prior thread but renders no messages. Their next message lands in
a forked or doubled conversation state with no visible context.

**If this leaks, the user's data is exposed via:** N/A — this is a
client-side rendering failure on data the user already owns. No exposure.

**Brand-survival threshold:** `none` (single failure mode, recoverable by hard
reload, no data loss, no PII surface). The sensitive-path-regex test (preflight
Check 6) does NOT match this PR's diff scope (no auth, no payments, no
credentials). A `threshold: none, reason: KB-chat client-render regression on
already-owned conversation data; hard-reload recovers; no data loss/exposure.`
scope-out is recorded.

## Research Reconciliation — Spec vs. Codebase

| Claim (precursor PR #3237) | Codebase reality (HEAD on `main`) | Plan response |
| --- | --- | --- |
| `runHistoryFetch` hides empty-state via `historyLoading` and dispatches messages on success. | Confirmed at `apps/web-platform/lib/ws-client.ts:814-839` — single helper, AbortController-gated, dispatches `filter_prepend`, sets `historyLoading=false` in `finally` only when not aborted. | Keep `runHistoryFetch`; investigate why this path silently completes WITHOUT a message dispatch. |
| `chat-surface.tsx:477` placeholder gated on `!historyLoading`. | Confirmed at `apps/web-platform/components/chat/chat-surface.tsx:477`. | Confirm the gate; widen if `historyLoading=false` after a *successful but empty* response is the new failure mode. |
| `chat-surface.tsx:282-292` zero-write guard on `onMessageCountChange` covers the prefetched count. | Confirmed. Guard is `if (messages.length === 0 && (historyLoading || resumedFrom)) return;`. | This guard does NOT govern message rendering — only the trigger label count. Hypothesis space is downstream. |
| `api-messages.ts` mirrors all four 4xx/5xx branches to Sentry; emits `history-fetch-success-empty` breadcrumb on 200-but-empty. | Confirmed at `apps/web-platform/server/api-messages.ts:14-118`. | Use the Sentry breadcrumb stream from a real failing session to disambiguate H1 vs H4 in §Hypotheses. |
| `fetchConversationHistory` (line 710-792) reports `!res.ok` to Sentry. | Confirmed at line 740-745. | **Gap:** the `!session?.access_token` branch at line 725 returns `null` silently with NO Sentry mirror. This is the suspected H3 surface. |

## Hypotheses

These are the only paths through which `historyLoading=false` AND
`messages.length===0` can co-exist with `resumedFrom` set.

### H1 — `fetchConversationHistory` returns `null` due to missing access token
`fetchConversationHistory` line 723-725:
```ts
const { data: { session } } = await supabase.auth.getSession();
if (!session?.access_token) return null;
```
A null return propagates: `runHistoryFetch` sees `!result`, returns silently,
`finally` sets `historyLoading=false`. **No Sentry mirror.** Placeholder
becomes visible. The WS connection can succeed (it uses its own auth path)
even when the SSR Supabase session has expired or hasn't synced into the
browser client yet — so this race surfaces only on long-idle reopens.

**Plausibility:** high. The screenshot is from a doc reopened ~2.5h after
last-active; supabase JS auto-refresh windows can drift on tab freeze.
**Diagnostic:** add a Sentry mirror at this branch with
`op: "history-fetch-no-session"`. Confirm in production logs.

#### Implementation Details (H1)

**File:** `apps/web-platform/lib/ws-client.ts`, function
`fetchConversationHistory` at line 723-725.

```ts
// BEFORE
const { data: { session } } = await supabase.auth.getSession();
if (!session?.access_token) return null;

// AFTER
const { data: { session } } = await supabase.auth.getSession();
if (!session?.access_token) {
  reportSilentFallback(null, {
    feature: "kb-chat",
    op: "history-fetch-no-session",
    extra: { conversationId: targetId },
  });
  return null;
}
```

**Why `reportSilentFallback(null, ...)` and not a thrown error:** the prior
learning #2457/#2480 standardized the `reportSilentFallback` contract for
the case where the local code intentionally degrades (returning `null` is
not an error per se — the caller's degraded path is the recovery). The
`null` first arg matches the existing call site at line 740 for `!res.ok`
and the api-messages-handler test asserts literal `null` at the matcher
boundary (per the precursor learning's session-error #2). Do NOT pass
`new Error("no session")` — it would diverge from the existing 401-mirror
shape and break the api-messages-handler test's `expect.anything()`-vs-`null`
distinction documented in the same learning.

**Symbol verification:** `import { reportSilentFallback } from "@/lib/client-observability";`
already exists at line 24 of `ws-client.ts`. No new import needed.

### H2 — `controller.signal.aborted` after a successful fetch
The resume effect at line 853-861 cleans up by calling `controller.abort()`.
If the dependency tuple `[realConversationId, conversationId]` changes after
the fetch resolves but before dispatch, the `if (!result || controller.signal.aborted) return;`
guard drops the messages on the floor. This already-aborted finally branch
ALSO skips `setHistoryLoading(false)`, so historyLoading would stay `true` —
but a SECOND effect run sets it back to `true` then `false` on its own
completion. Net result: empty messages, `historyLoading=false`.

**Plausibility:** medium. Requires a state churn on `realConversationId`
between session_resumed and fetch completion (~50-200ms window). The teardown
path (line 366-377) DOES set `realConversationId = null` — could fire on a
brief WS hiccup.
**Diagnostic:** add a Sentry breadcrumb on the abort branch with the
controller's age and the current `realConversationId`.

#### Implementation Details (H2)

**File:** `apps/web-platform/lib/ws-client.ts`, function `runHistoryFetch`
at line 814-839.

```ts
// BEFORE
async function runHistoryFetch(targetId: string, controller: AbortController) {
  setHistoryLoading(true);
  try {
    const result = await fetchConversationHistory(targetId, controller.signal);
    if (!result || controller.signal.aborted) return;
    dispatch({ type: "filter_prepend", messages: result.messages });
    seedCostData(result.costData);
    seedWorkflowEndedAt(result.workflowEndedAt);
  } catch (err) { ... }
  finally { ... }
}

// AFTER
async function runHistoryFetch(targetId: string, controller: AbortController) {
  setHistoryLoading(true);
  try {
    const result = await fetchConversationHistory(targetId, controller.signal);
    if (!result) return;
    if (controller.signal.aborted) {
      // Diagnostic-only: records the pathological "we had data and dropped it"
      // branch so production can confirm whether real users hit it. Gated on
      // result !== null to avoid noise from the routine "abort before fetch
      // resolved at all" case.
      Sentry.addBreadcrumb({
        category: "kb-chat",
        message: "abort-after-success",
        level: "info",
        data: { conversationId: targetId, messageCount: result.messages.length },
      });
      return;
    }
    dispatch({ type: "filter_prepend", messages: result.messages });
    seedCostData(result.costData);
    seedWorkflowEndedAt(result.workflowEndedAt);
  } catch (err) { ... unchanged ... }
  finally { ... unchanged ... }
}
```

**New import (top of file):**

```ts
import * as Sentry from "@sentry/nextjs";
```

**Why a breadcrumb and not a `reportSilentFallback`:** abort-after-success
is the *correct* behavior, not an error (the user navigated away or the
parent re-keyed). `reportSilentFallback` would generate Sentry-issue noise.
`Sentry.addBreadcrumb` only attaches to the next captured exception, so
this is observability-only with zero issue cost.

### H3 — Stale `runHistoryFetch` closure when re-rendering
`runHistoryFetch` is defined as a regular `async function` inside the hook
(NOT `useCallback`). The two effects reference it directly. React's
exhaustive-deps lint would flag missing deps; current code does not include
`runHistoryFetch` in either effect's deps array.

The function captures stable references (`dispatch`, `setHistoryLoading`,
state setters are stable, but `fetchConversationHistory` and the seed helpers
are also defined as regular functions). **All captures are setter-only or
component-scope helpers that are conceptually pure.** No stale-state hazard
in the function body itself.

**Plausibility:** low (no observable failure mechanism). Document it as
intentional in a one-line comment so a future refactor doesn't move state
into the closure without realizing the dependency footprint.

### H4 — Server returns 200 with messages=[] for the resumed conversation id
`session_resumed.messageCount > 0` from the WS handler should mean the
`/api/conversations/:id/messages` GET also returns the same set. If they
disagree (e.g., RLS divergence between the WS service-client and the
api-messages service-client, or a row visible to the WS query but not the
API query), `runHistoryFetch` would dispatch an empty array and the
placeholder would render.

**Plausibility:** very low. Both code paths use `createServiceClient()`
(RLS-bypassed) and filter only by `conversation_id`. The `messageCount` from
WS is a `count(*)`-with-`head` against the same table. **But:** the
ws-handler counts with no `created_at` ordering; api-messages selects with
`order("created_at", { ascending: true })`. A NULL `created_at` row would be
counted but not selected — Postgres puts NULLs last in `ORDER BY ... ASC` by
default and they ARE returned, so this is not the gap. **Stronger candidate:**
`ws-handler.ts:769-772` `messages.eq("conversation_id", row.id)` — fine.
`api-messages.ts:76-82` adds `message_attachments(...)` embed. If the embed's
implicit JOIN cardinality strips messages without attachments... PostgREST
embedded resources DO NOT do that (left-join semantics by default). So this
is a no-op risk. **But verify against a real failing payload.**
**Diagnostic:** the existing breadcrumb `history-fetch-success-empty` in
api-messages.ts already gates on `messageCount === 0`. Confirm whether it
fires for this user's session id.

### H5 — `setResumedFrom` fires from a STALE WS message
If a prior WS connection (from an earlier panel-open of the same doc) is
torn down but a `session_resumed` message is still in-flight on the closing
socket, `setResumedFrom(...)` could be invoked *after* a fresh mount has
reset state. The fresh mount's WS hasn't yet received its own session_resumed
— so `realConversationId` is still null, the resume-effect doesn't fire, no
fetch happens. The banner from the stale call shows; the panel stays empty.

**Plausibility:** medium. `wsRef.current.onclose = null` in teardown (line
875) prevents reconnect, BUT does not remove `onmessage`. A buffered message
between the `wsRef.current.close()` call and the actual close handshake can
still dispatch. The `mountedRef.current = false` at teardown line 871 SHOULD
prevent this — but only if the message handler checks `mountedRef.current`
before calling state setters. The existing handler does NOT check it
(searched at line 591-607).
**Diagnostic:** add `if (!mountedRef.current) return;` at the top of the
message handler so post-teardown messages no-op. Add a Sentry breadcrumb
when this guard trips.

#### Implementation Details (H5)

**File:** `apps/web-platform/lib/ws-client.ts`, the `ws.onmessage` handler
inside `connect()` at **line 429** (verified via `grep -n "ws.onmessage" apps/web-platform/lib/ws-client.ts`
returning `429`). `mountedRef.current` is set to `false` at line 367 (teardown)
and line 871 (unmount cleanup); set to `true` at line 864 (mount), and
re-set to `true` at line 956 inside `reconnect()`. The H5 guard relies on
the false-on-teardown invariant.

```ts
// BEFORE
ws.onmessage = (event: MessageEvent) => {
  let msg: WSMessage;
  try {
    msg = JSON.parse(event.data) as WSMessage;
  } catch { ... }
  // ... switch on msg.type
};

// AFTER
ws.onmessage = (event: MessageEvent) => {
  // H5 guard: post-teardown WS messages must not dispatch into a stale
  // hook instance. `mountedRef.current` is set to `false` in teardown()
  // and the unmount cleanup. Without this guard, a buffered `session_resumed`
  // arriving in the close handshake window can call setRealConversationId
  // and setResumedFrom on a torn-down hook, surfacing the resume banner
  // on the next mount without ever fetching history (the resume effect
  // never re-runs because realConversationId only transitions null → uuid
  // once, and the fresh mount already saw the stale write).
  if (!mountedRef.current) {
    Sentry.addBreadcrumb({
      category: "kb-chat",
      message: "ws-message-after-teardown",
      level: "warning",
      data: { type: (() => {
        try { return (JSON.parse(event.data) as { type?: string }).type ?? "unknown"; }
        catch { return "unparseable"; }
      })() },
    });
    return;
  }

  let msg: WSMessage;
  try {
    msg = JSON.parse(event.data) as WSMessage;
  } catch { ... }
  // ... switch on msg.type
};
```

**Note on the breadcrumb's parse-twice cost:** the inline IIFE re-parses
`event.data` for the breadcrumb's `type` field. This only fires on the
guard-trip path (post-teardown), which is rare by construction. Fine.

**Why not `wsRef.current.onmessage = null` at teardown:** that would also
discard the close-frame's final code/reason payload (see line 642 onward
where `ws.onclose` runs disconnection logic). The `mountedRef` guard
short-circuits the dispatch, not the receipt — observability stays intact
in the test harness via the breadcrumb.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Filled at draft time.
- This is the SECOND PR against the same surface in the same week. PR #3237
  did not catch the H1/H5 surfaces because both manifest only in long-idle
  re-opens — the test harness used `vi.useFakeTimers` and synthetic clock
  advances rather than real cross-mount WS lifecycles. The new test must
  reproduce in real (jsdom) WebSocket simulation, not via fake timers alone.
- Defense-relaxation watch (AGENTS.md
  `cq-when-a-plan-relaxes-or-removes-a-load-bearing`): we are NOT relaxing
  the existing `historyLoading` gate or the `controller.signal.aborted`
  guard. We are *adding* observability and a `mountedRef` guard at the WS
  message-handler entry. No defense being relaxed.

## Files to Edit

- `apps/web-platform/lib/ws-client.ts` (verified line references against
  HEAD as of branch creation)
  - **Top of file (line ~24):** `import { reportSilentFallback } from "@/lib/client-observability";`
    already exists. Add `import * as Sentry from "@sentry/nextjs";` (currently
    absent — verified via `grep -n "import.*Sentry" apps/web-platform/lib/ws-client.ts`
    returning zero matches).
  - **Line 429** (`ws.onmessage = (event) => {`): add `mountedRef.current`
    guard at top with breadcrumb (H5). See §H5 Implementation Details.
  - **Line 723-725** (`fetchConversationHistory` no-session branch): add
    `reportSilentFallback(null, {feature:"kb-chat", op:"history-fetch-no-session",
    extra:{conversationId:targetId}})` (H1). See §H1 Implementation Details.
  - **Line 814-839** (`runHistoryFetch`): split the
    `if (!result || controller.signal.aborted) return;` guard into two
    branches; add the abort-after-success breadcrumb in the `aborted`
    branch (H2). See §H2 Implementation Details.
  - Document the `runHistoryFetch` non-`useCallback` choice in a one-line
    comment above the function (H3 — observability-only, no behavior
    change).

- `apps/web-platform/server/api-messages.ts`
  - Lower the existing `history-fetch-success-empty` breadcrumb level from
    `info` to `warning` (line 105 in current file — verified via
    `grep -n 'history-fetch-success-empty' apps/web-platform/server/api-messages.ts`).
    Include a TODO comment referencing the H4 disambiguation path so a
    follow-up can add an X-Resumed-Count header. No behavior change;
    observability only.

- `apps/web-platform/test/kb-chat-resume-hydration.test.tsx`
  - Three new cases (H1 RED→GREEN, H5 RED→GREEN, H2 diagnostic). See
    §Test Scenarios for the case-by-case prescription.
  - Reuse the existing `MockWebSocket` class (line 32-66 of the same
    file) — do NOT duplicate.
  - Reuse the `createWebSocketMock` helper from
    `apps/web-platform/test/mocks/use-websocket.ts` ONLY for the
    `historyLoading=false` regression guard in case 1; the H5 case
    requires a real WebSocket lifecycle and must NOT mock the hook.

## Files to Create

- None. All edits are surgical.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Vitest case: when `supabase.auth.getSession()` returns `{ session: null }`
  during `fetchConversationHistory`, the hook does NOT dispatch
  `filter_prepend` AND `reportSilentFallback` is called with
  `op: "history-fetch-no-session"`. **Currently fails on `main`** (no
  Sentry call site exists for this branch).
- [ ] Vitest case: a `session_resumed` message dispatched to a torn-down
  WS instance (`mountedRef.current === false`) does NOT cause
  `setRealConversationId` or `setResumedFrom` to be invoked. Verify by
  asserting the rendered panel reports `realConversationId === null` and
  no banner. **Currently fails on `main`** (handler unguarded).
- [ ] Vitest case: an abort that fires AFTER `fetchConversationHistory`
  resolves but BEFORE dispatch records exactly one Sentry breadcrumb with
  category `"kb-chat"` and message containing `"abort-after-success"`.
- [ ] All KB-chat tests in `kb-chat-resume-hydration.test.tsx`,
  `kb-chat-trigger.test.tsx`, `kb-chat-sidebar.test.tsx`,
  `kb-chat-sidebar-banner-dismiss.test.tsx`, and
  `api-messages-handler.test.ts` continue to pass.
- [ ] `bun run lint` and `tsc --noEmit` both clean.
- [ ] PR body uses `Ref #3241` (the precursor issue) and explicitly states
  the new failure modes (H1/H5) covered by this PR. Do NOT use `Closes`
  on a closed issue.

### Post-merge (operator)
- [ ] After merge, monitor Sentry for new
  `op: "history-fetch-no-session"` events over the next 48h. If any fire,
  the H1 hypothesis is confirmed and the existing fix already covers it.
- [ ] After merge, monitor Sentry for `kb-chat`-category breadcrumbs with
  message `abort-after-success`. If frequent, file a new issue to harden
  the resume effect's lifecycle.
- [ ] If neither fires within 7 days but the user reports the bug again,
  the surviving hypothesis is H4 (server/client message-set divergence) —
  file a follow-up to add the X-Resumed-Count diagnostic header path.

## Test Scenarios

**Test fixture rules (from cross-referenced learnings):**

- **`mockImplementation`, NOT `mockReturnValue`, for the `auth.getSession`
  stub.** Per `2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race`,
  `mockReturnValue(Promise.resolve({...}))` evaluates the promise eagerly at
  setup time, which can resolve before the SUT awaits it and break the
  test's intended resolution ordering. Use:
  `mockGetSession.mockImplementation(async () => ({ data: { session: null } }))`.
- **Stable references for hook-mock returns.** Per
  `2026-04-07-userouter-mock-instability-causes-useeffect-refire`, the
  `MockWebSocket` instance and any factory return values that flow into
  hook deps must be stable across re-renders, or the resume effect re-fires
  and obscures the failure path under test.
- **Precondition seeding for the H5 test.** Per
  `2026-04-22-red-test-must-simulate-suts-preconditions`, the test must
  install spies on the observable state setters (`vi.spyOn(React, ...)`
  is fragile — instead spy on the rendered output via React Testing
  Library `getByText`/`queryByText` for the banner's appearance and the
  message-list emptiness). The buggy code path requires `mountedRef` to
  be `false` at message-handler entry; we MUST trigger `unmount()` before
  dispatching the synthetic message.
- **Vitest fake timers vs real WebSocket lifecycle.** Per the precursor
  learning's "test fidelity gate" cross-ref, fake timers alone do NOT
  exercise the cross-mount WS lifecycle. Use real (jsdom) timers for H5
  and only `vi.useFakeTimers` for the H2 50ms delay simulation, with a
  `vi.useRealTimers()` reset in `afterEach`.

### Cases

1. **H1 RED→GREEN** — null Supabase session at fetch time
   - Setup: `mockGetSession.mockImplementation(async () => ({ data: { session: null } }))`.
   - Action: render `<ChatSurface conversationId="new" sidebarProps={{ resumeByContextPath: "/doc/foo.pdf", onThreadResumed }}/>`,
     dispatch a `session_resumed` over the mock WS.
   - Assert: `reportSilentFallback` called once with
     `expect.objectContaining({ feature: "kb-chat", op: "history-fetch-no-session", extra: { conversationId: <uuid> }})`.
   - Assert: empty-state placeholder is NOT visible while
     `historyLoading === true` (regression guard for the existing H3 fix
     from #3237).
   - **RED verification:** without the `reportSilentFallback` call site
     added by H1, the assertion fails because the spy receives 0 calls.
     Confirm the test fails on `main` BEFORE applying the fix — this is
     the cross-referenced "RED test must distinguish gated from ungated"
     gate from `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`.

2. **H5 RED→GREEN** — stale WS message after teardown
   - Setup: render the `useWebSocket` hook (NOT mocked at the hook layer
     — use the real hook with `globalThis.WebSocket = MockWebSocket`
     installed in `beforeEach` per the existing pattern in
     `kb-chat-resume-hydration.test.tsx:32-66`). Await
     `MockWebSocket.OPEN` state. Capture the `ws.onmessage` handler
     reference from the most recent `MockWebSocket` instance.
   - Action: call `act(() => { unmount(); })`. Then synchronously invoke
     `capturedOnMessage(new MessageEvent("message", { data: JSON.stringify({ type: "session_resumed", conversationId: "<uuid>", resumedFromTimestamp: "...", messageCount: 3 }) }))`.
   - Assert: re-render the panel via a fresh mount with the same
     `resumeByContextPath`. The freshly-mounted panel's `realConversationId`
     observable (via the message-list rendering) must NOT show 3 messages
     from a stale dispatch — only what the new mount fetches via its own
     resume cycle.
   - Assert: a Sentry breadcrumb was recorded via
     `Sentry.addBreadcrumb` with `category: "kb-chat"` and
     `message: "ws-message-after-teardown"`.
   - **RED verification:** without the `mountedRef.current` guard, the
     state setters in the stale handler still run and the test would
     observe an inconsistent banner/messages state on the next mount.

3. **H2 diagnostic** — abort fires after fetch resolution
   - Setup: stub `fetchConversationHistory` to resolve a 2-message payload
     after a 50ms delay (use `vi.useFakeTimers()` for this case only,
     `vi.useRealTimers()` in `afterEach`).
   - Action: dispatch `session_resumed`, then within 25ms re-key the
     parent `conversationId` so the resume effect cleanup runs (calling
     `controller.abort()`). Advance timers past 50ms.
   - Assert: `reportSilentFallback` is NOT called (this is expected
     correct behavior, not an error). Assert ONE breadcrumb is recorded
     via `Sentry.addBreadcrumb` with category `"kb-chat"` and message
     `"abort-after-success"`, with `data.messageCount === 2`.

4. **Negative case** — happy path still works
   - Setup: real session, real fetch returning 3 messages, normal
     `session_resumed` arrival.
   - Assert: 3 message bubbles render, banner shows, no Sentry fallback
     fires, no abort breadcrumb. (Already covered by existing tests; add
     an explicit cross-reference in the new file's describe block:
     `// Cross-reference: kb-chat-resume-hydration.test.tsx ::
     "hydrates Command Center history (non-'new' conversationId) — AC3"`.)

## Pre-Implementation Verification

These checks run BEFORE any code edit (per the precursor learning's
session-error log: paraphrase-without-verification is the #1 plan-drift
class). All must return the expected output:

```bash
# H1 site exists at the prescribed line
grep -nE 'if \(!session\?\.access_token\) return null;' apps/web-platform/lib/ws-client.ts
# Expected: 725:    if (!session?.access_token) return null;

# H5 site exists at the prescribed line
grep -nE '^    ws\.onmessage = ' apps/web-platform/lib/ws-client.ts
# Expected: 429:    ws.onmessage = (event) => {

# H2 site exists at the prescribed line
grep -nE 'if \(!result \|\| controller\.signal\.aborted\)' apps/web-platform/lib/ws-client.ts
# Expected: 822:      if (!result || controller.signal.aborted) return;

# Sentry import absence (must add)
grep -c '@sentry/nextjs' apps/web-platform/lib/ws-client.ts
# Expected: 0

# reportSilentFallback import already present (must NOT re-add)
grep -c 'from "@/lib/client-observability"' apps/web-platform/lib/ws-client.ts
# Expected: 1

# api-messages breadcrumb at the prescribed line
grep -nE 'history-fetch-success-empty' apps/web-platform/server/api-messages.ts
# Expected: 105:      message: "history-fetch-success-empty",
```

If any check fails, do NOT proceed — the file has drifted from this plan.
Re-read the file and adjust the plan rather than implementing against
stale offsets.

## Risks

- **Adding observability to a hot path.** The `mountedRef` guard at the
  top of `onmessage` is O(1) and cannot regress. The Sentry breadcrumb
  on abort fires only when `result !== null && aborted === true` — a
  rare branch by construction. Acceptable.
- **H1 fix changes the contract for a callsite that was returning `null`
  silently.** Today: `fetchConversationHistory` returns `null` for any
  pre-fetch failure. After: still returns `null`, but ALSO mirrors the
  no-session case to Sentry. No behavior regression — strictly more
  visibility.
- **H5 guard might silently drop messages we WANT to process during
  teardown.** Specifically: usage_update or workflow_ended events that
  arrive in the close handshake window. Mitigation: only the WS-handler
  state setters are dropped; pino logging at the message-receipt entry
  is preserved (it lives outside the guard) so the observability trail
  is intact. The teardown path already invalidates these state values
  by setting `realConversationId = null` and `setSessionConfirmed(false)`,
  so the dropped events would have been clobbered anyway.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** assessed inline by the planner.
**Assessment:** This is a defensive observability + edge-case-coverage
patch for a bug class that was supposed to be closed by the precursor PR
but resurfaced. The approach is correct: instrument first, narrow the
hypothesis space, ship the surgical fix that covers H1 and H5
mechanically (the two paths with deterministic reproductions). H2 is
left as observability-only because the abort behavior IS correct. H4
is left as a deferred diagnostic until breadcrumb data confirms or
rules it out.

**Brainstorm-recommended specialists:** none (no brainstorm exists for
this bug — `/soleur:plan` invoked directly via one-shot).

### Product/UX Gate
Tier: NONE — bug fix on existing surface, no new components, no new
flows, no copy changes.

## References

- Precursor PR: `#3237` — `89be22bc fix(kb-chat): hydrate prior messages on resume + correct trigger label`
- Precursor learning: `knowledge-base/project/learnings/ui-bugs/2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md`
- Precursor plan: `knowledge-base/project/plans/2026-05-05-fix-kb-doc-chat-resume-hydration-and-button-label-plan.md`
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — drives H1 fix
- AGENTS.md `cq-when-a-plan-relaxes-or-removes-a-load-bearing` — confirms no relaxation
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — threshold `none` justified above
- Repro screenshot: `/home/jean/Pictures/Screenshots/Screenshot From 2026-05-05 15-18-23.png`

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no
matches against `ws-client.ts`, `chat-surface.tsx`, `kb-chat-content.tsx`,
or `api-messages.ts` at plan time.
