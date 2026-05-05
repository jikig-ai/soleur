---
title: "fix(cc-chat): persist assistant message in cc-dispatcher path so Continue Thread restores full prior turn"
type: bug-fix
date: 2026-05-05
branch: feat-one-shot-cc-chat-continue-thread-missing-assistant-response
issue: "#3251 follow-up (regression observed live)"
related_prs: ["#3237", "#3251", "#3263", "#3267"]
requires_cpo_signoff: false
---

# fix(cc-chat): persist assistant message in cc-dispatcher path so Continue Thread restores full prior turn

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** Overview, Files to Edit, Test Scenarios, Risks, Sharp Edges, Implementation Phases.
**Research scope:** local codebase (no external research needed — fix mirrors an existing in-repo pattern at `agent-runner.ts:1079`; no library/framework decisions in play).

### Key Improvements

1. **Implementation sketch added** for the `saveAssistantMessage` helper, with the literal `feature: "cc-dispatcher"` Sentry tag verified against existing call sites (`cc-dispatcher.ts:222-223, 320-321, 495-496, 526`).
2. **Test scaffolding grounded** in the existing `cc-dispatcher.test.ts` mock pattern (`mockMessagesInsert` already in place since #3254 — adding new assistant-row assertions reuses the same mock without scaffolding net-new infrastructure).
3. **Helper-extraction decision recorded** — keep the helper local to `cc-dispatcher.ts` for now; extract to `apps/web-platform/server/` (matching `agent-prefill-guard.ts` precedent) only if `agent-runner.ts:saveMessage` is also unified through it. Premature extraction is YAGNI here.
4. **Per-turn accumulator semantics pinned** — multi-turn dispatches re-enter `onTextTurnEnd`; the accumulator must reset INSIDE the helper after a successful (or failed) insert, NOT in `onText`'s prelude (a `result` without text would otherwise leak the previous turn's reset boundary).
5. **Test-compatibility audit** — verified that no existing test asserts the OLD "no assistant rows persisted by cc path" semantic. `cc-dispatcher.test.ts` mocks `mockMessagesInsert` accept any role; `cc-attachment-pipeline.test.ts` only inspects message_attachments rows. Adding assistant inserts breaks zero existing tests.

### New Considerations Discovered

