---
date: 2026-05-11 (rev-3: 2026-05-12 PR-A split)
issue: "#3603"
pr: "#3602 (draft, becomes PR-A1)"
branch: feat-cc-assistant-turn-persistence-3258
brand_survival_threshold: single-user incident
gdpr_gate: required (plan 2.7, work 2 exit, ship 5.5)
type: feat
scope: PR-A1 of 4-PR sequence (PR-A split into A1+A2 per implementation-time scope assessment 2026-05-12)
review_revision: rev-3 (PR-A1/PR-A2 split applied during Phase 0 of implementation)
---

# Plan: cc-soleur-go transcript hardening — PR-A1 (engineering, small)

## Summary

**Rev-3 split (2026-05-12):** PR-A as originally planned (4 workstreams) was sized for multi-hour focused implementation. To ship the highest-user-impact fix fastest, PR-A splits into:

- **PR-A1 (this plan):** W2 + W8 — abort flush + replace-not-append. ~50 LOC code + ~4 tests. Shippable in one session.
- **PR-A2 (follow-up):** W4 (feature-flagged usage parity) + W1 (cross-tenant RLS matrix). More complex; needs real Supabase fixture + feature-flag wiring.

Both PRs reference #3603 (umbrella stays open until both ship + PR-B + PR-C). DHH framing "ship the fix, don't perform the fix" drives the split.

| Workstream | Surface | PR |
|---|---|---|
| **W2** | Flush partial assistant text on `onWorkflowEnded` for non-completed statuses + `workflowEnded` flag to prevent late `onTextTurnEnd` double-write | **A1** |
| **W8** (new from AC11) | Align persisted content with UI render via replace-not-append; documented invariant + emission-ordering test | **A1** |
| **W4** (narrowed) | `messages.usage` parity on cc path, feature-flagged behind `CC_PERSIST_USAGE` until PR-C lands | **A2** |
| **W1** | Cross-tenant matrix invariants (7 invariants from CLO brainstorm, all actively tested) | **A2** |

Step 0 (AC11 prod verification) cleared 2026-05-11. PR-B (migration cohort UX) and PR-C (legal refresh) follow in sequence.

## Provenance & rev-2 source

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/spec.md` (revised in lockstep — see "Spec reconciliation" below)
- Umbrella issue: #3603
- AC11 verification: `gh issue view 3603` comment 2026-05-11
- Plan rev-2 incorporates: DHH critique (cut W3, simplify ceremony), Kieran P0-1/P0-2/P0-3 (ordering races), Simplicity (cut W3 + tasks.md + Phase 3 trim), GDPR plan-time audit (W8 contract reconciliation, W4 race, W1 invariant 5 active tests, Privacy Policy gate)

## Why now (unchanged from rev-1)

USER_BRAND_CRITICAL framing locked at brainstorm Phase 0.1. Brand-survival threshold = single-user incident. Cross-tenant invariants (W1) are the highest-blast-radius surface; a dedup bug surfacing User A's assistant turn in User B's tab is a GDPR Art. 33/34 notifiable breach.

W8 is new from AC11 verification — persisted content diverged from live render (UI replaces, server accumulator concatenated).

## Spec reconciliation (rev-2 amendment)

Spec FR5b said "filter SDK router-telemetry chunks before INSERT." Plan §2.4 implements `accumulatedAssistantText = text` (replace-not-append, mirroring UI). These are different contracts. Decision: **adopt replace-not-append**, update spec FR5b in the same commit. Rationale:

- Replace-not-append mirrors the UI's existing REPLACE semantic at `chat-state-machine.ts:477` (in `case "stream":` of `applyStreamEvent`). Persistence matches what the user sees.
- Filter-by-predicate requires a sentinel or pattern the SDK doesn't reliably emit (the `"Routing to soleur:go"` text is model-generated narration, not a structured marker). False positives/negatives are likely.
- Risk: if SDK ever reverses emission order (preamble last instead of first), replace would persist the preamble. Same failure mode as the UI would render — drift stays zero. The W8 test asserts this consistency.

## TDD ordering (mandatory per `cq-write-failing-tests-before`)

RED → GREEN → REFACTOR. Each workstream's RED test precedes its GREEN implementation within the same PR. Tests + implementation in the same commit per DHH (drop the separate RED-commit ceremony).

## Phase 0 — Setup

- [ ] 0.1 Read `apps/web-platform/test/cc-dispatcher.test.ts` (existing T1/T2/T3 assistant-persistence patterns).
- [ ] 0.2 Read `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` (integration test pattern).
- [ ] 0.3 Run baseline: `bun test apps/web-platform/test/cc-dispatcher*` — confirm clean.
- [ ] 0.4 **User-Stop status string resolution** (GDPR NOTE): grep `soleur-go-runner.ts` for all callers of `onWorkflowEnded` and enumerate every `status` value; record in this plan as "Statuses in scope for W2 flush:" list. Without this, T-W2 may miss the user-Stop case.
- [ ] 0.5 **DSAR export query location** (GDPR RECOMMEND): grep for `Art. 15 | dsar | export.*personal | data-export` in `apps/web-platform/server/`. Record file:symbol. If column-listed (not `SELECT *`), document whether `messages.usage` is included; if absent, file follow-up issue (D-DSAR) for PR-C scope.
- [ ] 0.6 **SDK emission-ordering verification** (GDPR BLOCK 1 corollary): read `apps/web-platform/server/soleur-go-runner.ts:1682-1735` (`handleResultMessage`) and document whether `onResult` ordering relative to `onTextTurnEnd` and `onWorkflowEnded` is contractually guaranteed. Add the citation to plan §2.3 inline. If not guaranteed → W4 race fix MUST tag `usage` with `turnIndex` (see Phase 2.3.4).

## Phase 1 — RED + GREEN per workstream (no separate RED-commit)

Each subsection writes the failing test then implements. One commit per workstream, message: `feat(cc-dispatcher): W<N> for #3603 — <one-line>`.

