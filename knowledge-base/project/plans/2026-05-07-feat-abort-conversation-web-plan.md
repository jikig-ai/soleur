---
title: Abort Conversation in Web Application
type: feat
date: 2026-05-07
issue: 3448
brainstorm: knowledge-base/project/brainstorms/2026-05-07-abort-conversation-web-brainstorm.md
spec: knowledge-base/project/specs/feat-abort-conversation-web/spec.md
branch: feat-abort-conversation-web
worktree: .worktrees/feat-abort-conversation-web
draft_pr: 3447
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
---

# Plan: Abort Conversation in Web Application

## Overview

Add a user-initiated **Stop** capability to the Soleur Command Center (`apps/web-platform/`) that aborts the current assistant turn, mirrors `Ctrl+C` muscle memory, and leaves the conversation in a clean continuable state. Triggers: Stop button replacing Send during streaming; `Esc` keyboard shortcut.

Two-PR sequence locked in brainstorm: **PR1** = server correctness + DB migration + bundled legal-doc updates; **PR2** = client UI (Stop button + Esc + abort_turn WS message + abort marker). PR1 is independently shippable — it fixes today's silent partial-text discard on the existing tab-close abort path before any new UI lands.

## Problem Statement

Today the only way to interrupt a runaway assistant turn in the web app is to close the tab. That path:

- silently discards `fullText` accumulated by `agent-runner.ts:351` (user paid for tokens, sees nothing),
- marks the entire **conversation** as `failed` even though only the *turn* needed to stop, leaving the user unable to continue without starting a new conversation,
- does not preempt mid-stream — the AbortSignal is checked between SDK message boundaries (`agent-runner.ts:354`), not wired into the SDK `query()` call, so an in-flight tool call or a sub-agent spawned 200ms before close keeps consuming the user's BYOK API key for as long as it runs.

Existing user-facing pain (CCO Phase 0.5 evidence): #2855, #3382, #3044, #3429, #3040, #3335 all describe "stuck conversation" symptoms.

## Research Reconciliation — Spec vs. Codebase

The brainstorm and spec were written against an older snapshot of `agent-runner.ts`. Plan-time grep against current `feat-abort-conversation-web` surfaced four reconciliations that the work skill MUST honor over the spec.

| Spec / Brainstorm Claim | Codebase Reality (verified 2026-05-07) | Plan Response |
|---|---|---|
| `activeSessions` keyed `userId:conversationId` | Keyed `userId:conversationId:leaderId` — multi-leader dispatch (`agent-runner.ts:131-141`). `dispatchToLeaders` (line 1655) spawns parallel per-leader sessions for one conversation turn. | **Stop = broadcast.** User-Stop calls `abortSession(userId, conversationId)` with **no `leaderId`** — the existing prefix-match in lines 159-165 broadcasts to every leader's session for the turn. Single-stream conversations get one abort; multi-leader dispatch gets every leader stopped. This is the only mental model that satisfies G3 (no hidden leader keeps burning BYOK after Stop). |
| `abortSession(userId, conversationId)` takes no reason argument | Already takes `reason?: "disconnected" \| "superseded"` (lines 142-148). | **Add a third reason.** Widen the union to `"disconnected" \| "superseded" \| "user_requested_stop"`. The branch at `agent-runner.ts:401-411` reads `controller.signal.reason` (or the abort error message) to decide turn vs. conversation status. |
| Spec: AbortSignal not wired into SDK `query()` | Confirmed against installed `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:816`: `abortController?: AbortController` is part of the Options object. Hook callbacks and `CanUseTool` receive `signal: AbortSignal`. Verified in this worktree at plan time. | **Wire `abortController: controller`** into the `query({ options })` call in `agent-runner.ts` (around line 204). Source-level signal-propagation behavior to (a) underlying Anthropic HTTP fetch and (b) PreToolUse-launched Bash subprocesses is the SDK's internal concern; the type signature confirms the option is honored. If runtime testing surfaces a propagation gap, file an SDK feature request and add a per-turn wall-clock budget. |
| Spec: persist `fullText` on abort, conversation stays `active` | `saveMessage` (line 377) does NOT have a `status` column today. `messages` table has `{id, conversation_id, role, content, tool_calls, created_at, leader_id}` — no `status`, no `usage`. | **Migration adds three columns.** See Phase 1 below. `tool_calls` jsonb is reused for completed-actions snapshot; `status` and `usage` are net-new. |

## User-Brand Impact

- **If this lands broken, the user experiences:** Stop button click that silently does nothing (turn keeps streaming, BYOK tokens keep consuming) OR Stop click that aborts the visible stream but leaves a hidden leader session (in `dispatchToLeaders` paths) still running for minutes. Either case: the user paid; the user feels they have no agency over their own agents.
- **If this leaks, the user's data/workflow/money is exposed via:** (a) cross-user abort — a forged `abort_turn` payload aborting another user's stream; (b) BYOK token waste from non-broadcast abort that misses hidden leader sessions; (c) partial assistant message persisted under the wrong `userId` (RLS already prevents this, but the plan calls it out for review-time cross-check).
- **Brand-survival threshold:** `single-user incident`. Carried forward from brainstorm Phase 0.1 (user explicitly tagged billing surprise + data loss + cross-tenant leak as in-scope worst outcomes).

`requires_cpo_signoff: true`. CPO sign-off was performed at brainstorm time via Phase 0.5 carry-forward; this plan's framing matches the brainstorm's framing line-for-line. `user-impact-reviewer` will be invoked at PR review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block (mandatory for `single-user incident` threshold).

## Open Code-Review Overlap

9 open code-review issues touch files this plan modifies. All orthogonal — no fold-in:

| File | Issue | Title | Disposition |
|---|---|---|---|
| `agent-runner.ts` | #3392 | PR-B (#3244) deferrals — denied_jti wire-up, etc. | **Acknowledge** — unrelated to abort surface. |
| `agent-runner.ts` | #3343 | case-insensitive `</document>` escape | **Acknowledge** — unrelated. |
| `agent-runner.ts` | #3242 | tool_use WS event lacks raw name field | **Acknowledge with coordination note** — PR2 chip-list should display the raw tool name. If #3242 lands first, PR2 inherits the cleaner shape; if PR2 lands first, it uses today's shape and #3242 becomes a downstream cleanup. |
| `agent-runner.ts` | #2955 | process-local state ADR + startup guard | **Acknowledge** — `activeSessions` is exactly the process-local state called out, but adding new branches inside it doesn't change the issue's scope. |
| `ws-handler.ts` | #3374 | slot_reclaimed WS frame | **Acknowledge** — orthogonal. |
| `ws-handler.ts` | #3372 | tryLedgerDivergenceRecovery tautological | **Acknowledge** — orthogonal. |
| `ws-handler.ts` | #2191 | clearSessionTimers helper + jitter | **Acknowledge** — orthogonal. |
| `ws-client.ts` | #3374 | (same) | **Acknowledge.** |
| `ws-client.ts` | #3280 | useWebSocket history-fetch reducer refactor | **Coordination note** — PR2 adds an `abort()` method to `useWebSocket`. If #3280 lands first, the `abort()` method slots into the new reducer's action types; if PR2 lands first, #3280's refactor inherits one more action. PR2 author MUST verify which lands first and adapt — no fold-in here, but a comment in PR2's description must reference #3280. |
| `lib/types.ts` | #3242 | (same) | **Acknowledge** — same coordination as agent-runner.ts entry. |

## Proposed Solution

### High-level architecture

```
Browser (PR2)                 Server (PR1)                          DB (PR1)
─────────────                 ─────────────                         ──────────
Stop button click ─┐
                   ├── { abort_turn,                                
Esc keystroke   ───┘    conversationId } ──→ ws-handler.handleMessage
                                              ├─ resolve userId from session
                                              │  (NEVER from msg payload — TR4)
                                              └─ abortSession(
                                                   userId,
                                                   conversationId,
                                                   "user_requested_stop"
                                                   /* no leaderId — broadcast */)
                                                   │
                                                   ▼
                                              controller.abort(reason)
                                                   │
                                                   ▼
                                  query({ abortController: controller, ... })
                                  ├─ underlying HTTP fetch aborts (verify at /work)
                                  ├─ hooks/canUseTool receive signal
                                  └─ for await loop hits signal.aborted ─→ break
                                                   │
                                                   ▼
                                  abort branch (agent-runner.ts:~401):
                                  ├─ inspect controller.signal.reason
                                  ├─ if "user_requested_stop":
                                  │    ├─ saveMessage(role=assistant,
                                  │    │              content=fullText,
                                  │    │              status="aborted",
                                  │    │              usage={input,output,cost,
                                  │    │                     completed_actions:[…]})
                                  │    └─ updateConversationStatus(active)  ← turn aborted, conv active
                                  └─ else (disconnected | superseded):
                                       └─ existing path → conversation status=failed
                                                                                    
                                              ws.send({ type: "session_ended",
                                                        reason: "user_aborted" })
                                                   │
                                                   ▼
Browser (PR2):                                                      
  - render abort marker on partial msg                              
  - re-enable chat input                                            
  - keep conversation in history                                    
```

### Key design choices (locked from brainstorm; reconfirmed at plan time)

1. **Stop = turn-level abort, conversation stays active.** Locked at brainstorm Decision 1.
2. **Best-effort cancel + honest disclosure.** Wire `abortController: controller` into SDK `query()`. Surface completed-before-stop side effects in the abort marker. Locked at Decision 2.
3. **Trigger: Stop button + Esc.** Esc-while-typing guard added at plan time (see SpecFlow §1).
4. **Persist partial text + inline cost + completed actions.** Locked at Decision 4.
5. **Bundle T&C §5 + Privacy §4.2 with PR1.** Locked at Decision 5.
6. **Two-PR sequence (Approach B).** Locked at Decision 6.

### Plan-time additions from SpecFlow

The spec-flow-analyzer surfaced 5 critical questions that the plan resolves now (not deferred to /work):