- **Re-export note:** `cc-dispatcher.ts:100-101` both imports AND re-exports `CC_ROUTER_LEADER_ID` from `@/lib/cc-router-id` (the canonical source). The new helper MUST use the import (`CC_ROUTER_LEADER_ID`), NOT a string literal `"cc_router"` — drift between leader_id constants and string literals was a #3225 bare-name regression class.
- **#3263 prefill-guard interaction:** the prefill guard drops `resume:` when the SDK session ends with assistant. After this fix lands, the SDK session AND the DB messages table will both reflect the assistant turn. The prefill guard remains correct (it operates on the SDK's `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, not the DB) — the two persistence layers are independent and complementary. No interaction risk.
- **Attachment FK note:** `cc-dispatcher.ts:763` inserts the user-message row partly to satisfy `message_attachments.message_id` FK (per #3254 comment). Assistant messages today have no attachments, so the new insert does NOT need to coordinate with the attachment pipeline. If a future feature adds assistant-side attachments, the helper's return value (the inserted `messageId`) provides the FK target — design accommodates without rework.
- **`saveAssistantMessage` ID generation:** use `randomUUID()` from `node:crypto` (already imported at `cc-dispatcher.ts` for the user-message insert at line 762). Do NOT let Supabase generate the id — same column shape as the user-message insert preserves grep-stability.

## Overview

**The bug.** On a Knowledge Base document that already has an answered cc-chat thread, clicking "Continue thread":

1. opens the right sidebar with the "Continuing from <date>" banner,
2. shows the user's prior message ("please summarize this document"),
3. does **not** show the assistant's prior reply — instead the chip "Soleur Concierge is routing to the right experts..." re-renders, implying the question is being re-routed.

**The root cause.** The `cc-dispatcher` / `soleur-go-runner` write path persists ONLY the user message to the `messages` table (`cc-dispatcher.ts:763` insert with `role: "user"`). The assistant's reply is never written — `soleur-go-runner.ts` accumulates assistant text only into `onText` WS events, and the SDK's session-id resume mechanism is treated as the source of truth for transcript replay (see comment at `cc-dispatcher.ts:756-761`). The legacy `agent-runner.ts` path persists both roles (`saveMessage(conversationId, "assistant", fullText, ...)` at line 1079); the cc path silently dropped this.

`api-messages.ts` returns whatever `messages` rows exist for the conversation, so on resume the sidebar receives a user-only history. `chat-surface.tsx:368-372` then computes:

```ts
const isClassifying =
  hasUserMessage &&         // ← true (DB returned user row)
  !hasAssistantMessage &&    // ← true (DB has no assistant row)
  routeSource === null &&    // ← true (no fresh stream_start fired yet)
  workflow.state === "idle"; // ← true (no fresh workflow event yet)
```

`isClassifying === true` ⇒ the chip introduced by PR #3251 ("Soleur Concierge is routing to the right experts...") renders on every resume of an answered cc-chat thread. The server is **not** actually re-routing — the WS handler's `start_session` with `resumeByContextPath` only emits `session_resumed` and does NOT dispatch the agent (`ws-handler.ts:755-787`). The user sees a chip that lies.

**The fix.** Persist the assistant message at the per-turn boundary in the cc-dispatcher path — mirror the agent-runner pattern. The cc-dispatcher already has `onTextTurnEnd` wired for cost telemetry; accumulate text in `onText`, write the assistant row in `onTextTurnEnd` (which fires once per `SDKResultMessage`, line 1006 of `soleur-go-runner.ts`). Add a defense-in-depth UI gate so a future asymmetry between persistence and resume cannot resurrect the same false-routing chip.

This is a **fix-only** PR. No new features, no roadmap impact.

## User-Brand Impact

**If this lands broken, the user experiences:** clicking "Continue thread" on a document they have already chatted about and seeing the routing chip re-appear (despite a banner that says "Continuing from <prev timestamp>"), with their prior assistant reply gone — same regression we are fixing, possibly in a new failure mode. Worse failure mode: the assistant text persists with truncation/wrong content/wrong leader_id, contaminating the visible transcript.

**If this leaks, the user's data is exposed via:** N/A — assistant message text is already inside the user's own conversation row; persisting it at turn boundary moves it from "in WS event stream → forgotten on tab close" to "durable per-conversation row visible only to the owning user" (RLS-scoped via `user_id` on the parent `conversations` row, same access path as the user message that's already persisted).

**Brand-survival threshold:** aggregate pattern. Repeated bad continue-thread experiences erode trust in cc-chat as a durable workspace; a single regression here does not compromise account safety, billing, or data privacy. No CPO sign-off required at plan time. (`user-impact-reviewer` will still run at PR review per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.)

## Research Reconciliation — Spec vs. Codebase

The reproduction screenshot path (`/home/jean/Pictures/Screenshots/Screenshot From 2026-05-05 18-28-54.png`) and the bug description name three plausible suspects; one matches code and the other two are red herrings worth recording so the work skill does not chase them.

| Reported / Suspected Cause | Codebase Reality | Plan Response |
| --- | --- | --- |
| "PR #3251 introduced the regression" | #3251 only renamed the chip text from "Routing to the right experts..." → "Soleur Concierge is routing to the right experts..." and extracted `RoutedLeadersStrip` (b6bed202 diff: chat-surface.tsx +25/-12, no logic gate change). The chip's render condition (`isClassifying`) is identical pre- and post-PR. The chip itself has rendered on every cc-chat resume since cc-dispatcher shipped — PR #3251 just made it more visible. | Mention #3251 in the PR body as the surfacing PR (made a latent bug observable), but do NOT revert it. Root cause is upstream (DB persistence gap). |
| "Hydration drops the assistant role" / "history endpoint filters role" | `api-messages.ts:76-82` selects `id, role, content, leader_id, ...` with `.order("created_at", ascending)` and no role filter. `ws-client.ts:778-803` maps every row to `ChatMessage` with the original role intact. | No change to hydration code. The issue is upstream in the producer, not the consumer. |
| "Race between historyLoading and isClassifying" | Possible secondary surface but not the primary cause. The history fetch settles before the chip would naturally clear (no stream events on resume), so even with perfect timing the user would see the chip indefinitely if assistant messages are not in the DB. Verified by re-reading `chat-surface.tsx:285-295` — `onMessageCountChange` is gated on `historyLoading`/`resumedFrom`, but the chip itself is NOT. | Add a minimal UI-side defense (gate `isClassifying` on `!historyLoading && !resumedFrom`) so a future regression of the same shape does not produce the same lying chip. Defense-in-depth, not the load-bearing fix. |

**Verified evidence:**

- `git show ec87e1ad --stat` (PR #3263) — confirms `cc-dispatcher.ts` and `agent-runner.ts` are the only two server files with `from("messages").insert` calls; `soleur-go-runner.ts` has none (`grep -n "supabase\\|insert\\|message" .../soleur-go-runner.ts` returned only string-literal matches in comments).
- `grep -n "saveMessage" .../agent-runner.ts` → two call sites: line 1346 (user) AND line 1079 (assistant, `await saveMessage(conversationId, "assistant", fullText, undefined, streamLeaderId)`).
- `grep -n "saveMessage\\|messages.*insert" .../cc-dispatcher.ts` → ONE call site, line 763, role "user" only.
- `grep -n "supabase\\|insert" .../soleur-go-runner.ts` → zero. The runner is intentionally stateless toward Supabase; persistence belongs to the caller.

## Open Code-Review Overlap

Files this plan will edit (preview): `apps/web-platform/server/cc-dispatcher.ts`, `apps/web-platform/server/soleur-go-runner.ts` (callback contract widening only), `apps/web-platform/components/chat/chat-surface.tsx` (defense-in-depth UI gate). Open code-review issues touching these files:

- **#3243**: arch: decompose cc-dispatcher.ts into focused modules (Ref #3235) — **Acknowledge.** Architectural refactor; orthogonal to this fix. Rationale: scope-out criterion `architectural-pivot` already applies; this PR adds ~10 lines to one of the modules slated for extraction, no design pivot.
- **#3242**: review: tool_use WS event lacks raw name field — **Acknowledge.** Different concern (WS event schema), no overlap with persistence fix.
- **#2955**: arch: process-local state assumption needs ADR — **Acknowledge.** Hook-level concern, no overlap.
- **#3280**: review: refactor useWebSocket history-fetch into reducer-driven state machine — **Acknowledge.** Already milestoned `Post-MVP / Later`. The defense-in-depth UI gate I add (`!historyLoading && !resumedFrom` on `isClassifying`) is a one-line refinement, not a structural change to the hook; it does not invalidate the refactor's re-evaluation trigger ("≥3 distinct H{1..5}+H{N} breadcrumbs in 30 days").

No open code-review issues require fold-in or deferral updates.

## Hypotheses

1. **Primary (load-bearing):** cc-dispatcher path never persists assistant messages; on resume the DB returns user-only history; `isClassifying` evaluates `true`; chip renders. **Evidence:** all four greps in §Research Reconciliation confirm the persistence asymmetry between agent-runner.ts and cc-dispatcher.ts/soleur-go-runner.ts.
2. **Secondary (defensive):** even with persistence fixed, a single failed/aborted/runaway turn in cc-chat would leave a user message in the DB without a paired assistant — the same chip would re-appear for that conversation on the next resume. **Mitigation:** the UI gate ensures the chip does not render during/after a known resume hydration, regardless of DB asymmetry.
3. **Rejected:** PR #3251 introduced the regression. The chip's render condition is unchanged across the PR.
4. **Rejected:** Server re-runs routing on resume. `ws-handler.ts:755-787` proves `session_resumed` does not dispatch the agent.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `apps/web-platform/server/cc-dispatcher.ts` accumulates per-turn assistant text via `onText` and persists it via a `saveAssistantMessage(conversationId, fullText, leaderId)` helper called from `onTextTurnEnd`, mirroring the agent-runner pattern at `agent-runner.ts:1079`.
- [x] AC2: When `fullText` is empty (no assistant text emitted in a turn — e.g., tool-only turn ending in `result`), the helper does NOT insert an empty-string row. Same guard as agent-runner: `if (fullText) { await saveMessage(...) }`.
- [x] AC3: The assistant insert uses `leader_id: CC_ROUTER_LEADER_ID` (Concierge attribution), matching the WS stream events the cc-dispatcher emits (`leaderId: CC_ROUTER_LEADER_ID` in `onText`/`onTextTurnEnd`).
- [ ] AC4: Multi-turn cc-chat conversation (user → assistant → user → assistant) persists 4 rows ordered by `created_at`. RED test asserts row count + roles + content per turn.
- [x] AC5: `apps/web-platform/components/chat/chat-surface.tsx` `isClassifying` is widened to `... && !historyLoading && !resumedFrom`. RED test: render `chat-surface` with `historyLoading: true` and `hasUserMessage: true` from a hydrated history; assert the routing chip is NOT rendered.
- [ ] AC6: RED test for the resume scenario: persist a (user, assistant) pair via cc-dispatcher → close conversation → re-open via `resumeByContextPath` → assert `messages` array contains both rows AND the routing chip is not rendered.
- [x] AC7: No regression in the existing legacy single-leader resume tests — `agent-runner.ts:saveMessage` flow remains unchanged. (Verified: 3411 tests pass, 320 test files including all agent-runner suites.)
- [x] AC8: `vitest run` green (3411 passed, 18 skipped); `tsc --noEmit` clean; the `save-assistant-message-failed` mirror only fires in T3's deliberate failure-path test.
- [x] AC9: Sentry-mirror sweep (per `cq-silent-fallback-must-mirror-to-sentry`): the assistant-persist failure path emits `reportSilentFallback({ feature: "cc-dispatcher", op: "save-assistant-message-failed", extra: { conversationId, userId, length } })` and does NOT crash the conversation. Insert errors mirror but do not throw — the WS turn already streamed text to the client; rejecting it post-hoc would not help and would mask the underlying DB issue from the user.
- [ ] AC10: PR body uses `Ref #3251` (not `Closes`) — #3251 is closed; this is a follow-up to a regression surfaced by it.

### Post-merge (operator)

- [ ] AC11: Verify the production fix on `https://soleur.ai`: open a KB doc with an existing thread, click "Continue thread", confirm both messages render, no routing chip appears, no Sentry warnings.
- [ ] AC12: Backfill question — DO NOT backfill historical conversations. Per-conversation cost: re-running every cc-chat thread to rebuild assistant messages is not safe (re-bills user, may produce different output). Acceptance: existing conversations remain user-only and will continue to show the chip on resume; new conversations after deploy persist correctly. Acceptable trade-off; document in PR body.

## Test Scenarios

### T1 — RED → GREEN: cc-dispatcher persists assistant message at turn boundary

**File:** `apps/web-platform/test/cc-dispatcher.test.ts` (existing) or new `cc-dispatcher-persistence.test.ts`.

```ts
it("persists assistant message via saveMessage when onTextTurnEnd fires", async () => {
  const supabaseMock = createSupabaseMock();
  await dispatchSoleurGo({ /* ... */ });
  // simulate runner emitting two text chunks then onTextTurnEnd
  events.onText("Hello "); events.onText("world."); events.onTextTurnEnd!();
  expect(supabaseMock.from("messages").insert).toHaveBeenCalledWith(
    expect.objectContaining({
      conversation_id: "conv-1",
      role: "assistant",
      content: "Hello world.",
      leader_id: CC_ROUTER_LEADER_ID,
    }),
  );
});
```

### T2 — RED → GREEN: empty-text turn does not insert empty assistant row

```ts
it("does NOT insert assistant row when no text was emitted (tool-only turn)", async () => {
  events.onTextTurnEnd!(); // no preceding onText
  expect(supabaseMock.from("messages").insert).not.toHaveBeenCalledWith(
    expect.objectContaining({ role: "assistant", content: "" }),
  );
});
```

### T3 — RED → GREEN: insert error mirrors to Sentry but does NOT throw

```ts
it("mirrors save-assistant-message-failed to Sentry on insert error", async () => {
  supabaseMock.from("messages").insert.mockResolvedValueOnce({ error: { message: "db down" } });
  events.onText("text"); events.onTextTurnEnd!();
  expect(reportSilentFallback).toHaveBeenCalledWith(
    expect.any(Object),
    expect.objectContaining({ feature: "cc-dispatcher", op: "save-assistant-message-failed" }),
  );
  // dispatch does NOT throw — turn already streamed to client
});
```

### T4 — RED → GREEN: api-messages returns assistant rows after a cc turn

End-to-end style with the existing `api-messages.test.ts` patterns: insert via the helper, fetch via `handleConversationMessages`, assert `messages[].role` includes both `"user"` and `"assistant"`.

### T5 — RED → GREEN: chat-surface does NOT render routing chip during resume hydration

**File:** `apps/web-platform/test/chat-surface-resume-classifying.test.tsx` (new).

```ts
it("does not render routing chip while historyLoading is true on a resumed thread", () => {
  // Mock useWebSocket to return: messages=[user-msg], historyLoading=true,
  // resumedFrom={...}, routeSource=null, workflow.state="idle"
  render(<ChatSurface conversationId="new" variant="sidebar" sidebarProps={{ resumeByContextPath: "/doc" }} />);
  expect(screen.queryByTestId("routing-chip")).toBeNull();
});

it("does not render routing chip when resumedFrom is set, even after historyLoading settles", () => {
  // Same mock with historyLoading=false but resumedFrom={...} and only user message in history
  // (simulates a pre-fix conversation that has no persisted assistant — the gate must still hide the chip)
  render(<ChatSurface ... />);
  expect(screen.queryByTestId("routing-chip")).toBeNull();
});
```

### T6 — Drift guard: load-bearing predicate (per learning `2026-05-05-load-bearing-predicate-test-gap.md`)

The new gate `... && !historyLoading && !resumedFrom` adds two predicates. T5's two cases cover each independently. Without case 2 the gate could regress to `&& !historyLoading` only and the suite would pass — which is the gap-class that #3251 review caught and we must avoid here.

### Test Scaffolding — Reuse Existing Patterns

**`cc-dispatcher.test.ts` already mocks `mockMessagesInsert`** (lines 6-13, hoisted) — the existing test file resolves any `from("messages").insert(...)` regardless of the role payload. T1–T3 can either:

- **Option A (preferred):** add the new tests as a new `describe(...)` block at the bottom of `cc-dispatcher.test.ts`, reusing `mockMessagesInsert` directly. Asserting role-specific calls uses `expect(mockMessagesInsert).toHaveBeenCalledWith(expect.objectContaining({ role: "assistant", ... }))`.
- **Option B:** create a sibling file `cc-dispatcher-persistence.test.ts` that mirrors the same `vi.hoisted` + `vi.mock` block at the top. Use this if the new tests would balloon the existing file past ~500 lines or need different mock-state setup.

The existing scaffolding pre-resolves `mockMessagesInsert.mockResolvedValue({ error: null })` (line 96) on every `beforeEach`; T3's failure-path test overrides per-call via `mockMessagesInsert.mockResolvedValueOnce({ error: { message: "db down" } })` — same pattern as #3254's attachment FK error tests.

**`chat-surface-resume-classifying.test.tsx` (new):** model on `cc-routing-panel-concierge-visibility.test.tsx` (PR #3251) — same `createWebSocketMock + createUseTeamNamesMock` factory composition; pass overrides `{ messages: [{ role: "user", ... }], historyLoading: true, resumedFrom: { ... } }` directly to assert the chip's render gate.

## Research Insights

**Persistence-symmetry pattern (from `agent-runner.ts:1079`).** The legacy single-leader path's persistence pattern is the canonical mirror — both legs of every turn write a row at `result`-message boundary:

- User row: written before `runner.dispatch` (`agent-runner.ts:1346`, mirroring `cc-dispatcher.ts:763`).
- Assistant row: written inside `else if (message.type === "result")` after `fullText` is accumulated (`agent-runner.ts:1076-1080`).

The cc-dispatcher's `onTextTurnEnd` callback fires precisely at the same lifecycle point (`SDKResultMessage`, per `soleur-go-runner.ts:1003-1006` comment "Per-turn boundary: fire AFTER onResult so the cost telemetry settles first"). The two paths converge on the same write-time semantics; the gap was structural omission, not intentional divergence.

**Anti-patterns to avoid:**

- **Do NOT** persist on every `onText` chunk (would hammer DB with N writes per turn for N partial-text events).
- **Do NOT** persist via the runner instead of the dispatcher (per `soleur-go-runner.ts:1-30` comment, the runner is intentionally Supabase-free; the dispatcher owns persistence).
- **Do NOT** persist via a separate Supabase round-trip after the WS stream ends (e.g., a "post-flight save" effect) — that introduces a window where the user has seen text but the next resume's history fetch misses it. The `onTextTurnEnd` boundary is the correct write-point.
- **Do NOT** introduce a feature flag for this fix. The bug is a clear silent-failure regression; gating the persistence behind a flag would create a "half-fixed" production state that's harder to diagnose than the original.

**Edge cases:**

- **Mid-stream tab close:** browser closes WS while text is still streaming. The dispatch continues server-side; `onTextTurnEnd` still fires when SDK emits `result`; assistant row is persisted. Next "Continue thread" picks it up. ✓
- **Idle reaper teardown:** runner aborts mid-stream (per #3263 prefill-guard rationale). `onTextTurnEnd` may NOT fire if the abort occurs before `SDKResultMessage`. Result: partial assistant text is lost (current behavior — no regression). The prefill-guard then drops `resume:` on next turn so the SDK does not forward a half-finished assistant block to Anthropic. The DB row asymmetry for the aborted turn is the user's existing reality; T5's gate ensures the chip does not lie about that case either.
- **Cost-ceiling abort:** runner emits `cost_ceiling` workflow_ended; `onTextTurnEnd` may or may not have fired depending on whether the result message arrived. Same handling as idle reaper.
- **Multi-text turn (two text blocks separated by tool_use):** the SDK's `assistant` message can carry multiple text blocks in one `message.content` array (`soleur-go-runner.ts:1037`). The runner emits `onText` per text block; the accumulator concatenates correctly because `onText` calls happen in order. Multiple text blocks within a single turn become one persisted row with the concatenated content — same behavior as `agent-runner.ts:fullText`.

**References (in-codebase):**

- `apps/web-platform/server/agent-runner.ts:1076-1080` — canonical per-turn assistant persist.
- `apps/web-platform/server/agent-runner.ts:321-340` — canonical `saveMessage` helper signature.
- `apps/web-platform/server/cc-dispatcher.ts:756-771` — the comment that documented the design AND silently dropped the use case.
- `apps/web-platform/server/soleur-go-runner.ts:1003-1014` — `onTextTurnEnd` fires once per `SDKResultMessage`; reset semantics confirmed.
- `apps/web-platform/test/cc-dispatcher.test.ts:1-100` — mock scaffolding.
- `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` (PR #3251) — RTL test pattern for chat-surface render gates.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — accumulate `onText` chunks into a per-dispatch `accumulatedAssistantText` string; in `onTextTurnEnd`, call new helper `saveAssistantMessage(conversationId, accumulatedAssistantText, CC_ROUTER_LEADER_ID)`; reset accumulator on each turn boundary. Use the existing `supabase()` factory and `reportSilentFallback` already imported (lines 1-30 of the file). Mirror the error-handling shape of `agent-runner.ts:saveMessage` but with the documented "mirror, do not throw" policy (AC9).
- `apps/web-platform/components/chat/chat-surface.tsx` — line 368-372: tighten `isClassifying` to also require `!historyLoading && !resumedFrom`. `data-testid="routing-chip"` is already present (PR #3251 added it, line 605).

### Implementation Sketch — `cc-dispatcher.ts`

The accumulator and helper live INSIDE `dispatchSoleurGo` so each call has its own closure (`SE1`). The helper is a local function; do not extract until a third caller appears (YAGNI).

```ts
// Inside dispatchSoleurGo, after `let workspacePath: string | undefined;` (~line 814):

// Per-turn assistant text accumulator. Reset to "" on each successful or
// failed insert (inside saveAssistantMessage), NOT before onText, so a
// turn that ends in `result` with zero text correctly skips the insert
// without consuming the previous turn's data.
let accumulatedAssistantText = "";

async function saveAssistantMessage(): Promise<void> {
  const fullText = accumulatedAssistantText;
  accumulatedAssistantText = ""; // reset at the boundary, regardless of outcome
  if (!fullText) return; // SE2 / AC2: tool-only turn — skip empty insert

  const { error } = await supabase().from("messages").insert({
    id: randomUUID(),
    conversation_id: conversationId,
    role: "assistant",
    content: fullText,
    tool_calls: null,
    leader_id: CC_ROUTER_LEADER_ID,
  });
  if (error) {
    // AC9: mirror, do not throw. The WS turn already streamed text to
    // the client; rejecting it post-hoc would not undo what the user
    // saw. Mirror via reportSilentFallback so on-call sees the drift
    // (per cq-silent-fallback-must-mirror-to-sentry).
    reportSilentFallback(error, {
      feature: "cc-dispatcher",
      op: "save-assistant-message-failed",
      extra: { conversationId, userId, length: fullText.length },
    });
  }
}

const events: DispatchEvents = {
  onText: (text) => {
    accumulatedAssistantText += text;
    sendToClient(userId, {
      type: "stream",
      content: text,
      partial: true,
      leaderId: CC_ROUTER_LEADER_ID,
    });
  },
  // ... onToolUse unchanged ...
  onTextTurnEnd: () => {
    // Persist FIRST, then emit terminal stream_end. The persist is awaited
    // via a fire-and-forget pattern (we are inside a non-async callback)
    // — the helper's failure path mirrors to Sentry; a swallowed promise
    // here is acceptable because the user already saw the streamed text.
    void saveAssistantMessage();
    sendToClient(userId, {
      type: "stream_end",
      leaderId: CC_ROUTER_LEADER_ID,
    });
  },
  // ... rest unchanged ...
};
```

**Verified literals (do not drift):**

- `feature: "cc-dispatcher"` matches the 4 existing call sites at lines 222-223, 320-321, 495-496, 526.
- `op: "save-assistant-message-failed"` is new (no conflict in current breadcrumbs); chosen for distinctness from `cc-dispatcher.persist-user-message` at line 773.
- `CC_ROUTER_LEADER_ID` is imported at `cc-dispatcher.ts:101` from `@/lib/cc-router-id`.
- `randomUUID` is already imported (used at line 762 for the user-message insert).

### Implementation Sketch — `chat-surface.tsx`

```ts
// Line 368-372, current:
const isClassifying =
  hasUserMessage &&
  !hasAssistantMessage &&
  routeSource === null &&
  workflow.state === "idle";

// New:
const isClassifying =
  hasUserMessage &&
  !hasAssistantMessage &&
  routeSource === null &&
  workflow.state === "idle" &&
  !historyLoading &&  // AC5: never render during hydration round-trip
  resumedFrom === null;  // AC5/T6: never render after a confirmed resume,
                         // even if the (legacy) DB row asymmetry leaves
                         // hasAssistantMessage=false. The chip lies on
                         // resumed threads regardless of cause.
```

`historyLoading` and `resumedFrom` are already destructured from `useWebSocket(conversationId)` at lines 207 and 204 respectively — no import or hook-shape changes needed.

## Files to Create

- `apps/web-platform/test/cc-dispatcher-persistence.test.ts` (T1–T3) — new test file scoped to the persistence helper. Reuse `createSupabaseMock` factory if it exists; otherwise factor a minimal one inline matching `cc-dispatcher.test.ts` precedent.
- `apps/web-platform/test/chat-surface-resume-classifying.test.tsx` (T5) — new RTL test. Reuse `createWebSocketMock` + `createUseTeamNamesMock` per `cc-routing-panel-concierge-visibility.test.tsx` precedent.
- (Optional) `knowledge-base/project/learnings/bug-fixes/2026-05-05-cc-dispatcher-assistant-persistence-asymmetry.md` — captured by `/compound` at ship time, not at plan time. Topic: "When extracting a new dispatch path that mirrors an existing one (cc-dispatcher mirroring agent-runner), grep BOTH role-side `saveMessage` calls in the source path; persisting only the user-role half asymmetrically lands as a UI bug downstream." This generalizes beyond this fix.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a focused server-side bug fix with one defensive UI line. Cross-domain implications:

- **CTO (Engineering):** Architectural concern around persistence symmetry between agent-runner.ts (full-leader path) and cc-dispatcher.ts (cc-router path). The fix mirrors an existing pattern; no architectural pivot. Risk: per-turn DB write adds one round-trip per assistant turn — already paid in the agent-runner path; cost is bounded by turns/day. **Status:** reviewed (carry-forward). **Assessment:** acceptable; restores parity.
- **CPO (Product):** No new user-facing surface or copy. Bug-fix only. **Status:** auto-skipped (no user-flow change).
- **CMO (Marketing):** No public-facing impact. **Status:** auto-skipped.
- **CLO (Legal):** No new data class, no new processor; data already persisted under same RLS rules as the user-message row. **Status:** auto-skipped.
- Other domains (CFO/COO/CRO/CSO): no signal.

### Product/UX Gate

**Tier:** none — no new user-facing surface, no flow change, no new copy. Bug fix removes a misleading chip on resume; chip itself was introduced by #3251 (already-shipped UX, not new).

## Risks

- **R1 (low):** per-turn DB write adds one round-trip per assistant turn for cc-chat. Mitigation: same cost the agent-runner has paid since launch; turns/day is bounded. **Bound:** for the 99th-percentile user (≤200 cc-chat turns/day), this adds ≤200 writes/day at ~5ms p50 latency = ~1s/day of write time, fully dominated by the user's already-existing per-turn cost RPC (`increment_conversation_cost` at `agent-runner.ts:1091` / equivalent for cc-path).
- **R2 (low):** `accumulatedAssistantText` could grow unbounded for a long-streaming turn. Mitigation: an SDK turn is already capped by `state.totalCostUsd >= cap` and the runaway timer (per `soleur-go-runner.ts:1015-1022` and #3225 `DEFAULT_MAX_TURN_DURATION_MS = 10 min`); assistant text is bounded by Anthropic's max output tokens (~4096 for sonnet-4-6). Worst-case in-memory string ≤ ~16KB, dropped at turn boundary. No additional cap needed.
- **R3 (medium):** the cc-dispatcher catch-all at line 927 (`try { await runner.dispatch(...) } catch (err)`) currently does NOT receive errors from `onTextTurnEnd` because that is invoked via `state.events.onTextTurnEnd?.()` inside the runner's own try/catch (`soleur-go-runner.ts:1006-1014`). Mitigation: the runner already wraps `onTextTurnEnd` in `try { ... } catch (err) { reportSilentFallback({ feature: "soleur-go-runner", op: "onTextTurnEnd", ... }) }`. The new helper's failure path additionally calls `reportSilentFallback({ feature: "cc-dispatcher", op: "save-assistant-message-failed", ... })` directly (AC9), so a Supabase-level failure is observable under the dispatcher tag, independent of the runner-level wrapper. Two distinct ops give Sentry filters a clean signal of WHERE the failure originated.
- **R3a (medium, NEW):** the helper is called via `void saveAssistantMessage()` inside `onTextTurnEnd` (a sync callback). The promise is intentionally not awaited — but if Supabase write latency exceeds the runner's idle window or the dispatch's exit, the request could be cancelled. Mitigation: the Supabase write is fire-and-forget against the service-role client; cancellation drops the request silently. The helper's own `reportSilentFallback` runs only after `await`; if the Node process exits before the promise resolves, no breadcrumb is emitted and the assistant row is lost. **Acceptance:** for the dispatch's normal lifecycle (emit `stream_end`, return from dispatch, runner stays alive in the SDK loop), the promise resolves well before any teardown. For abnormal teardown (process kill, runtime crash), the loss is acceptable — same failure mode as the user-message insert at line 763 in the same condition. No change.
- **R4 (low):** historical conversations remain user-only and continue to show the chip on resume. Mitigation: documented in AC12; backfill is unsafe (cost + non-idempotent).
- **R5 (low):** if a future code path re-uses `dispatchSoleurGo` from a non-cc context with a non-cc leader, `leader_id: CC_ROUTER_LEADER_ID` would mis-attribute. Mitigation: today the dispatcher is hard-wired to cc; if that changes, the leader_id is wired from the dispatcher's context already (it's what `onText`/`onTextTurnEnd` use for the WS stream), so the persistence MUST mirror the same value, not be hardcoded.
- **R6 (low, NEW):** the new chat-surface gate (`!historyLoading && !resumedFrom`) could mask a genuine routing-needed state if a future code path emits `session_resumed` for a brand-new (zero-history) conversation. Mitigation: `session_resumed` is only emitted by `ws-handler.ts:778-783` after a confirmed `existing` lookup with an existing `messageCount`. A zero-history `session_resumed` is not a current code path. If introduced, the gate would suppress the chip on a thread that genuinely needs routing — a different bug, but with a clear signal (chip never appears). T5's case 2 documents the chosen failure direction. **Decision:** prefer over-suppressing the chip on resumed threads vs. resurrecting the false-routing UX from this bug. The chip is a soft UX hint, not a load-bearing signal — its absence is recoverable; its false presence destroys trust.

### Test-Compatibility Audit (per deepen-plan Phase 4 sharp edge)

The plan changes:

- **Helper-contract semantic:** new write path inside `cc-dispatcher.dispatchSoleurGo`. No existing helper signature changes.
- **`isClassifying` predicate semantic:** widens the gate (more false → false transitions). Equivalent to `existingPredicate && extraConditions`.

`grep -rn "isClassifying\\b" apps/web-platform/` → references in:

- `apps/web-platform/components/chat/chat-surface.tsx` (definition + 2 render sites).
- `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` line 39 — T1 asserts the chip RENDERS with `messages: [user-only], routeSource: null, workflow.state: idle`. **Verified compatible:** `createWebSocketMock` defaults at `apps/web-platform/test/mocks/use-websocket.ts:47-44` set `historyLoading: false, resumedFrom: null`, so the new gate evaluates `!false && !null === true` and T1 still passes unchanged.

No test asserts the chip RENDERS during `historyLoading=true` or after `resumedFrom !== null` — both states are post-hydration regimes the existing tests do not cover. Adding the gate breaks zero existing tests.

`grep -rn "saveAssistantMessage\\|save-assistant-message-failed" apps/web-platform/` → zero matches. The new symbol does not collide with existing breadcrumbs or helpers.

## Sharp Edges

- **SE1:** The `accumulatedAssistantText` accumulator MUST live on the dispatch invocation scope (closure of `dispatchSoleurGo`), NOT on `getSoleurGoRunner` module scope. The runner is process-singleton; module-scope state would leak text between concurrent dispatches. Wire it as a `let` in `dispatchSoleurGo` and have `onText`/`onTextTurnEnd` close over it.
- **SE2:** `onTextTurnEnd` fires ONCE per `SDKResultMessage` (`soleur-go-runner.ts:1006`). A multi-turn dispatch (e.g., when the runner internally chains turns within a single dispatch) will fire it multiple times. Reset the accumulator inside the helper after the insert, NOT outside, so a second turn within the same dispatch starts clean.
- **SE3:** This plan does NOT bump version, does NOT touch knowledge-base/product/roadmap.md, does NOT add new env vars, does NOT touch Doppler. Pure source-code fix.
- **SE4:** This plan does NOT propose backfilling historical conversations. The cost (re-bill) and idempotency (re-routing may pick a different model output) make it strictly worse than letting old conversations show the chip. Documented in AC12.
- **SE5:** A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with concrete artifact / vector / threshold values (aggregate pattern).

## Implementation Phases

### Phase 1 — RED tests (T1–T5, ≤90 min)

Write failing tests per `cq-write-failing-tests-before`. T1–T3 against the dispatcher; T4 against the api-messages flow; T5 against the chat-surface render. T6 is a sub-case of T5 — make sure both branches of the gate are exercised independently.

### Phase 2 — GREEN: persistence helper (≤45 min)

Add `saveAssistantMessage` to `cc-dispatcher.ts` (or extract to the same shared helper module if a sibling helper already exists; check `agent-prefill-guard.ts` precedent — extracted in #3263). Wire into `onText`/`onTextTurnEnd`. Run T1–T4 → green.

### Phase 3 — GREEN: UI gate (≤15 min)

Tighten `isClassifying` in `chat-surface.tsx`. Run T5/T6 → green.

### Phase 4 — REFACTOR (≤30 min)

If `accumulatedAssistantText` lives well as a closure variable, leave it. If T1–T3 grow brittle, extract a `createAssistantTextAccumulator()` helper. Code-simplicity-reviewer at PR review will challenge any over-engineering here.

### Phase 5 — Verification

Local QA per the reproduction steps in the bug report:

1. Open KB doc with existing answered cc-chat thread (use the screenshot doc if available, else any cc-chat thread).
2. Click "Continue thread".
3. Confirm: banner says "Continuing from <date>"; user message visible; assistant message visible; NO routing chip.
4. Send a new message; confirm a new turn streams in and the new turn's assistant reply also persists (next-resume test).

Capture before/after screenshots in the PR body (the bug ticket already attached the BEFORE screenshot at `/home/jean/Pictures/Screenshots/Screenshot From 2026-05-05 18-28-54.png`).

## References

- PR #3237 — `fix(kb-chat): hydrate prior messages on resume + correct trigger label` — first hydration fix; predates the cc-router path's existence asymmetry from being load-bearing.
- PR #3251 / #3276 — `fix(cc-chat): keep Soleur Concierge visible in routing panel` — surfaced the regression by making the chip text more identifiable.
- PR #3263 — `fix(cc-concierge): drop resume when persisted session ends with assistant` — adjacent fix on the same dispatch path; introduced the `agent-prefill-guard.ts` shared helper pattern this plan can reuse.
- PR #3267 — `fix(kb-chat): close H1/H5 observability gaps for continuing-from regression` — added the Sentry breadcrumbs that will catch any post-fix asymmetry. The `history-fetch-success-empty` breadcrumb (level: warning) will quiet for cc-chat conversations after this fix lands; that's the post-deploy success signal.
- `apps/web-platform/server/agent-runner.ts:1079` — canonical per-turn assistant persistence pattern this plan mirrors.
- `apps/web-platform/server/cc-dispatcher.ts:756-761` — the comment that documented the design decision ("SDK's session-id resume mechanism still owns transcript replay") and silently dropped the `api-messages.ts` hydration use case.
- Constitution / `apps/web-platform/server/observability.ts` — `reportSilentFallback` shape used in AC9.
