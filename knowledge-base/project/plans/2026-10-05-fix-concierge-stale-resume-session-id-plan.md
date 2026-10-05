---
title: "fix(concierge): mid-stream stale-resume never clears session_id — conversation wedges in internal_error retry loop"
type: fix
date: 2026-10-05
slug: fix-concierge-stale-resume-session-id
branch: feat-one-shot-9538-stale-resume-session-id
issue: 9538
closes: 9538
lane: cross-domain
priority: high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(concierge): mid-stream stale-resume never clears session_id — conversation wedges in internal_error retry loop

## Enhancement Summary

**Deepened on:** 2026-10-05
**Mode:** inline deepen pass — the Task/subagent fan-out (skill sections 2–5) is unavailable in this harness; all halt gates (§4.6–4.12) were run mechanically and the research/verification passes were performed inline against the tree.
**Sections enhanced:** Proposed Solution, Implementation Phases, Files to Edit, Acceptance Criteria, Test Scenarios, Dependencies & Risks

### Key Improvements

1. **Shared-guard regression caught and fixed.** The `[]`→drop-resume front-line was first designed as unconditional; deepen verification found `agent-runner.ts` shares `applyPrefillGuard` and its `.catch` replay restores FULL `messages` history on stale resume — an unconditional drop would have silently downgraded legacy recovery to a context-free cold start. Redesigned as caller-gated `dropResumeOnEmptyHistory` (cc opts in; legacy default unchanged).
2. **Test-seam names corrected** to the real exports: `__setCcRunnerForTests` / `__resetDispatcherForTests`.
3. **Test-compatibility narrowed.** The flagged default preserves every existing `agent-prefill-guard.test.ts` assertion (including the multi-arm `contextResetNotice-undefined` test whose empty-history arm stays green); new coverage is additive. `cc-dispatcher-prefill-guard.test.ts` uses field-level arg assertions (`mock.calls[0][0].feature`), so a new optional field breaks nothing.

### New Considerations Discovered

- `context_reset` verified end-to-end: real `WSMessage` variant (`lib/types.ts:452`, `conversationId` required), Zod schema arm (`ws-zod-schemas.ts:451`), client `case` arm (`ws-client.ts:1076`, `chat-state-machine.ts:1823`) — the honesty frame reaches the UI today.
- `warnSilentFallback` (already imported by both target files) emits `logger.warn` + Sentry `level: "warning"` — the established warn-tier counting mechanism (`agent-prefill-guard.ts` `warnSilentFallback(null, …)` precedent), satisfying the issue's "info-level marker, no Sentry error event" ask.
- Both cited rule IDs verified active in `AGENTS.md`; #9541 verified OPEN draft on this branch.
- Inline GDPR posture (trigger: `single-user incident`): no new processing activity — clears one opaque UUID column and retries an existing turn; no new data categories, storage, or transfer; emit sites carry opaque ids only (`userId` auto-hashed at the emit boundary). No findings; no compliance-doc update required.

### Halt-Gate Results

§4.6 User-Brand Impact — PASS (threshold `single-user incident`). §4.7 Observability — PASS (5 fields, literal `expected_output`, allowlisted `grep` verb, no SSH). §4.8 PAT — PASS (no hits). §4.9 UI wireframe — SKIP (no UI files). §4.10 Encryption Posture — SKIP (no new store/connection). §4.11 Guard Contract — SKIP (error-recovery code, not a guard deliverable). §4.12 Scope Check — PASS (one live section; asks verbatim; inferred rows justified).

## Overview

A Concierge (cc-soleur-go) conversation whose persisted `conversations.session_id` points at a Claude Code session that no longer exists wedges permanently. Two resume-failure paths exist and only one clears the stale id: a `runner.dispatch()` construction-time rejection reaches `dispatchSoleurGo`'s catch, which calls `clearCcSessionId` (#3266 R7) — but a dead session that constructs cleanly dies later, inside the SDK message iterator, where `consumeStream`'s catch emits a terminal `internal_error` and never clears the column. The terminal `session_ended` frame disables input; the user's next send re-seeds the same dead `session_id` and fails identically, forever, at zero tokens per attempt.

This plan restores the recover-and-retry behavior the legacy `agent-runner.ts` path already has, at the runner/dispatcher seam, and closes the prefill-guard pass-through that lets the dominant dead-file shape reach the SDK at all.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

Observed live 2026-10-05 (Sentry issue 125216285, conversation `c65763e2-9b9d-4e11-b154-bf003f9e68ac`): three user retries each produced `Claude Code returned an error result: No conversation found with session ID: …` and a terminal `session_ended` (`internal_error`) with `totalCostUsd: 0` — the run dies inside SDK resume before the first model call. Sentry shows at least two distinct dead session ids across 2026-10-01 and 2026-10-05. Any founder whose sandbox/session store is lost (reclaim, reprovision, SDK store corruption) is hard-locked out of continuing that conversation. The workaround (operator clears `conversations.session_id`, or the user starts a new conversation) should not be required.