### 1.1 W2: flush-on-abort

**Test (T-W2):** `apps/web-platform/test/cc-dispatcher.test.ts`

- [ ] 1.1.1 Mock SDK emits two `onText` chunks; trigger `onWorkflowEnded` with status `runner_runaway` without firing `onTextTurnEnd`.
- [ ] 1.1.2 Assert one assistant row with `status: "aborted"`, content = concatenation of the two chunks (Note: this is the LAST emission per replace-not-append semantic post-W8; pre-W8 ordering also valid for this test), `leader_id: cc_router`.
- [ ] 1.1.3 Assert accumulator reset post-flush.
- [ ] 1.1.4 Repeat for each non-`completed` `WorkflowEnd` status (Phase 0.4 corrected 2026-05-12 — 6 statuses, NOT 3): `cost_ceiling`, `runner_runaway`, `user_aborted`, `idle_timeout`, `plugin_load_failure`, `internal_error`. **User-Stop is `user_aborted` and IS in scope** — initial Phase 0.4 finding was wrong.
- [ ] 1.1.5 **T-W2.late-text:** after W2 flush, fire `onTextTurnEnd` late (simulating in-flight SDK callback). Assert no second row, no `status: "completed"` overwrite.
- [ ] 1.1.6 Document accepted residuals: SIGKILL (container-kill skips `onWorkflowEnded`) and reaper/closeConversation paths (cc-dispatcher.ts:738 — close Query without firing onWorkflowEnded).

**Implementation:** `apps/web-platform/server/cc-dispatcher.ts`

- [ ] 1.1.7 Add closure state `let workflowEnded = false;` near `accumulatedAssistantText` declaration.
- [ ] 1.1.8 In `events.onWorkflowEnded` (currently ~line 1098): if `accumulatedAssistantText` non-empty AND `end.status !== "completed"`, call `saveAssistantMessageAborted(end)`; then `workflowEnded = true` and reset accumulator.
- [ ] 1.1.9 In `events.onTextTurnEnd` (line 1077): if `workflowEnded === true`, return early (silent — `// silent: turn already written via abort path, late onTextTurnEnd is a no-op`).
- [ ] 1.1.10 New helper `saveAssistantMessageAborted(end: WorkflowEnd)` — mirrors `saveAssistantMessage` shape but writes `status: "aborted"` and populates `usage` ONLY when `accumulatedAssistantText` is non-empty (orphan-usage drop per Kieran P0-2). If `usage` would be orphaned, `reportSilentFallback` with tag `usage_orphan_dropped` per `cq-silent-fallback-must-mirror-to-sentry`.
- [ ] 1.1.11 Reference contract: `apps/web-platform/server/agent-runner.ts:2044-2055` (`writeAbortedAssistant` symbol — legacy abort branch). Match its column shape exactly.