- **Multi-leader Stop semantics:** broadcast (no `leaderId` argument). Cross-references in #Phase 2 below.
- **Tab-close persistence path:** server-resolved in the existing `ws.on("close")` handler at `ws-handler.ts:357-370`, NOT client `beforeunload`. The handler calls `abortSession(userId, conversationId, "disconnected")`; the `disconnected` branch in `agent-runner.ts` will be taught to also persist `fullText` (PR1 G4), but with conversation status remaining `failed` for disconnect (today's behavior preserved for the disconnect case; only `user_requested_stop` keeps the conversation `active`).
- **Esc-while-typing guard:** Esc only triggers abort when (a) the focus is on the chat surface (not the textarea), OR (b) the chat input is empty. Otherwise it falls through to the textarea's default (clear autocomplete, blur). Documented as FR10 refinement.
- **Stopping-state timeout:** client transitions to `stopping` immediately on click and remains there until `session_ended` arrives. If the WebSocket dies before ack, the existing reconnect/error path surfaces normally — no separate `failed_to_stop` state, no safety-net timer. (Cut after plan review: a custom 5s timeout state was speculative for a 5-second cosmetic gap; the existing WS error surface handles real connection failures.)
- **Edit-and-retry interaction with `aborted` rows:** verified at plan time — `ws-handler.ts` has no `edit_message` / `editMessage` handler today. There is no message-edit feature to corrupt. NG5 deferral stands; nothing to audit.

## Implementation Phases

### Phase 1 — PR1: Server correctness + DB migration + legal docs

#### 1.1 DB migration (next available number, expected `040_message_status_aborted.sql`)

Determine the migration number at /work time by `ls apps/web-platform/supabase/migrations/ | sort | tail -3` — collisions on `037_*` and `038_*` exist (per `git ls-files`); `040` is currently free.

```sql
-- 040_message_status_aborted.sql
-- Add status + usage columns to public.messages to support
-- user-initiated abort (G2 honest disclosure, FR4, TR1).
-- Additive only; existing rows default to 'complete'.
-- See plan: knowledge-base/project/plans/2026-05-07-feat-abort-conversation-web-plan.md

alter table public.messages
  add column if not exists status text not null default 'complete'
    check (status in ('complete', 'aborted'));

alter table public.messages
  add column if not exists usage jsonb;

-- usage jsonb shape (documentation; not enforced by check):
-- {
--   "input_tokens": number,
--   "output_tokens": number,
--   "cost_usd": number | null,
--   "completed_actions": [
--     { "tool_name": string, "input_summary": string, "result_summary": string }
--   ]
-- }
```

**Sibling-migration check (per Sharp Edges):** `ls apps/web-platform/supabase/migrations/` and read 2-3 most recent. Migration 037-039 should be inspected for non-transactional DDL constraints; this migration is fully transactional (only `ALTER TABLE ADD COLUMN`).

**RLS:** existing `Users can read own messages` / `Users can insert own messages` policies (lines 79-95 of `001_initial_schema.sql`) cover the new columns automatically — they gate on `conversation_id`, not column shape.

**Backward-compatibility:** `tool_calls jsonb` is reused as the *cumulative* tool-call list during normal streaming. The new `usage.completed_actions` array is the *abort-time* snapshot — used exclusively when `status = 'aborted'`. Plan does NOT migrate existing `tool_calls` data; existing rows keep `status = 'complete'` and the abort-marker UI never reads their `usage` field.

#### 1.2 Server: WS protocol additions (`apps/web-platform/lib/types.ts`)

Add ONE variant to the `WSMessage` union at line 199:

```ts
// Client → server: user-initiated stop
| { type: "abort_turn"; conversationId: string }
```

Verified at plan time: `lib/types.ts:237` defines `| { type: "session_ended"; reason: string }` — `reason` is already free-form `string`. No widening needed; the server emits `reason: "user_aborted"` as a new string value alongside existing values.

#### 1.3 Server: abort reason union + handler

`agent-runner.ts:142-148` — widen the `reason` parameter union:

```ts
export function abortSession(
  userId: string,
  conversationId: string,
  reason?: "disconnected" | "superseded" | "user_requested_stop",
  leaderId?: string,
): void
```

**Three-pattern grep verified safe at plan time** (per AGENTS.md `cq-union-widening-grep-three-patterns`):
- (a) `_exhaustive: never` rails on this field: zero hits. Existing 10 rails (`ws-handler.ts:1641`, `ws-client.ts:265,657`, etc.) discriminate on `msg.type` / `action.type` / `event.type` / `kind` / `cause` — none on the abort `reason` field.
- (b) `reason ===` if-ladder: only one hit (`kb-upload-payload.ts:48`, unrelated KB-upload reason field).
- (c) `?.reason ===` optional-chain: only one hit (`github-read-tools.ts:256`, unrelated GitHub PR review).

Widening is non-breaking.

`ws-handler.ts handleMessage` — add branch (sibling to `chat`/`review_gate_response`):

```ts
case "abort_turn": {
  // userId comes from the authenticated socket session set up
  // earlier in handleMessage (the existing auth resolution path).
  // NEVER from msg.userId — TR4 cross-user invariant.
  abortSession(userId, msg.conversationId, "user_requested_stop");
  // Idempotent: if no session is active, abortSession is a no-op (lines 153-156).
  break;
}
```

`agent-runner.ts:~401-411` — split the abort branch with an explicit single-write guard (per Kieran TR5 finding):

```ts
// Top of the startAgentSession for-await closure (declared once, before the loop):
let messagePersisted = false;

// ... inside the for-await loop ...

if (controller.signal.aborted) {
  const reason = (controller.signal.reason as Error | undefined)?.message ?? "";
  const isUserRequested = reason.includes("user_requested_stop");

  // Persist partial assistant text — fixes today's silent discard (G4).
  // This applies to BOTH user-requested AND disconnected aborts, so
  // closing a tab no longer loses what the user paid for.
  // The `messagePersisted` guard prevents a double-save if a `result`
  // event arrived after abort fired but before we exited the loop.
  if (!messagePersisted && fullText.length > 0) {
    messagePersisted = true;
    await saveMessage(
      userId,
      conversationId,
      "assistant",
      fullText,
      /* tool_calls */ accumulatedToolCalls,
      leaderId,
      /* new args, see 1.4 */
      { status: "aborted", usage: snapshotUsage(/* see 1.5 */) },
    );
  }

  // Conversation status: only user-requested keeps conversation active.
  // Disconnect / superseded keeps today's "failed" semantics so a
  // crashed client doesn't masquerade as a clean continuation.
  await updateConversationStatus(
    userId,
    conversationId,
    isUserRequested ? "active" : "failed",
  );

  // Send session_ended with user_aborted reason if applicable.
  if (isUserRequested) {
    sendToClient(userId, {
      type: "session_ended",
      reason: "user_aborted",
      conversationId,
    });
  }

  break; // exit the for-await SDK stream loop
}
```

#### 1.4 Server: extend `saveMessage` signature (`agent-runner.ts:377`)

Today's signature: `(userId, conversationId, role, content, toolCalls?, leaderId?)`.

Add a 7th optional argument: `meta?: { status?: "complete" | "aborted"; usage?: UsageSnapshot }`. Default `status = 'complete'`, `usage = null`. The insert payload extends accordingly.

This is additive; every existing call site continues to work without change.

The same `messagePersisted` guard is checked in the normal `result`-event branch (set to `true` after `saveMessage(role=assistant, status=complete)`). This keeps both happy-path and abort-path persistence on a single guarded site.

#### 1.5 Server: `usage` snapshot + completed-actions tracking

Inside `startAgentSession`'s for-await loop, accumulate `usage` + `completed_actions` as the SDK yields tool-use events. The SDK's `result` event includes a `usage` block (input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens) — capture incrementally so the abort branch has a value even if `result` is never yielded.

Pseudo:

```ts
let accumulatedUsage = { input_tokens: 0, output_tokens: 0 };
const completedActions: Array<{tool_name: string; input_summary: string; result_summary: string}> = [];

for await (const msg of query({ abortController: controller, ... })) {
  if (controller.signal.aborted) break;
  
  if (msg.type === "tool_use_complete") {  // verify exact event name at /work
    completedActions.push({
      tool_name: msg.toolName,
      input_summary: summarize(msg.input),
      result_summary: summarize(msg.result),
    });
  }
  if (msg.type === "result") {
    accumulatedUsage = msg.usage;
  }
  // ... existing dispatch
}
```

`snapshotUsage()` in 1.3 reads from these closure-scoped accumulators.

#### 1.6 Server: SDK signal wiring (`agent-runner.ts` ~line 204)

Wire the AbortController into the SDK `query()` call. Per Context7 docs (verified 2026-05-07 against `/nothflare/claude-agent-sdk-docs`):

```ts
for await (const message of query({
  abortController: controller,    // NEW — was previously omitted/defaulted
  prompt: ...,
  options: { ... existing options ... },
})) {
  // ...
}
```

**Verified at plan time:** `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:816` declares `abortController?: AbortController` on the Options object. Item (1) — option is honored — is settled at the type level. Items (2)/(3) — propagation to the underlying HTTP fetch and to PreToolUse-launched Bash subprocesses — are SDK internals; if a runtime test at /work time shows a partial gap, document it in the abort marker copy ("partial output and side effects may complete after Stop") AND file a tracking issue for an SDK feature request AND add a per-turn wall-clock budget (e.g., 10 minutes hard ceiling) in `agent-runner.ts` to bound runaway sub-agents on user's BYOK key.

#### 1.7 Server: error message surface (verified — no allowlist change needed)

Verified at plan time: `apps/web-platform/server/error-sanitizer.ts:36` allowlists only the user-facing string `"Your session was disconnected. Please reconnect to continue."` — it does NOT gate the raw `Session aborted: …` strings used inside `controller.abort(new Error(...))`. The brainstorm research's claim that `error-sanitizer.ts` is the gate was stale.

The actual user-facing channel for abort communication is `{ type: "session_ended"; reason: string }` — the abort branch in §1.3 emits `reason: "user_aborted"` directly, never letting the internal `Error.message` reach the client. No `error-sanitizer.ts` edit is needed.

If a future code path WERE to leak a `Session aborted: user_requested_stop` error message through a different channel that touches `error-sanitizer.ts`, that would be a separate fix; this plan does not introduce such a path.

#### 1.8 Server: Sentry observability

Per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`, every degraded path in the abort flow mirrors `logger.error`/`warn` to Sentry:

```ts
import { reportSilentFallback } from "@/server/observability";

// in catch / abort paths:
reportSilentFallback(err, {
  feature: "abort-turn",
  op: "persist-partial-on-abort" | "send-session-ended" | "update-conversation-status",
  extra: { userId, conversationId, reason, hadPartialText: fullText.length > 0 },
});
```

#### 1.9 Server: tests

Test file path: `apps/web-platform/server/__tests__/abort-turn.test.ts` (matching the existing test convention used by sibling files in `apps/web-platform/server/__tests__/`).

- **Unit (Vitest):**
  - `abortSession(userId, conv, "user_requested_stop")` calls `controller.abort` with an Error whose message contains `"user_requested_stop"`.
  - The for-await abort branch reads `signal.reason` and routes to `user_requested_stop` vs `disconnected` correctly.
  - `saveMessage` extended signature persists `status` + `usage` fields.
  - **Cross-user invariant test (TR4) — concrete shape:**
    - Setup: mock `activeSessions` map with two entries (`alice:conv1` and `bob:conv2`); spy on each `controller.abort`.
    - Invoke: simulate `handleMessage` with WS-resolved `userId = "alice"` and a payload `{ type: "abort_turn", conversationId: "conv2", userId: "bob" }` (forged `userId`).
    - Assertions:
      - `expect(aliceAbortSpy).not.toHaveBeenCalled()` (alice's session unaffected — conv2 isn't hers).
      - `expect(bobAbortSpy).not.toHaveBeenCalled()` (forged userId is ignored; the handler reads from auth, not payload).
      - The handler either silently drops or aborts only alice's `conv1` if conversationId resolution falls back to her active session — the plan's accepted behavior is "silent drop" since alice doesn't own conv2.
  - **Multi-leader broadcast — concrete shape:**
    - Setup: seed 3 entries in `activeSessions`: `alice:conv1:cpo`, `alice:conv1:cmo`, `alice:conv1:cto`, each with its own `AbortController` spy.
    - Invoke: `abortSession("alice", "conv1", "user_requested_stop")` (no `leaderId`).
    - Assertions: all three `controller.abort` spies are called exactly once each with reason matching `"user_requested_stop"`.
  - **Idempotency:** call `abortSession` twice in succession; second call is a no-op (no thrown error, no spurious WS frame, no second `saveMessage`).
  - **Race-window:** a `result` event yielded 50ms after `controller.signal.aborted === true` does NOT cause a second `saveMessage` — the `messagePersisted` guard short-circuits both branches.
- **Integration (Vitest + a real Supabase instance via existing test fixtures):**
  - `messages` row persisted with `status = 'aborted'`, `usage` populated, `tool_calls` carries cumulative-stream snapshot.
  - Conversation row's `status` remains `'active'` for `user_requested_stop`; transitions to `'failed'` for `disconnected`.

(Stress-loop test cut on plan-review feedback — a unit test asserting idempotency covers the same property without the CI flakiness.)

#### 1.10 Legal: T&C §5 metered-usage clause

Edit BOTH copies (kept in sync per existing T&C process):
- `docs/legal/terms-and-conditions.md`
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md`

Add a new sub-section under §5 covering:
- (a) Tokens generated before Stop are billed; the discretionary-refund posture from §5.4 still applies.
- (b) Side-effecting tool calls already dispatched are not auto-reversed (cite §AI-Generated Output and §Local System Risks adaptation in `disclaimer.md`).
- (c) Cross-reference Privacy §4.2 (transcript retention) for completeness.

Coordinate with `legal-compliance-auditor` agent — invoke during PR1 review phase (not at /work time). Draft text by `legal-document-generator` agent.

#### 1.11 Legal: Privacy Policy §4.2 transcript entry

Edit BOTH copies:
- `docs/legal/privacy-policy.md`
- `plugins/soleur/docs/pages/legal/privacy-policy.md`

Add to §4.2 Web Platform data inventory:
- "**Conversation transcripts** (including partial assistant outputs from aborted turns)": purpose, retention rules matching existing transcript handling, cross-reference to GDPR Art. 17 erasure rights in §7.

Same agent coordination as 1.10.

### Phase 2 — PR2: Client UI

#### 2.1 Client: `useWebSocket.abort()` method (`apps/web-platform/lib/ws-client.ts`)

Add to the hook's return surface:

```ts
function abort(): void {
  if (!conversationId) return;
  if (wsRef.current?.readyState !== WebSocket.OPEN) return;
  wsRef.current.send(JSON.stringify({ type: "abort_turn", conversationId }));
  // Local optimistic state transition: streaming → stopping.
  // Stays in `stopping` until session_ended arrives or the WS errors —
  // existing reconnect/error path surfaces real connection failures.
  setStreamState("stopping");
}
```

Coordinate with #3280 (history-fetch reducer refactor) — see Open Code-Review Overlap. If #3280 lands first, this `abort()` slots into the new reducer's action types.

`useEffect` cleanup for any keyboard-listener refs (see §2.3) MUST be returned from the effect per AGENTS.md `cq-ref-removal-sweep-cleanup-closures`.

#### 2.2 Client: Stop button on chat surface

`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (and the chat-input component it composes):

- During `streamState === "streaming"`: replace Send button with Stop button.
- During `streamState === "stopping"`: Stop button shows "Stopping…" with a spinner; disabled (no double-click).
- On click: `useWebSocket.abort()`.

Stop button styling: reuse existing button variant from the chat surface (no new design tokens; bounded UI surface — see Skipped specialists).

#### 2.3 Client: `Esc` keyboard shortcut with focus guard

A `useEffect` registers a `keydown` listener on the chat surface (or `document` scoped to chat-page mount):

```ts
useEffect(() => {
  if (streamState !== "streaming" && streamState !== "stopping") return;
  const handler = (e: KeyboardEvent) => {
    if (e.key !== "Escape") return;
    // Esc-while-typing guard (SpecFlow §1):
    // Only abort if focus is NOT on a non-empty textarea.
    const target = document.activeElement;
    if (target instanceof HTMLTextAreaElement && target.value.length > 0) return;
    e.preventDefault();
    abort();
  };
  document.addEventListener("keydown", handler);
  return () => document.removeEventListener("keydown", handler);
}, [streamState, abort]);
```

Cleanup is enforced by the effect's return; no orphan refs.

#### 2.4 Client: Abort marker rendering

When the assistant message has `status === "aborted"`, render:

- The accumulated partial text (already in `content`).
- A `[stopped by user]` chip immediately after the text.
- Token cost: `usage.input_tokens + usage.output_tokens` and `usage.cost_usd` (if BYOK) OR "included in your plan" (if non-BYOK).
- A chip-list of `usage.completed_actions[]`: each chip shows `tool_name` + truncated `input_summary` (e.g., "git push → feat-x"). Hover tooltip shows `result_summary` when present.

Chip-list uses raw tool name from the SDK event (coordinate with #3242 if it lands first).

#### 2.5 Client: tests

- **Unit (Vitest + React Testing Library):**
  - Stop button click invokes `useWebSocket.abort()`.
  - `Esc` keystroke invokes abort when (a) chat surface focused, (b) textarea empty.
  - `Esc` does NOT invoke abort when textarea has content.
  - Double-click safety: second click while `stopping` is a no-op.
  - Abort marker renders partial text + token cost + completed-actions chip-list.
  - `useEffect` cleanup removes the keydown listener.
- **End-to-end (Playwright via `soleur:test-browser`):**
  - User starts a turn → clicks Stop → sees abort marker → sends a follow-up in same conversation.
  - User starts a turn → presses `Esc` → same.
  - User starts a turn → closes tab → returns to conversation → sees abort marker (PR1 server path verified end-to-end).

### Phase 3 — Verification, ship, post-merge

#### 3.1 Pre-merge (PR1)

- [ ] All unit + integration tests pass locally and in CI.
- [ ] Migration applied locally against a fresh DB; existing rows untouched (`SELECT count(*) FROM messages WHERE status = 'complete'` matches pre-migration count).
- [ ] `legal-compliance-auditor` reviewed both T&C §5 and Privacy §4.2 edits.
- [ ] `code-reviewer`, `architecture-strategist`, `kieran-rails-reviewer`, `user-impact-reviewer` (mandatory per `single-user incident` threshold) reviewed the diff.
- [ ] Sentry watchpoint configured for `feature: "abort-turn"` events.

#### 3.2 Post-merge (PR1)

- [ ] Migration deployed to prd Supabase via the existing migration pipeline.
- [ ] 24h Sentry watch: zero unhandled rejections from the abort path.
- [ ] Verify in prd: a tab-close mid-stream now persists partial text (use a test conversation; check `messages.status = 'aborted'` row appears).

#### 3.3 Pre-merge (PR2)

- [ ] All client unit tests pass.
- [ ] `soleur:qa` browser walkthrough: Stop button + Esc both work; abort marker renders.
- [ ] `code-reviewer`, `kieran-rails-reviewer`, `user-impact-reviewer` reviewed.

#### 3.4 Post-merge (PR2)

- [ ] 24h Sentry watch: zero new error classes from `feature: "abort-turn"`.
- [ ] Manual dogfood: verify Stop button + Esc + abort marker on prd.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Single-PR bundled** | Couples legal review (days) with code review (hours); concentrates risk in a single landing window for a user-brand-critical feature. |
| **Three-PR sequence (legal first)** | Legal docs that promise behavior the code doesn't yet deliver is a worse posture than bundling with the server change that delivers it. |
| **Hard rollback of completed side effects** | Rollback can compound the original problem (e.g., reverting a git push that's already been pulled by a teammate). Brand-survival posture: surface what completed, let the user decide. |
| **Cooperative-only abort (no SDK signal wiring)** | Sub-agents spawned 200ms before Stop could run for minutes on user's BYOK key. Brand-survival violation of G3. |
| **Stop blocks until in-flight tool resolves** | A stuck `bun build` makes Stop feel unresponsive — bad UX. Best-effort cancel + honest disclosure is a better fit. |
| **Per-leader Stop UX in the UI** | The existing multi-leader dispatch is a server orchestration detail; the user mental model is "stop my conversation". Broadcast Stop is the single right answer; per-leader Stop would leak orchestration into UX. |

## Acceptance Criteria

### Pre-merge (PR1 — server + DB + legal)

- [ ] Migration `040_message_status_aborted.sql` adds `status text not null default 'complete' check (status in ('complete', 'aborted'))` and `usage jsonb` to `public.messages`. Verified locally against a fresh DB; existing row count unchanged.
- [ ] `WSMessage` union extended with `{ type: "abort_turn"; conversationId: string }` in `apps/web-platform/lib/types.ts`.
- [ ] `ws-handler.ts handleMessage` has an `abort_turn` branch that calls `abortSession(userId, conversationId, "user_requested_stop")` using server-resolved `userId`.
- [ ] `abortSession` reason union widened to include `"user_requested_stop"`.
- [ ] `agent-runner.ts` SDK `query()` call passes `abortController: controller`.
- [ ] Abort branch persists `fullText` as an assistant message with `status = 'aborted'` and a `usage` snapshot when `fullText.length > 0`. Applies to BOTH user-requested AND disconnected aborts.
- [ ] Conversation status logic: `user_requested_stop` → `active`; `disconnected`/`superseded` → `failed`.
- [ ] Sentry mirroring (`reportSilentFallback`) on abort error paths per `cq-silent-fallback-must-mirror-to-sentry`.
- [ ] Cross-user invariant unit test: forged `msg.userId` cannot abort another user's session (concrete shape in §1.9).
- [ ] Multi-leader broadcast unit test: one `abort_turn` aborts every leader session for the conversation (concrete shape in §1.9).
- [ ] Idempotency unit test: second `abort_turn` after settle is a no-op.
- [ ] Race-window unit test: `result` event arriving after abort does not double-save (`messagePersisted` guard).
- [ ] T&C §5 metered-usage / partial-consumption clause merged in BOTH `docs/legal/` and `plugins/soleur/docs/pages/legal/` copies, reviewed by `legal-compliance-auditor`.
- [ ] Privacy §4.2 transcript processing entry merged in BOTH copies, reviewed by `legal-compliance-auditor`.
- [ ] PR body uses `Ref #3448` (NOT `Closes #3448`) — feature is two-PR; close after PR2.
- [ ] `user-impact-reviewer` review approval (mandatory per `single-user incident` threshold).

### Post-merge (PR1)

- [ ] Migration deployed via existing migration pipeline; verified by row-count and column-existence query against prd.
- [ ] 24h Sentry watch: zero unhandled rejections under `feature: "abort-turn"`.
- [ ] Manual prd verification: tab-close during a streaming turn now persists partial assistant text (`messages.status = 'aborted'` row appears in DB).

### Pre-merge (PR2 — client UI)

- [ ] `useWebSocket.abort()` method added; sends `abort_turn` and transitions local state to `stopping`.
- [ ] Stop button replaces Send during `streamState === 'streaming'`. During `stopping`, button shows "Stopping…" and is disabled.
- [ ] `Esc` keystroke invokes abort when chat surface is focused AND (textarea is empty OR not focused). When textarea has content and is focused, Esc does NOT abort.
- [ ] Abort marker renders: partial text, `[stopped by user]` chip, token count, USD cost (or "included in your plan"), and a chip-list of `usage.completed_actions[]`.
- [ ] `useEffect` cleanup removes the keydown listener.
- [ ] Playwright e2e: start turn → Stop → marker → follow-up message; same for `Esc`; same for tab-close (verifies PR1 + PR2 integration).
- [ ] `user-impact-reviewer` review approval.
- [ ] PR body uses `Closes #3448` (this PR completes the feature).

### Post-merge (PR2)

- [ ] 24h Sentry watch: zero new error classes from `feature: "abort-turn"`.
- [ ] Manual dogfood: send a long prompt, click Stop, verify the abort marker renders end-to-end on prd.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a streaming assistant turn, when the user clicks Stop, then within 250ms the UI transitions to `stopping` and within 1s server-side the abort completes; the assistant message is persisted with `status = 'aborted'`.
- Given a streaming turn, when the user presses `Esc` while focus is on the chat surface (not the textarea), then abort fires.
- Given a streaming turn AND the textarea has 10+ characters AND focus is on the textarea, when the user presses `Esc`, then abort does NOT fire (default browser behavior).
- Given an aborted turn, when the user types a follow-up and submits, then the conversation continues normally and the abort marker remains in history.
- Given a `dispatchToLeaders` turn with 3 active leader sessions, when the user clicks Stop, then all 3 leader sessions abort.
- Given an authenticated user A's WebSocket, when a forged `abort_turn` payload claims `userId = B`, then user A's session aborts (or is silently dropped) and user B's session is untouched.

### Regression Tests

- Given a tab-close mid-stream (today's silent-discard path), when the user returns to the conversation, then the partial assistant text is visible with the `[stopped by user]` marker — this fixes the existing bug class without requiring PR2.
- Given a `superseded` abort (a second tab opens), when the first session aborts, then conversation status remains `failed` (today's behavior preserved).

### Edge Cases

- WebSocket dies during streaming → user clicks Stop → WS reconnects 3s later → stream chunks for the now-aborted turn arrive → client suppresses them and marker is already rendered.
- User clicks Stop twice in 50ms → only one `abort_turn` is sent (button disabled after first click via `stopping` state).
- A `result` event arrives 50ms after the abort branch fires → `saveMessage` is NOT called twice (status check guards).

### Integration Verification (for `/soleur:qa`)

- **Browser:** Navigate to `/dashboard/chat/<conversationId>`, send a long prompt, click Stop within 5s, verify abort marker visible with token count > 0.
- **API verify (post-PR1):** `doppler run -c dev -- psql $DATABASE_URL -c "SELECT id, status, usage->'output_tokens' FROM messages WHERE conversation_id = '<id>' ORDER BY created_at DESC LIMIT 1"` expects `status = 'aborted'` and a non-null `output_tokens` value.
- **Cleanup:** existing test-conversation cleanup; no new fixtures.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing, Support
**Source:** Brainstorm Phase 0.5 carry-forward (see `2026-05-07-abort-conversation-web-brainstorm.md` §Domain Assessments).

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** ~80% of plumbing already exists. Plan-time grep surfaced 4 reconciliations (see Research Reconciliation table). Multi-leader dispatch was a brainstorm blind spot — Stop = broadcast resolves it. SDK signal wiring confirmed feasible per Context7.

### Product (CPO)

**Status:** reviewed (carry-forward + plan-time CPO sign-off via `requires_cpo_signoff: true`)
**Assessment:** Stop UX = button + Esc. Brand-survival line: any post-Stop side effect the user did not consent to. Carried forward into User-Brand Impact section.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** T&C §5 metered-usage clause + Privacy §4.2 transcript entry must land in PR1. `legal-compliance-auditor` review at PR1 review time.

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** "Control & trust" message; changelog highlight + short post on PR2 ship; bundle thematically with BYOK/audit-log into a future "You own the loop" pillar. No copywriter needed (no marketing copy in this plan).

### Support (CCO)

**Status:** reviewed (carry-forward)
**Assessment:** Real recurring "stuck conversation" pain (#2855, #3382, #3044, #3429, #3040, #3335). One FAQ entry covers launch documentation needs. Created post-PR2 merge.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial — wireframes deferred with rationale)
**Agents invoked:** spec-flow-analyzer, cpo (carry-forward)
**Skipped specialists:** ux-design-lead — bounded UI surface (Stop button label swap; abort marker chip-list on existing assistant-message bubble); existing chat-surface visual conventions cover all new elements; no novel layout. If review challenges this, run `/soleur:frontend-design` inline.
**Pencil available:** yes (deferred, not invoked)

#### Findings

spec-flow-analyzer surfaced 5 critical questions. All resolved at plan time (see "Plan-time additions from SpecFlow"). No remaining /work-blocking unknowns.

## Sharp Edges

- `## User-Brand Impact` section is filled per template; if any future edit reverts it to placeholder text, `deepen-plan` Phase 4.6 will fail.
- Migration number is `040` AT plan time (sibling check: 037-039 occupied with two `037` and two `038` collisions). At /work time, re-check `ls apps/web-platform/supabase/migrations/ | sort | tail -3` — if `040` was taken by a parallel feature, bump.
- The `abortController` option name is verified against the *installed* `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:816` at plan time. No re-verification needed at /work time.
- The `tool_use_complete` event name in §1.5 is illustrative; verify exact event name at /work time by reading the SDK's TypeScript types (the Context7 docs surface the broad event taxonomy but the exact event names should be cross-checked against installed types before encoding into the for-await switch).
- PR1 body uses `Ref #3448`, NOT `Closes #3448` — auto-close on PR1 merge would prematurely close the issue while PR2 is still pending. PR2 uses `Closes #3448`. Per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`.

## Files to Edit

### Server (PR1)
- `apps/web-platform/lib/types.ts` — add `abort_turn` variant to `WSMessage`
- `apps/web-platform/server/ws-handler.ts` — add `abort_turn` case in `handleMessage`
- `apps/web-platform/server/agent-runner.ts` — widen `abortSession` reason union; wire `abortController` into SDK `query()`; split abort branch (user_requested_stop vs disconnected); persist partial text on abort; extend `saveMessage` signature
- `apps/web-platform/server/error-sanitizer.ts` — allowlist `Session aborted: user_requested_stop`

### Legal (PR1)
- `docs/legal/terms-and-conditions.md` — §5 metered-usage clause
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` — same edit (sync)
- `docs/legal/privacy-policy.md` — §4.2 transcript entry
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — same edit (sync)

### Client (PR2)
- `apps/web-platform/lib/ws-client.ts` — `useWebSocket.abort()` method; add `"stopping"` to the `streamState` machine; coordinate with #3280 reducer refactor.
- `apps/web-platform/components/chat/chat-input.tsx` — Stop button replaces Send during `streamState === "streaming" | "stopping"`.
- `apps/web-platform/components/chat/chat-surface.tsx` — `Esc` keydown listener with focus guard; mounts only while a stream is active.
- `apps/web-platform/components/chat/message-bubble.tsx` — abort marker render path when `message.status === "aborted"`: partial text, `[stopped by user]` chip, token count, USD cost, completed-actions chip-list.
- `apps/web-platform/components/chat/tool-use-chip.tsx` — possibly reused for the completed-actions chip-list (verify shape compatibility at /work time).
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — wire `useWebSocket.abort()` through to the chat-input + chat-surface props.

## Files to Create

### PR1
- `apps/web-platform/supabase/migrations/040_message_status_aborted.sql` — new migration (number subject to /work-time re-check)
- `apps/web-platform/server/__tests__/abort-turn.test.ts` (or sibling location matching existing test conventions) — unit + integration tests for the abort path

### PR2
- `apps/web-platform/components/chat/__tests__/abort-marker.test.tsx` (matching existing component-test convention) — abort marker rendering tests + Esc focus guard
- New component file is not required if `message-bubble.tsx` can render the abort marker inline based on `status === "aborted"` (decided at /work time)

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| SDK `abortController` does not propagate to the underlying HTTP fetch despite type-level support | Low (verified at type level) | High | /work-time runtime probe — start a turn, abort mid-stream, observe whether further chunks arrive after `controller.abort()`. If propagation gap, document in marker copy + per-turn wall-clock budget. |
| Multi-leader Stop semantics confuse users (some leaders abort, others don't) | Low (broadcast is correct) | High | Broadcast is the only behavior; verified at plan time. UI never exposes leader scope to the user. |
| Race between `result` event and abort branch double-saves the message | Medium | Medium | Status check in the abort branch; persistence is idempotent; verified by integration test. |
| Tab-close `beforeunload` is unreliable for client-side persistence | High (default behavior) | Low | We do NOT rely on `beforeunload`; persistence is server-resolved in the existing `ws.on("close")` handler. |
| Abort marker copy under-discloses (CLO transparency risk) | Low | High | `legal-compliance-auditor` reviews the marker copy alongside T&C/Privacy in PR1 review. |
| Stop button + Esc listener leaks (cleanup miss) | Low | Low | AGENTS.md `cq-ref-removal-sweep-cleanup-closures` enforced; `useEffect` returns explicit cleanup. |
| Forged `userId` cross-user abort | Low | Critical | TR4 server-resolved userId; unit test; review-time `user-impact-reviewer` mandatory. |
| Migration number collision (040 taken by parallel feature) | Low | Low | /work-time `ls` re-check; bump if needed. |
| Existing `dispatchToLeaders` paths break under broadcast abort | Low | Medium | Existing prefix-broadcast logic in `abortSession` (lines 159-165) is unchanged; we only add a third `reason` enum value. |

## References

### Internal references
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-abort-conversation-web-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-abort-conversation-web/spec.md`
- Issue: #3448
- Draft PR: #3447

### Code paths (verified 2026-05-07)
- `apps/web-platform/server/agent-runner.ts:131-200` (activeSessions, sessionKey, abortSession, abortAllUserSessions, abortAllSessions)
- `apps/web-platform/server/agent-runner.ts:204-348` (SDK `query()` call site for signal wiring)
- `apps/web-platform/server/agent-runner.ts:354,401-411` (signal.aborted check, abort branch)
- `apps/web-platform/server/agent-runner.ts:377` (saveMessage)
- `apps/web-platform/server/agent-runner.ts:670-1655` (startAgentSession, dispatchToLeaders)
- `apps/web-platform/server/ws-handler.ts:357-370` (existing close = abort path)
- `apps/web-platform/lib/types.ts:199-309` (WSMessage union, MessageState)
- `apps/web-platform/supabase/migrations/001_initial_schema.sql:68-77` (messages table base shape)
- `apps/web-platform/supabase/migrations/010_tag_and_route.sql:14-15` (leader_id added)

### Precedents
- PR #1610 / #1554 (SIGTERM abort path)
- PR #1197 / #1194 (abort before conversation replace)
- PR #922 / #840 (review-gate abort + timeout)
- PR #1989 (XHR abort for uploads)
- PR #2843 (stream_start/stream_end idempotency guards)

### Learnings
- `2026-03-20-review-gate-promise-leak-abort-timeout.md` — manual `setTimeout` + `.unref()` for safety-net timers; allowlist abort messages in `error-sanitizer.ts`
- `2026-03-20-fire-and-forget-promise-catch-handler.md` — wrap every fire-and-forget abort/start promise with `.catch`
- `2026-03-20-websocket-first-message-auth-toctou-race.md` — re-check `ws.readyState` and session-ID equality after every async hop
- `runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md` — null-out before async delete for idempotent cleanup
- `2026-03-02-telegram-streaming-repurpose-status-message.md` — `streamState` field as single source of truth

### External references
- Anthropic Claude Agent SDK Options: `query()` accepts `abortController` (Context7 `/nothflare/claude-agent-sdk-docs`, verified 2026-05-07)
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` (this plan satisfies Phase 2.6)
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` (Sentry mirroring on abort error paths)
- AGENTS.md `cq-ref-removal-sweep-cleanup-closures` (client React cleanup)
- AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` (PR1 `Ref`, PR2 `Closes`)