## Research Reconciliation — Spec vs. Codebase

The issue body's premises were each verified against the tree. One is materially wrong and changes the plan's shape:

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "`consumeStream`'s catch calls `emitWorkflowEnded(internal_error)` + `reportSilentFallback` — but never clears `conversations.session_id`" | Confirmed — `soleur-go-runner.ts` `consumeStream` catch discriminates only `RuntimeAuthError`/`denied_jti` → `session_revoked`; all else → `internal_error` + unconditional `reportSilentFallback`. | Phase 1 adds a sibling discriminator. |
| "The legacy leader path handles this correctly: re-throw → `.catch()` clears `session_id`, loads `messages` history, replays into a fresh session" | Confirmed — `agent-runner.ts` stale-resume branch re-throws on `err.message.includes("No conversation found with session ID")`; the `sendUserMessage` `.catch()` clears via `updateConversationFor({session_id: null})`, then `loadConversationHistory` + `buildReplayPrompt` + `startAgentSession(…, undefined, replayPrompt)`. | Mechanism mirrored; replay half descoped (below). |
| "the prefill guard's history-probe branch + persisted `messages` rows already rebuild context on cold start (this is the R7 design contract)" | **False on both halves.** (a) `applyPrefillGuard` probes the SDK session store via `getSessionMessages(resumeSessionId)` and on `history.length === 0` (the deleted/rotated-file shape) or on probe throw it returns `safeResumeSessionId: args.resumeSessionId` — it *passes `resume:` through*, which is exactly how a dead session reaches `query({resume})` and dies mid-stream. It never rebuilds context. (b) Nothing in the cc path reads `messages` for replay — `git grep` shows `cc-dispatcher.ts` only INSERTs user/assistant rows and SELECTs `workspace_id`/`role`; `loadConversationHistory`/`buildReplayPrompt` are module-private to `agent-runner.ts`. The `cc-dispatcher.ts` dispatch-catch comment "the SDK rebuilds from the persisted `messages` rows" is aspirational and inaccurate. A cold start after clear has **zero** prior-turn context. | Phase 2 closes the `[]` pass-through for the cc caller only (front-line — the guard is shared with legacy `agent-runner`, which keeps pass-through to preserve its `.catch` history replay). The retry emits the existing `context_reset` honesty contract (notice + wire frame) rather than pretending context survived. DB-replay parity descoped to a tracking issue. |
| "Fix-Size: ~60 lines / 3 files" | Roughly accurate for the backstop alone (runner branch + dispatcher wiring + one vitest file). With the guard fix, notice plumbing, and test updates: ~90–130 lines / 6–7 files. | Estimate revised; still a small fix. |
| `#3266 R7` design contract | `knowledge-base/project/plans/2026-05-11-fix-cc-session-id-wiring-plan.md` §R7 confirmed: the mitigation shipped was only the dispatch-time `clearCcSessionId`; the mid-stream gap was named ("the SDK rejects `resume` mid-stream … the bad session_id stays in the DB and the next cold-Query retries the same failure") but left unhandled. | This plan is the deferred half of R7. |

## Research Insights

### Premise Validation (Phase 0.6)