### 1.2 W4: `usage` parity (feature-flagged)

**Feature flag (GDPR BLOCK 4):** `CC_PERSIST_USAGE` env-driven boolean, default `false`. Flips to `true` only after PR-C Privacy Policy §4.7 refresh ships. Without this flag PR-A cannot start persisting new personal-data category before user-facing disclosure (Art. 13(3)).

**Test (T-W4):**

- [ ] 1.2.1 With `CC_PERSIST_USAGE=true`: mock SDK `result` event with known usage payload; after `onTextTurnEnd`, assert row has `messages.usage` populated.
- [ ] 1.2.2 With `CC_PERSIST_USAGE=false` (default): assert `messages.usage = null` regardless of SDK payload.
- [ ] 1.2.3 **T-W4-race** (Kieran P0-3 + GDPR BLOCK 2): synthesize the ordering `onResult(turnN) → onTextTurnEnd(turnN) → onResult(turnN+1 LATE) → onTextTurnEnd(turnN+1)`. Assert turn-N's row has turn-N usage and turn-N+1's row has turn-N+1 usage. NO cross-turn attribution.
- [ ] 1.2.4 **T-W4-orphan:** `onResult` fires (usage captured), `onWorkflowEnded(runner_runaway)` before any text arrived. Assert abort row written with `content = ""` (no row at all per drop-empty contract), usage data DROPPED, Sentry mirror fires once with `usage_orphan_dropped` tag.

**Implementation:**

- [ ] 1.2.5 Capture-and-pass synchronously (no shared mutable closure state):
  ```ts
  events.onResult = (result) => {
    pendingTurnUsage = { turnIndex: currentTurnIndex, totalCostUsd: result.totalCostUsd, ...etc };
  };
  events.onTextTurnEnd = () => {
    const usageSnapshot = pendingTurnUsage?.turnIndex === currentTurnIndex
      ? pendingTurnUsage
      : null;
    pendingTurnUsage = null;  // synchronous clear before async save
    void saveAssistantMessage(usageSnapshot);
    currentTurnIndex++;  // synchronous AFTER the snapshot
  };
  ```
  - The `pendingTurnUsage` carries a `turnIndex` tag — a stale `onResult` arriving for a previous turn cannot attach to a later row.
- [ ] 1.2.6 Remove the Stage-3 deferral comment at `cc-dispatcher.ts:1136-1139`.
- [ ] 1.2.7 Type contract: confirm `Message.usage` in `apps/web-platform/lib/types.ts` is jsonb-compatible. No schema migration (column from migration 040).
- [ ] 1.2.8 In `saveAssistantMessage`, gate on `CC_PERSIST_USAGE`:
  ```ts
  const usageToWrite = process.env.CC_PERSIST_USAGE === "true" ? usageSnapshot : null;
  ```

### 1.3 W8: replace-not-append + emission-ordering invariant

**Test (T-W8):**

- [ ] 1.3.1 Mock SDK emits Msg-1 (preamble) then Msg-2 (answer) within one turn. Assert persisted content = Msg-2 only (matching UI live render).
- [ ] 1.3.2 Capture WS frames sent to client; assert UI receives both `stream` events; assert chat-state-machine REPLACE semantic kept (last one wins).
- [ ] 1.3.3 **T-W8-emission-order** (GDPR BLOCK 1 corollary): mock SDK reversed order — Msg-1 (answer) then Msg-2 (preamble). Assert persisted content = Msg-2 (preamble). Confirms invariant: "persistence mirrors UI's REPLACE — both reflect the LATEST SDK emission, whatever it is." This is the falsifiable proof of the chosen contract.
- [ ] 1.3.4 No fragments of replaced emissions in persisted content.

**Implementation:**

- [ ] 1.3.5 Change `accumulatedAssistantText += text` (line 1054) to `accumulatedAssistantText = text`.
- [ ] 1.3.6 Replace the 6-line accumulator comment at lines 1010-1015 with: `// Holds the LATEST SDKAssistantMessage emission. Mirrors chat-state-machine REPLACE semantic (chat-state-machine.ts:477, applyStreamEvent case "stream"). Invariant: value at onTextTurnEnd fires is what persists; no reordering, no merge. AC11 evidence: #3603 comment 2026-05-11.`

### 1.4 W1: cross-tenant matrix + active hydration injection

**Test (T-W1):**

- [ ] 1.4.1 Synthesize `userA` + `userB` via Supabase admin (`afterAll` teardown deletes both with retry on unique-email collision).
- [ ] 1.4.2 Create four cc conversations: A1, A2 (userA), B1, B2 (userB).
- [ ] 1.4.3 **Concurrency semantics** (GDPR NOTE 7): use `Promise.all` over the four dispatches AND interleave mocked SDK callbacks across them (deliberate cross-fire). Sequential awaits would NOT validate Art. 33/34 evidentiary bar.
- [ ] 1.4.4 Auth-client (not service role) SELECT for userA on conversation_id=A1 returns A1 rows; on conversation_id=B1 returns ZERO rows (RLS enforcement, not app-layer).
- [ ] 1.4.5 All assistant rows carry `leader_id=cc_router`.
- [ ] 1.4.6 **T-W1-invariant5-a** (GDPR BLOCK 3): pre-populate empty `messages` for A1 + populated SDK session for A1. Trigger hydration via `api-messages.ts` handler. Assert empty response. (Today this is empty because hydration doesn't read SDK session — test guards against future regression.)
- [ ] 1.4.7 **T-W1-invariant5-b** (GDPR BLOCK 3): same as 1.4.6 but SDK session tagged with userB's user_id while conversation_id matches userA's A1. Assert hydration returns empty AND a P0 Sentry mirror fires (the `assertWriteScope` boundary check from §1.4.10).
- [ ] 1.4.8 **T-W1-cascade-erasure** (GDPR RECOMMEND): in fixture, write an aborted row with `usage` populated, then DELETE the parent conversation. Assert the aborted row and its `usage` data are gone (FK cascade).

**Implementation:**

- [ ] 1.4.9 Extract `assertWriteScope({dispatchUserId, payloadUserId, dispatchConversationId, payloadConversationId})` helper (Kieran P2-6 + Simplicity #5). Single comparison site, single P0 Sentry mirror site (bypasses `mirrorWithDebounce` per CLO TR1.7; deduped by `(offendingUserId, targetConversationId)` 1-hour TTL Set per Kieran P1-5).
- [ ] 1.4.10 Call `assertWriteScope(...)` at the top of `saveAssistantMessage` AND `saveAssistantMessageAborted`. Both paths derive `dispatchUserId` and `dispatchConversationId` from the dispatch closure (already true today). If SDK callback ever exposes a payload user_id or conversation_id, cross-check; mismatch → P0 mirror + abort write.
- [ ] 1.4.11 Document inline: `// Per CLO 7 invariants (issue #3603 W1) — boundary guard against any future SDK-payload trust regression.`

### 1.5 FR6: hydration regression test (test-only)

DHH flagged this as "coverage theater" — point taken, but the brainstorm explicitly considered "approach 2: exclude cc rows from hydration." A one-line guard against a future re-introduction of that filter is cheap and high-signal. Keep.

- [ ] 1.5.1 Pre-populate one cc row + one legacy row for same conversation. Call `api-messages.ts` handler. Assert both returned.

## Phase 2 — GREEN checkpoint

- [ ] 2.1 Full test suite: `bun test apps/web-platform`. All passing.
- [ ] 2.2 Typecheck: `bun tsc --noEmit`.
- [ ] 2.3 Lint: `bun run lint apps/web-platform/server/cc-dispatcher.ts apps/web-platform/test/cc-dispatcher.test.ts`.
- [ ] 2.4 `/soleur:gdpr-gate` on the diff (work Phase 2 exit per TR7).
- [ ] 2.5 Push.

## Phase 3 — REFACTOR (single-bullet trim per Simplicity)

- [ ] 3.1 Diff self-review for silent-fallback paths (every `if (error)` arm + every `.catch`); document each deliberate silent path with `// silent: <reason>`.
- [ ] 3.2 Update PR #3602 description: AC11 link, container-kill residual, alternatives table, `Refs #3603` (NOT `Closes` — PR-B+PR-C still owed).

## Phase 4 — Pre-merge gates

- [ ] 4.1 `/soleur:review` with cc-dispatcher + test files as primary surfaces.
- [ ] 4.2 `/soleur:qa` against real Supabase dev instance (W1 RLS matrix requires real DB).
- [ ] 4.3 Resolve findings inline per `rf-review-finding-default-fix-inline`.
- [ ] 4.4 `/soleur:preflight`.
- [ ] 4.5 `/soleur:gdpr-gate` final pass (ship Phase 5.5 per TR7).
- [ ] 4.6 Confirm `gh pr checks 3602` all green.
- [ ] 4.7 Mark ready, `gh pr merge 3602 --squash --auto`. #3603 stays OPEN for PR-B+PR-C.

## Alternative Approaches Considered (trimmed to 2)

| Alternative | Why not |
|---|---|
| **W8: persist each SDK emission as its own `messages` row** with per-emission `leader_id` | Bigger scope. Changes hydration shape (multiple bubbles per turn). UI today renders one bubble per `leader_id`-keyed stream (chat-state-machine.ts:460-469 chip-removal + REPLACE); multi-row would expose the preamble bubble. Defer as possible W10. |
| **W2: heartbeat-based SIGKILL detection** | Out of PR-A scope. Requires separate liveness signal + sweeper. Filed as **D1** below. |

## Deferred items (file tracking issues)

- [ ] **D1** Container-kill / SIGKILL flush gap. Heartbeat-based detection. File on Phase 4 close.
- [ ] **D2** Multi-bubble-per-turn UI semantic (W8 alternative). File only if appetite emerges post-PR-A.
- [ ] **D3** `conversations.status="failed"` rollup despite per-message success (AC11 W9 advisory). Repro under non-abort conditions first; file if reproducible.
- [ ] **D-DSAR-art15** (Phase 0.5 finding 2026-05-12): **No Art. 15 DSAR export endpoint exists in code.** Pre-existing gap surfaced during this PR's Phase 0 verification — broader than originally framed. Privacy Policy §8.1 promise apparently fulfilled by manual operator action today. File as separate workstream; Art. 17 cascade delete is wired and works for the new `usage` column.

## Files touched

| File | Purpose |
|---|---|
| `apps/web-platform/server/cc-dispatcher.ts` | W2 abort-flush + workflowEnded flag (1.1.7-1.1.10); W4 capture-and-pass + feature flag (1.2.5-1.2.8); W8 replace-not-append (1.3.5-1.3.6); W1 `assertWriteScope` helper + call sites (1.4.9-1.4.11) |
| `apps/web-platform/test/cc-dispatcher.test.ts` | T-W1 (matrix + invariant 5 + cascade), T-W2 (+ late-text), T-W4 (+ race + orphan), T-W8 (+ emission-order), T-FR6 |
| `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` | Integration coverage for W8 alignment in real-factory flow |

## Files NOT touched

- `apps/web-platform/server/soleur-go-runner.ts` — read for contract; `DispatchEvents` shape unchanged.
- `apps/web-platform/server/api-messages.ts` — no production change; FR6 + W1 invariant-5 tests exercise it.
- `apps/web-platform/server/agent-runner.ts` — read as reference contract (`writeAbortedAssistant` symbol at lines 2044-2055).
- `apps/web-platform/components/chat/*` — UI behavior unchanged; W8 aligns persistence to current UI.
- `apps/web-platform/supabase/migrations/*` — no new migrations. `status`+`usage` from migration 040; RLS from migration 001.

## Acceptance Criteria

- AC1: T-W1 (matrix + invariant 5 + cascade), T-W2 (+ late-text), T-W4 (+ race + orphan), T-W8 (+ emission-order), T-FR6 all pass.
- AC2: Pre-existing T1/T2/T3 still pass.
- AC3: Typecheck + lint clean.
- AC4: `/soleur:gdpr-gate` passes at plan 2.7, work 2 exit, ship 5.5.
- AC5: `/soleur:review` no P0/P1; P2 resolved inline.
- AC6: `/soleur:qa` runs W1 matrix against real Supabase dev.
- AC7: PR description has AC11 link, container-kill residual, alternatives table.
- AC8 (procedural, not CI-checkable): `CC_PERSIST_USAGE=false` is the env default at merge. Flips to `true` only after PR-C Privacy Policy refresh lands.

## Sharp edges

- **chat-state-machine REPLACE vs server APPEND.** W8 fixes the divergence. If a future refactor wants APPEND on the UI side, both sides must change in lockstep. Citation: `chat-state-machine.ts:477` (`applyStreamEvent case "stream"`) and `cc-dispatcher.ts:1054` (`onText` callback after W8).
- **`onWorkflowEnded` fires only on graceful runner shutdown.** SIGKILL leaves partial text in memory. Accepted residual; tracked as D1.
- **`pendingTurnUsage` race protection** depends on the turnIndex tag matching synchronously. If a future refactor moves `currentTurnIndex++` to async timing, the tag invariant breaks. Comment at `onTextTurnEnd` makes this explicit.
- **W1 fixture cleanup uses retry on unique-email collision** in Supabase auth.users. `afterAll` with up to 3 retries per user; if cleanup fails, subsequent runs detect via `select 1 from auth.users where email = ?` and skip creation.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm + plan-time GDPR audit). No fresh leader spawn — per Phase 2.5 brainstorm-carry-forward rule.

### Engineering (CTO) — carry-forward

**Status:** reviewed. **Assessment:** Three brainstorm-time residual risks: Risk 2 (W2 closes), Risk 3 (cut per DHH+Simplicity grep — no SDK retry in code), Risk 4 (mirrorWithDebounce-swallow-UI, residual). Blast radius single-user under existing RLS.

### Product (CPO) — carry-forward

**Status:** reviewed. **Assessment:** Workspace positioning confirms approach-1 choice. W5/W6 are PR-B/PR-C scope. Cross-tenant tests must be tenant-scoped — W1 matches.

### Legal (CLO) — carry-forward + plan-time GDPR audit

**Status:** reviewed (with plan-time amendments). **Assessment:** Seven invariants enumerated in W1; all now actively tested (rev-2 added invariant 5 active injection tests per audit BLOCK 3). `CC_PERSIST_USAGE` feature flag added per audit BLOCK 4 (Art. 13(3) — Privacy Policy refresh must precede new data category persistence). Cascade-delete asserted via T-W1-cascade-erasure. SIGKILL transparency disclosure deferred to PR-B/PR-C user-facing copy (D-disclosure tracking item).

### Product/UX Gate

**Tier:** none. PR-A modifies backend persistence to ALIGN with current UI. No new pages, no new components, no UI changes.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/spec.md` (FR5b reconciled in rev-2)
- AC11 verification: `gh issue view 3603` comment 2026-05-11
- Plan-review record: DHH + Kieran + Simplicity + GDPR-audit synthesis 2026-05-11 (rev-2 source of truth)
- Code anchors (symbol + line):
  - `cc-dispatcher.ts:1016 — accumulatedAssistantText declaration`
  - `cc-dispatcher.ts:1018-1050 — saveAssistantMessage function`
  - `cc-dispatcher.ts:1053-1063 — events.onText callback (W8 target at line 1054)`
  - `cc-dispatcher.ts:1077-1092 — events.onTextTurnEnd callback`
  - `cc-dispatcher.ts:1098+ — events.onWorkflowEnded callback (W2 hook site)`
  - `cc-dispatcher.ts:1136-1139 — onResult Stage-3 deferral comment (W4 removes)`
  - `soleur-go-runner.ts:640-676 — DispatchEvents interface`
  - `soleur-go-runner.ts:1682-1735 — handleResultMessage (ordering reference for W4)`
  - `agent-runner.ts:1841 — saveMessage on result event (legacy contract)`
  - `agent-runner.ts:2044-2055 — writeAbortedAssistant (legacy abort contract)`
  - `chat-state-machine.ts:455-516 — applyStreamEvent case "stream" / case "stream_end"`
  - `supabase/migrations/001_initial_schema.sql:68-98 — messages RLS`
  - `supabase/migrations/040_message_status_aborted.sql — status + usage columns`