- Cited issue `#9538` OPEN — planning proceeds. Cited `#3266` mechanism verified in tree (`clearCcSessionId`, `onSessionIdPersisted`, `persistCcSessionId`).
- Cited symbols verified: `consumeStream` catch, `emitWorkflowEnded`, `TERMINAL_WORKFLOW_END_STATUSES` (contains `internal_error` → `session_ended`), `clearCcSessionId`, `agent-runner.ts` stale-resume branch and caller `.catch` replay — all present as described.
- ADR corpus: no ADR rejects the recover-and-retry mechanism; the R7 plan explicitly contemplated it.
- Applicable learning: `knowledge-base/project/learnings/2026-04-12-startAgentSession-catch-block-swallows-resume-errors.md` — the legacy sibling of this exact defect; its fix shape (discriminate, don't Sentry, re-throw to a recovery `.catch`) is the precedent this plan adapts to the event-driven runner/dispatcher seam.

### Relevant file paths

- `apps/web-platform/server/soleur-go-runner.ts` — `consumeStream` catch (the fix site), `DispatchEvents` interface (`onStaleResume` added here), `emitWorkflowEnded`/`closeQuery` ordering, `DispatchArgs` (new `contextResetNotice` passthrough).
- `apps/web-platform/server/cc-dispatcher.ts` — `dispatchSoleurGo` `events` wiring (`onWorkflowEnded` at the `TERMINAL_WORKFLOW_END_STATUSES` branch), `clearCcSessionId`, `onSessionIdPersisted?.(null)` precedent, `realSdkQueryFactory` `effectiveSystemPrompt` assembly (existing `contextResetNotice` append site), `hasActiveCcQuery`, `mirrorWithDebounce`, `warnSilentFallback` (already imported).
- `apps/web-platform/server/agent-prefill-guard.ts` — `history.length === 0` pass-through branch (the door the dead file walks through).
- `apps/web-platform/server/agent-runner.ts` — the reference implementation (stale-resume re-throw + `.catch` replay); read-only.
- `apps/web-platform/test/helpers/soleur-go-fixtures.ts` — `createMockQueryScripted`, `makeRecordingEvents`, `flushMicrotasks` for the new test files.
- `apps/web-platform/test/agent-prefill-guard.test.ts`, `apps/web-platform/test/cc-dispatcher-session-id-writer.test.ts` — suites that pin the changed behaviors.

### Property List (mechanism-minimality gate)

- **P1** — A send to a conversation whose `session_id` is dead recovers transparently: one fresh session, no user-visible `internal_error`, no Sentry error-tier event.
- **P2** — The stale `conversations.session_id` is cleared so no subsequent turn re-attempts the same dead id.
- **P3** — Recovery is bounded (at most one re-dispatch per turn) and honest (the user sees the existing `context_reset` contract, not silent amnesia).
- **P4** — Occurrence of the recovery is observable (warn-tier marker) without error-tier paging.
- **P5** — The dominant dead-file shape is prevented from reaching the SDK at all (no crash-and-retry cycle for the common case).

### Cut List (mechanisms considered and cut)

- **New `WorkflowEnd` variant `stale_resume`** — buys "typed recoverable signal" (P1); already covered by an optional `DispatchEvents.onStaleResume` member, which avoids widening the bidirectional `WorkflowEndStatus` wire union (`lib/types.ts` + `_AssertWorkflowEndStatusMatches`), the `ABORT_FLUSH_STATUSES`/`_abortFlushExhaustive` rail, `TERMINAL_WORKFLOW_END_STATUSES`, and `WORKFLOW_END_USER_MESSAGES`. Cut — the union churn buys nothing the optional event doesn't.
- **DB history-replay parity** (extract `loadConversationHistory`/`buildReplayPrompt` from `agent-runner.ts`) — buys fuller "context preserved" (part of P1's transparency); the helpers are module-private, extraction is a separate refactor, and the wedge clears without it. Deferred to a tracking issue; the `context_reset` notice covers honesty (P3).
- **New `ContextResetReason` member** (e.g. `stale-session`) — buys label precision only; `CONTEXT_RESET_REASONS` widening touches the Zod schema, reducer, and `CONTEXT_RESET_COPY` consumers. Reuse `"prefill-guard"` + `CONTEXT_RESET_NOTICE_GENERIC`. Cut.
- **Recursive `dispatchSoleurGo` call for the retry** — would re-persist the user `messages` row, re-mint the tenant client, and re-run ownership/status writes; covered by re-invoking `runner.dispatch` inside the existing closure. Cut.

## Proposed Solution

Two layers, each independently shippable but intended to land together:

**Layer 1 — mid-stream backstop (the issue's core ask).** `consumeStream`'s catch gains a stale-resume discriminator (the same signature the legacy path checks: `err.message.includes("No conversation found with session ID")`, gated on `state.sessionId` being set — i.e. a resume was actually attempted). On match it does NOT emit `internal_error` and does NOT `reportSilentFallback`; it fires a new optional `DispatchEvents.onStaleResume({ deadSessionId })` and closes the query quietly. The dispatcher's `onStaleResume` wiring clears `conversations.session_id` (reusing `clearCcSessionId` + `onSessionIdPersisted?.(null)`), emits the `context_reset` wire frame, and re-dispatches the same turn with `sessionId: undefined` — deferred past `activeQueries.delete` (see Technical Considerations).

**Layer 2 — prefill-guard front-line (caller-gated).** `applyPrefillGuard`'s `history.length === 0` branch currently passes `resume:` through on the theory that "Anthropic accepts empty conversation + new user message" — but `[]` for a known id is the deleted/rotated-file shape, and the SDK then dies mid-stream with exactly this bug's signature. Deepen-pass caught that the guard is **shared**: the legacy `agent-runner.ts` call site (`agent-runner.ts:2078-2102`) consumes the same result and its crash-and-replay `.catch` delivers full `messages`-history replay — an unconditional `[]`→drop would silently downgrade legacy dead-session recovery to a context-free cold start. The drop is therefore gated behind a new optional `dropResumeOnEmptyHistory?: boolean` arg: the cc call site in `realSdkQueryFactory` passes `true` (cc has no replay primitive — the `context_reset` notice is strictly better than a crash cycle); the legacy call site passes nothing and keeps pass-through + `.catch` replay. With the flag, `{ safeResumeSessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC, reason: "prefill-guard" }` prevents the crash entirely for the dominant shape, in-turn, with the notice UX and session self-heal (`onSessionIdCaptured` overwrites the dead id on the first result). Probe-throw stays pass-through on both callers by design (an SDK regression must not silently strand context) and is covered by Layer 1 on cc.

## Implementation Phases

### Phase 1 — Backstop: runner discriminator + dispatcher recovery

1. `soleur-go-runner.ts` — `DispatchEvents`: add optional `onStaleResume?: (info: { deadSessionId: string | null }) => void` with a doc comment in the style of `onSessionIdCaptured` (optional + fire-and-forget; non-cc callers and existing tests ignore it).
2. `soleur-go-runner.ts` — `DispatchArgs` and `QueryFactoryArgs`: add optional `contextResetNotice?: string`, forwarded `dispatch` → `queryFactory` (same plumbing shape as `setBashAutonomous`).
3. `soleur-go-runner.ts` — `consumeStream` catch: compute `isStaleResume` (signature + `state.sessionId` truthy). Inside `if (!state.closed)` add the stale-resume arm before the `RuntimeAuthError`/`else` arms: set `state.closed = true`, fire `events.onStaleResume?.({ deadSessionId: state.sessionId })` inside try/catch (`reportSilentFallback` on a throwing listener), then `closeQuery(state)`. Gate the trailing unconditional `reportSilentFallback(err, { op: "consumeStream" })` on `!isStaleResume`; on the stale arm emit `warnSilentFallback(null, { feature: "soleur-go-runner", op: "stale-resume-recovery", message: "stale resume — cleared session_id and re-dispatching cold", extra: { conversationId, deadSessionId } })` (warn-tier marker for occurrence counting, prefill-guard `warnSilentFallback(null, …)` precedent — NOT error tier).
4. `cc-dispatcher.ts` — `dispatchSoleurGo` `events` block: wire `onStaleResume`. Guard `if (!sessionId) return;` (belt — only fire when this dispatch attempted a resume). Then: `sendToClient(userId, { type: "context_reset", reason: "prefill-guard", conversationId })`; `onSessionIdPersisted?.(null)`; `void clearCcSessionId({ userId, conversationId })`; and schedule the re-dispatch **deferred** (microtask — must land after `closeQuery`'s `activeQueries.delete`, see Technical Considerations) as `runner.dispatch({ …same args, sessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC })` with a `.catch` that mirrors the dispatch-time catch's contract: `mirrorWithDebounce` + generic `sendToClient({ type: "error", message: "Dashboard router is unavailable — try again shortly." })` + `updateConversationFor({ status: "failed" }, { onlyIfStatusIn: ["active"], expectMatch: false })` guarded by `!hasActiveCcQuery(conversationId)`.
5. `cc-dispatcher.ts` — `realSdkQueryFactory`: append `args.contextResetNotice` to `effectiveSystemPrompt` at the same site the prefill-guard notice is appended (`contextResetNotice` from `prefillGuardResult`); import `CONTEXT_RESET_NOTICE_GENERIC` for the dispatcher-side emit.

### Phase 2 — Front-line: prefill guard drops resume on empty history (cc-gated)

1. `agent-prefill-guard.ts` — `ApplyPrefillGuardArgs`: add optional `dropResumeOnEmptyHistory?: boolean` (default `false` → unchanged legacy pass-through).
2. `agent-prefill-guard.ts` — `history.length === 0` branch: keep the `warnSilentFallback` under `op: "prefill-guard-empty-history"`; when `args.dropResumeOnEmptyHistory` return `{ safeResumeSessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC, reason: "prefill-guard" }`, else the existing pass-through. Rewrite the branch comment to state the dead-file premise and why legacy stays pass-through (its `.catch` replay restores full context from `messages`; cc has no replay primitive — the crash cycle is strictly worse).
3. `cc-dispatcher.ts` — `realSdkQueryFactory`'s `applyPrefillGuard` call: pass `dropResumeOnEmptyHistory: true`.

### Phase 3 — Tests (RED first)

1. New `apps/web-platform/test/soleur-go-runner-stale-resume.test.ts` (fixtures: `createMockQueryScripted`, `makeRecordingEvents`, `flushMicrotasks` — mirror `soleur-go-runner-session-revoked.test.ts`):
   - dispatch with `sessionId: "dead-id"` → `mock.emitError(new Error("Claude Code returned an error result: No conversation found with session ID: dead-id"))` → `events.onStaleResume` fired once with `{ deadSessionId: "dead-id" }`; `events._ended` is empty (no `internal_error`); `reportSilentFallback` not invoked for the error (warn marker instead); query closed.
   - same signature with NO `sessionId` on the dispatch → falls through to `internal_error` (guard correctness — no false stale classification).
   - non-stale mid-stream error → `internal_error` + `reportSilentFallback` unchanged (regression).
2. New `apps/web-platform/test/cc-dispatcher-stale-resume.test.ts` (stub runner via the `__setCcRunnerForTests` / `__resetDispatcherForTests` test seams at the bottom of `cc-dispatcher.ts`; the suite shape follows `cc-dispatcher-session-id-writer.test.ts`):
   - fire `onStaleResume` from the wired events → `updateConversationFor` invoked with `{ session_id: null }`; `onSessionIdPersisted` called with `null`; one `context_reset` frame sent; `runner.dispatch` re-invoked with `sessionId: undefined` and `contextResetNotice` set; NO `session_ended` frame.
   - ordering: the deferred re-dispatch observes `activeQueries` already clear (fresh query construction — assert `queryReused === false` or the factory invoked once more).
   - retry-throw path → generic error frame + `status: "failed"` revert.
   - `onStaleResume` fired when `sessionId` was absent → no-op (early return).
3. `apps/web-platform/test/agent-prefill-guard.test.ts` — ADD a case: `getSessionMessages` → `[]` with `dropResumeOnEmptyHistory: true` returns `{ safeResumeSessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC, reason: "prefill-guard" }` and the `prefill-guard-empty-history` warn still fires. The existing `[]`-pass-through tests (`agent-runner` feature tag, no flag) remain valid — the default preserves legacy behavior, so no existing assertion changes.
4. `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — add one assertion that the cc factory invokes `applyPrefillGuard` with `dropResumeOnEmptyHistory: true` (extend the existing `mockApplyPrefillGuard.mock.calls[0][0]` field-access pattern at the "cc-concierge feature tag" test; no exact-object-match assertions exist, so nothing else breaks).

## Technical Considerations

- **Ordering trap (load-bearing).** `emitWorkflowEnded` calls `state.events.onWorkflowEnded(end)` synchronously and only THEN runs `closeQuery(state)` → `activeQueries.delete(conversationId)`. The `onStaleResume` callback fires at the same point in the lifecycle. A synchronous `runner.dispatch` inside the callback would hit `activeQueries.get(conversationId)` on the still-present dying entry and take the `queryReused` path — pushing the user message into a closed input queue, silently lost. The re-dispatch MUST be deferred (microtask or `setTimeout(0)`) so it runs after `closeQuery` completes. This is the single easiest way to write this fix wrong.
- **Retry bound.** The retried dispatch passes `sessionId: undefined` → `resumeSessionId` is undefined → the stale-resume signature cannot re-fire (the SDK is not resuming anything). Combined with `if (!sessionId) return` in the wiring, recovery fires at most once per turn — no loop.
- **Shared `TurnPersistenceState` is safe.** `consumeForAbort` flips `_aborted` only on the `kind: "text"` outcome. A dead resume produces zero assistant text and zero usage (`totalCostUsd: 0`), so the outcome is `"none"`. Because `onStaleResume` bypasses `onWorkflowEnded` entirely, the abort-flush never runs for this path regardless. Do NOT call `state.reset()` — documented as a test seam; production never resets.
- **No re-persistence.** The retry re-invokes `runner.dispatch` only — it does not re-enter `dispatchSoleurGo`, so no duplicate user `messages` INSERT, no second tenant mint, no duplicate `status: "active"` flip.
- **`emitWorkflowEnded` untouched.** The stale arm sets `state.closed = true` and calls `closeQuery(state)` directly rather than routing through `emitWorkflowEnded`, which would fire the terminal `onWorkflowEnded` path. Teardown parity (timers, `query.close()`, `inputQueue.close()`, `onCloseQuery` hook → `handleCcCloseQuery` gate/collector drain) is preserved.
- **`context_reset` honesty.** The `context_reset` frame is emitted before the re-dispatch; the `contextResetNotice` passthrough lands the directive in the retried query's system prompt so the model treats the user's message as standalone rather than confabulating continuity. Reason `"prefill-guard"` is reused — see Cut List.
- **Warm-query unreachable.** The signature can only fire on cold `query({resume})` construction; a warm (`queryReused`) dispatch never re-resumes. The `state.sessionId` truthy gate is sufficient — no `queryReused` check needed inside `consumeStream` (it isn't visible there anyway).
- **Client wire state.** No `stream_end` is emitted on the stale path — the dead turn never produced a stream to end, and the retried turn emits its own stream lifecycle; the `context_reset` frame is the user-visible signal in between.
- **NFR:** none affected (no new perf-sensitive path; one extra query construction only on the failure path).

## User-Brand Impact

- **If this lands broken, the user experiences:** the Concierge chat — a founder whose session store is lost stays wedged in the `internal_error` loop (status quo, no regression), or worse, a recovery bug (missed defer, unbounded retry) loses their message or loops silently.
- **If this leaks, the user's [data / workflow / money] is exposed via:** `deadSessionId`/`conversationId` are opaque UUIDs in warn-tier telemetry (auto-hashed `userId` at the emit boundary per `hashExtraUserId`); no message content, paths, or PII enters the new emit sites — the `context_reset` frame carries no content.
- **Brand-survival threshold:** `single-user incident` (issue-declared; a founder hard-locked out of a conversation is exactly this class).
- **Threshold decision (challengeable):** single-user incident, not aggregate pattern — the blast radius is one conversation at a time, but total for that user (permanent wedge, zero self-serve recovery).

CPO sign-off required at plan time before `soleur:work` begins (headless run — recorded for the pipeline; `soleur:engineering:review:user-impact-reviewer` will be invoked at review time per the review skill's conditional-agent block).

## Observability

```yaml
liveness_signal:
  what: "warn-tier marker `op: \"stale-resume-recovery\"` emitted once per recovery (feature: soleur-go-runner) — the rate of dead-session recoveries"
  cadence: "per-event"
  alert_target: "Sentry warn stream (no page — expected operational behavior); a sustained nonzero rate is the occurrence-counting signal the issue asked for"
  configured_in: "apps/web-platform/server/soleur-go-runner.ts (consumeStream catch stale-resume arm)"
error_reporting:
  destination: "Sentry web-platform via reportSilentFallback / mirrorWithDebounce (existing)"
  fail_loud: "retry-throw path: `mirrorWithDebounce` under op `stale-resume-retry` + generic error frame; non-stale mid-stream errors still report under op `consumeStream`"
failure_modes:
  - mode: "recovery fires but re-dispatch throws (factory failure, BYOK fetch)"
    detection: "in-surface signal: `mirrorWithDebounce` op `stale-resume-retry` Sentry event + generic error frame to the client + `status: failed` revert"
    alert_route: "Sentry (existing dispatch error route)"
  - mode: "stale-resume marker repeats for the same conversationId across turns"
    detection: "in-surface signal: `op: \"stale-resume-recovery\"` warn events grouped by `extra.conversationId` — repeat fires mean `clearCcSessionId` did not land (distinguishes 'clear failed' from 'new dead session')"
    alert_route: "Sentry warn query on the op slug"
  - mode: "signature masks a different mid-stream error"
    detection: "the arm is anchored on the exact SDK substring `No conversation found with session ID` AND `state.sessionId` truthy — any other error still emits `internal_error` + `reportSilentFallback` under op `consumeStream`"
    alert_route: "Sentry (existing)"
logs:
  where: "pino server log (Better Stack ingestion) — `logger.warn` line from warnSilentFallback carries feature/op/extra"
  retention: "platform log retention (unchanged)"
discoverability_test:
  command: "grep -o stale-resume-recovery apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/soleur-go-runner.ts"
  expected_output: "stale-resume-recovery"
```

## Domain Review

**Domains relevant:** engineering

Single-domain backend fix on the Concierge dispatch path. Domain sweep assessment: product = NONE (no UI-surface files in Files to Edit/Create — the mechanical override does not fire; `context_reset` reuses an existing wire type + approved copy); legal/finance/marketing/sales/support/operations = no implications (no new processing activity, no data-model change, no vendor or pricing surface). `soleur:engineering:review:user-impact-reviewer` applies at PR review per the single-user-incident threshold (review-phase agent, not a plan-phase leader).

## Open Code-Review Overlap

Two open `code-review` issues touch planned files:

- **#3243 — arch: decompose cc-dispatcher.ts into focused modules.** Disposition: **acknowledge** — different concern (module decomposition is its own refactor cycle); folding it into a bug fix would balloon scope. Our ~40 lines land inside `dispatchSoleurGo`'s existing events/wiring regions, consistent with the file's current structure.
- **#3242 — review: tool_use WS event lacks raw name field.** Disposition: **acknowledge** — unrelated WS-schema concern touching the same files; needs its own cycle.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "detect the stale-resume signature (`/No conversation found with session ID/` on `err.message`)" | Phase 1 item 3 — runner discriminator in `consumeStream` catch | mapped |
| 2 | "Do NOT emit terminal `internal_error`. Instead, surface a recoverable signal to the dispatcher" | Phase 1 items 1+3 — `DispatchEvents.onStaleResume` + quiet close (no `emitWorkflowEnded`/`internal_error`) | mapped |
| 3 | "clear `conversations.session_id` (reuse `clearCcSessionId` semantics) and re-dispatch the turn with `resumeSessionId = undefined`" | Phase 1 item 4 — dispatcher `onStaleResume` wiring | mapped |
| 4 | "Do NOT `reportSilentFallback` to Sentry on this path … (Optionally emit an info-level marker for occurrence counting)" | Phase 1 item 3 — skip `reportSilentFallback`; `warnSilentFallback` marker under `op: "stale-resume-recovery"` | mapped |
| 5 | "a send to a conversation whose `session_id` is dead recovers transparently — one fresh session, history replayed, no user-visible `internal_error`, and no Sentry error event" | Phases 1–3 + ACs 1–6 — "history replayed" corrected per Research Reconciliation (no replay primitive exists on the cc path; `context_reset` honesty contract + deferred replay-parity issue) | mapped (premise-corrected) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 items 1–4 (runner event + dispatcher recovery) | "surface a recoverable signal to the dispatcher so it can clear `conversations.session_id` (reuse `clearCcSessionId` semantics) and re-dispatch the turn with `resumeSessionId = undefined`" | asked |
| Phase 2 (`agent-prefill-guard.ts` `[]` → drop resume) | — | inferred — justification: the empty-history pass-through is the production door for the dominant dead-file shape (verified `getSessionMessages` `[]` → `safeResumeSessionId` pass-through → mid-stream crash); at `single-user incident` threshold the next-most-likely entry point must not be scoped out |
| `contextResetNotice` passthrough + `context_reset` emit | — | inferred — justification: verified (Research Reconciliation) the cold-start rebuild premise is false; the existing `context_reset` contract is the codebase's sanctioned honesty signal for context loss and the issue's "recovers transparently" ask requires it over silent amnesia |
| Test files + `agent-prefill-guard.test.ts` updates | "vitest case" (Fix-Size line) | asked |
| Retry-throw catch (error frame + failed revert + mirror) | — | inferred — justification: `cq-silent-fallback-must-mirror-to-sentry` and the turn-start `active` flip's revert contract; a failed retry must not silently strand the row `active` |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 7 | Estimated changed lines: ~130
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — `DispatchEvents.onStaleResume` member; `DispatchArgs`/`QueryFactoryArgs` `contextResetNotice` passthrough; `consumeStream` catch stale-resume arm + warn marker + `reportSilentFallback` gate.
- `apps/web-platform/server/cc-dispatcher.ts` — `dispatchSoleurGo` `events.onStaleResume` wiring (guard + `context_reset` + `clearCcSessionId` + `onSessionIdPersisted(null)` + deferred re-dispatch + retry catch); `realSdkQueryFactory` `contextResetNotice` append + `CONTEXT_RESET_NOTICE_GENERIC` import + `dropResumeOnEmptyHistory: true` on its `applyPrefillGuard` call.
- `apps/web-platform/server/agent-prefill-guard.ts` — `ApplyPrefillGuardArgs.dropResumeOnEmptyHistory?: boolean`; `history.length === 0` branch → drop `resume:` + generic notice only when the flag is set (legacy default unchanged).
- `apps/web-platform/test/agent-prefill-guard.test.ts` — add the flagged `[]`→drop case (existing default-path assertions unchanged).
- `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — add the `dropResumeOnEmptyHistory: true` arg assertion on the cc factory call.

## Files to Create

- `apps/web-platform/test/soleur-go-runner-stale-resume.test.ts`
- `apps/web-platform/test/cc-dispatcher-stale-resume.test.ts`

## Acceptance Criteria

- [x] AC1: A mid-stream iterator error matching `No conversation found with session ID` with `state.sessionId` set fires `events.onStaleResume` exactly once with `{ deadSessionId }`, emits no `onWorkflowEnded`/`internal_error`, and does not invoke `reportSilentFallback` for the error (vitest: `soleur-go-runner-stale-resume.test.ts`).
- [x] AC2: The same signature with no `sessionId` on the dispatch still routes to `internal_error` (no false stale classification); a non-stale mid-stream error still emits `internal_error` + `reportSilentFallback` (vitest, same file).
- [x] AC3: Firing `onStaleResume` from the dispatcher's wired events produces: `updateConversationFor` with `{ session_id: null }`, `onSessionIdPersisted` called with `null`, one `context_reset` wire frame, `runner.dispatch` re-invoked with `sessionId: undefined` and `contextResetNotice` set, and zero `session_ended`/`internal_error` frames (vitest: `cc-dispatcher-stale-resume.test.ts`).
- [x] AC4: The re-dispatch is deferred past `activeQueries.delete` — the test asserts the retry constructs a fresh query (`queryReused === false` / factory invoked again), not the dying entry (vitest, same file).
- [x] AC5: Recovery is bounded — `onStaleResume` with `sessionId` absent is a no-op, and the retry passes `sessionId: undefined` so the signature cannot re-fire; a retry dispatch throw produces the generic error frame + `status: "failed"` revert + `mirrorWithDebounce` (vitest, same file).
- [x] AC6: `applyPrefillGuard` with `dropResumeOnEmptyHistory: true` returns `{ safeResumeSessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC, reason: "prefill-guard" }` when `getSessionMessages` resolves `[]` for a known id, with the `prefill-guard-empty-history` warn still emitted; WITHOUT the flag the existing pass-through behavior is preserved (vitest: `agent-prefill-guard.test.ts` + `cc-dispatcher-prefill-guard.test.ts`).
- [x] AC7: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/soleur-go-runner-stale-resume.test.ts test/cc-dispatcher-stale-resume.test.ts test/agent-prefill-guard.test.ts test/cc-dispatcher-prefill-guard.test.ts` green, and the pre-existing `soleur-go-runner*.test.ts` / `cc-dispatcher*.test.ts` suites still pass.

## Test Scenarios

- Given a dispatch with `sessionId: "dead-id"` and a query whose iterator throws `Error("Claude Code returned an error result: No conversation found with session ID: dead-id")` mid-stream, when `consumeStream` catches, then `onStaleResume` fires once with `{ deadSessionId: "dead-id" }`, no `internal_error` WorkflowEnd is emitted, no `reportSilentFallback` error event fires, and the query is closed.
- Given the same error signature on a dispatch without `sessionId`, when the iterator throws, then the catch routes to the unchanged `internal_error` + `reportSilentFallback` path.
- Given `denied_jti` `RuntimeAuthError` mid-stream, when the catch runs, then `session_revoked` still emits (sibling discriminator unaffected).
- Given `onStaleResume` fired on the dispatcher with `sessionId` present, when the handler runs, then the session id is cleared (DB + in-process cache), `context_reset` is emitted, and a deferred `runner.dispatch` re-runs the turn cold.
- Given `onStaleResume` fired when `sessionId` was absent, when the handler runs, then it returns without clearing or re-dispatching.
- Given the deferred re-dispatch itself throws (factory failure), when the retry catch runs, then the client gets the generic error frame, the row reverts to `failed`, and `mirrorWithDebounce` mirrors it.
- Given `getSessionMessages` returns `[]` for a known `resumeSessionId` with `dropResumeOnEmptyHistory: true`, when `applyPrefillGuard` runs, then `resume:` is dropped and the generic context-reset notice/reason are returned; given the same `[]` without the flag (legacy caller), the existing pass-through is preserved.
- End-to-end (manual, deferred to pre-merge QA): a conversation with a dead `session_id` receives a send → user sees the context-reset notice then a normal streamed reply; zero `internal_error`; `conversations.session_id` holds the fresh id afterward.

## Dependencies & Risks

- **R1 — Defer forgotten → message silently lost (highest risk).** Synchronous re-dispatch collides with the dying `activeQueries` entry. Mitigation: Phase 1 item 4 specifies the deferred call; AC4 asserts the retry observes a cleared map. Covered in Technical Considerations.
- **R2 — Signature drift.** The match keys on the SDK's error text. Mitigation: same literal the legacy path and the `error-sanitizer.ts` defense-in-depth pattern already key on; a signature change degrades to the status quo (`internal_error` loop), not a new failure.
- **R3 — `contextResetNotice` plumbing gap.** If the passthrough is dropped, recovery still works but the model sees a bare cold start and may confabulate continuity. Mitigation: AC3 asserts the field reaches `runner.dispatch`; the factory append is one line at the existing notice site.
- **R4 — Guard `[]`→drop widens cold starts (cc only).** On cc, a genuinely-empty live session cold-starts instead of resuming — lossless by definition (empty transcript). The flag is cc-only: legacy `agent-runner` keeps pass-through so its `.catch` stale-resume replay (full `messages` history) still fires — dropping resume there would downgrade context fidelity. Probe-throw pass-through retained on both callers deliberately (SDK regression must not silently strand context; Layer 1 covers the residue on cc).
- **R5 — Retry-failure status revert race.** A concurrent live turn could own the row when the retry fails; mitigated by reusing the `hasActiveCcQuery` + `onlyIfStatusIn: ["active"]` guard shape from the dispatch-time catch.
- **R6 — `context_reset` reuse semantics.** Reason `"prefill-guard"` on a stale-resume is a label approximation; the client copy is generic ("Prior conversation context was reset…"), which is exactly accurate. Union widening rejected (Cut List).
- **Open scope-outs:** DB history-replay parity (extract `loadConversationHistory`/`buildReplayPrompt`) — deferred; file a tracking issue at ship time (`wg-when-deferring-a-capability-create-a`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The `discoverability_test.command` was executed during plan authoring; it exits 1 today (marker absent — the property the PR adds). It contains no `|`, `;`, `&`, `<`, `>`, `$`, or backtick; first token `grep` is on the Check 10 allowlist.
- AC7's typecheck/test invocations use the in-package forms (`cd apps/web-platform && ./node_modules/.bin/…`) — the repo root has no `workspaces` field, so `npm run -w` aborts; `test/**/*.test.ts` matches the vitest `include` glob.
- Every `knowledge-base/` path cited in this plan was verified to exist at write time.

## Non-Goals / Deferred

- **DB `messages` history replay on cold start** (legacy `buildReplayPrompt` parity) — requires exporting/rehoming `agent-runner.ts`-private helpers; separate refactor. Tracking issue to be filed at ship time.
- **New `WorkflowEnd` / `ContextResetReason` union members** — rejected (Cut List).
- **Probe-throw pass-through change in `applyPrefillGuard`** — deliberately retained (R4).
- **ws-handler / `dispatchSoleurGoForConversation` signature changes** — none needed; `sessionId` already flows through.

## References & Research

- Issue: #9538 (fix(concierge): mid-stream stale-resume never clears session_id)
- Prior art: `apps/web-platform/server/agent-runner.ts` stale-resume branch (`err.message.includes("No conversation found with session ID")` re-throw) + `sendUserMessage` `.catch` replay
- R7 design contract: `knowledge-base/project/plans/2026-05-11-fix-cc-session-id-wiring-plan.md` §R7
- Learning: `knowledge-base/project/learnings/2026-04-12-startAgentSession-catch-block-swallows-resume-errors.md`
- Prefill guard: `apps/web-platform/server/agent-prefill-guard.ts` (`applyPrefillGuard`), plan `knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md`
- Draft PR: #9541
