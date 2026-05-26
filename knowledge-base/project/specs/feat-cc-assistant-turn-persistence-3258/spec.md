# Feature: cc-soleur-go Transcript Persistence Hardening

## Provenance

- Closes #3603. Supersedes the closed #3258.
- Headline transcript-persistence fix landed in #3286 (merged 2026-05-05). This spec covers the residual hardening pass surfaced by CTO + CPO + CLO under USER_BRAND_CRITICAL framing.
- Brand-survival threshold: **single-user incident**. `/soleur:gdpr-gate` required at plan Phase 2.7, work Phase 2 exit, ship Phase 5.5.
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md`.
- **AC11 verification (Step 0) — PASSED 2026-05-11** via Playwright MCP + Supabase service-role DB query on conversation `36df3694-9f0c-4e1e-905f-c0846b52749e`. Two new residuals surfaced (W8 below; W9 advisory). See `gh issue view 3603` comment dated 2026-05-11 for the full result table.

## Problem Statement

The headline fix in PR #3286 (`saveAssistantMessage` at `cc-dispatcher.ts:1018-1050`, hooked into `onTextTurnEnd` at line 1077) closes the lopsided-transcript symptom going forward, but leaves four residual risks and three follow-up obligations:

1. **Cross-tenant dedup invariants are untested.** A subtle bug in stream-end persistence could surface User A's assistant turn in User B's tab — a GDPR Art. 33/34 notifiable breach at brand-survival threshold. Today there is no two-user matrix test asserting tenant isolation under concurrent load.
2. **Partial assistant text is lost on abort.** `saveAssistantMessage` fires only on `onTextTurnEnd`. If the SDK aborts mid-turn (Stop button, runner runaway, container kill, internal_error), accumulated text never persists. The legacy single-leader path writes `status:"aborted"` rows via migration 040; the cc path does not.
3. ~~**SDK retry can double-render an assistant turn.**~~ **CUT in rev-2** — no SDK retry path exists in code (DHH + Simplicity grep evidence, 2026-05-11). The W2 `workflowEnded` flag covers the related late-onTextTurnEnd-after-abort race more simply than a per-turn latch.
4. **`messages.usage` is null on the cc path** (W4-narrowed). AC11 verification on 2026-05-11 confirmed `messages.status` IS populated on cc rows (`status:"complete"`). The remaining Stage-3 deferral at `cc-dispatcher.ts:1137-1139` is `usage` jsonb only.

8. **Routing preamble leaks into persisted assistant content** (W8, new from AC11 verification). The cc path's `saveAssistantMessage` accumulates every `onText` chunk including hidden router telemetry (e.g., `"Routing to soleur:go — classifying this as a simple connectivity/verification ping."`). The UI filters these chunks live but DB persistence captures them. On reload, hydration renders text the user never saw streamed — a "message changed after reload" trust-class failure (CPO: MEDIUM trust damage, "implies tampering, not loss"). Evidence: assistant row `f511ec09-0960-412f-ae3e-c33d502900c5` in conversation `36df3694-9f0c-4e1e-905f-c0846b52749e` carries both the preamble and the user-visible reply concatenated.
5. **Migration cohort lacks an affordance.** Conversations created between 2026-05-05 (parent PR #3254 merge) and the AC11 verification of #3286 may render with user-only history. CPO + CLO agree that silent rendering of an incomplete transcript is both a brand-trust breach and an Art. 5(1)(a) transparency defect.
6. **Privacy Policy §4.7 + DPD activity #10 do not acknowledge the cc-soleur-go split.** The legal docs describe a single uniform "conversation data" surface; the implementation is now uniform-on-main but the documentation gap remains.
7. **DSAR cohort audit pending.** Any Art. 15 export request issued between 2026-05-05 and AC11 verification was materially incomplete for users with active cc conversations. The audit-log review and supplementary-disclosure preparation are unstarted.

## Goals

- Ship a 3-PR sequence (PR-A engineering, PR-B UX, PR-C legal) that closes each residual.
- Establish a tenant-isolation invariant test that gates every future change to the transcript path.
- Convert the migration cohort gap into a transparent user-facing acknowledgement, not a silent absence.
- Document cc-path persistence parity in the Privacy Policy and Data Protection Disclosure.
- Audit the DSAR-export log for the affected window and prepare supplementary disclosure if any exports occurred.

## Non-Goals

- **Re-litigating approach 1 vs approach 2 from #3258.** Approach 1 already shipped in #3286.
- **Architectural refactor of the runner.** No write-through-buffer module, no new ownership boundary. All changes stay within `dispatchSoleurGo` and adjacent files.
- **Backfill of pre-#3286 conversation history.** SDK session storage for affected cohort conversations has likely expired; recovery is not feasible.
- **UI redesign of the chat surface.** Banner + inline marker only.
- **`/usage` aggregate wiring for cc path.** `cost_update` WS path stays as-is; only `messages.usage` jsonb is populated at stream-end. Aggregate cost reader remains a separate workstream.
- **Adding a UNIQUE DB constraint on `(conversation_id, turn_id)`.** Per DEC8, retry dedup is in-process latch only; surfacing a Postgres error to a user is worse UX than the latch.

## Functional Requirements

### FR1: AC11 prod verification gate (Step 0) — PASSED 2026-05-11

PASSED via Playwright MCP + Supabase service-role DB query on conversation `36df3694-9f0c-4e1e-905f-c0846b52749e`. Both user and assistant rows persisted with matching `conversation_id`; assistant `leader_id=cc_router` (cc-soleur-go path confirmed). `messages.status="complete"` populated on cc path. `messages.usage=null` (W4 deferral confirmed). Two new residuals surfaced during verification: W8 (routing preamble leak into persisted content) and W9 advisory (`conversations.status="failed"` rollup despite per-message success — pending non-abort repro).

### FR2: Cross-tenant matrix test (W1, PR-A)

Synthesized-fixture test (per `cq-test-fixtures-synthesized-only`) constructs two users (A, B) each with two cc conversations (A1, A2, B1, B2), runs concurrent stream-end persistence on all four, and asserts that hydration for each conversation returns only that conversation's rows. Asserts seven invariants enumerated in #3603 W1.

### FR3: Flush-on-abort (W2, PR-A)

`dispatchSoleurGo` flushes any non-empty `accumulatedAssistantText` from `onWorkflowEnded` when the workflow status is non-`completed` (`runner_runaway`, `idle_timeout`, `internal_error`, user-Stop). Flushed row writes `status:"aborted"` and any partial `usage` data available at that point. Container-kill loss is accepted residual; documented in PR-A description.

### ~~FR4: SDK-retry idempotency latch (W3, PR-A)~~ — CUT in rev-2

**Cut per DHH + Simplicity grep evidence (2026-05-11 plan-review):** No SDK retry path exists in `soleur-go-runner.ts` or `cc-dispatcher.ts`. The only retry-adjacent code is a benign client-WS-layer comment about "retry after success" (already idempotent at that layer). W3 protected against a re-emission path that isn't in the codebase. The W2 `workflowEnded` flag in FR3 covers the late-onTextTurnEnd race that Kieran flagged as P0-1 — simpler than a per-turn latch. If SDK retry behavior ever surfaces in the future, file a new workstream then.

### FR5: `usage` parity on cc path (W4-narrowed, PR-A) — rev-2 feature-flagged

`status` is already written: `status:"complete"` on `onTextTurnEnd` (AC11-verified 2026-05-11). FR3 flush path adds `status:"aborted"`. The remaining gap is `usage` jsonb — populate from whatever cost/token data is available at the persistence boundary; if unavailable, write `null` not a placeholder. Removes the Stage-3 deferral comment at `cc-dispatcher.ts:1136-1139`.

**Feature flag (rev-2, per GDPR plan-time audit BLOCK 4 / Art. 13(3)):** Gate W4 behind `CC_PERSIST_USAGE` env-driven boolean. Default `false`. Flips to `true` only after PR-C Privacy Policy §4.7 refresh ships. This ensures the new personal-data category (token counts + cost) is not persisted before user-facing disclosure.

**Race protection (rev-2, per Kieran P0-3 + GDPR BLOCK 2):** `pendingTurnUsage` carries a `turnIndex` tag captured synchronously at `onResult` and validated at `onTextTurnEnd`. A stale `onResult` for a previous turn cannot attach to a later row. Orphan usage (usage captured + content empty on abort) is DROPPED with `usage_orphan_dropped` Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`.

### FR5b: Align persisted assistant content with UI render via replace-not-append (W8, PR-A) — rev-2

`saveAssistantMessage` MUST mirror the UI's REPLACE semantic at `chat-state-machine.ts:477` (`applyStreamEvent` case `"stream"`). The persisted `content` reflects the LATEST `SDKAssistantMessage` emission within a turn — not the concatenation of all emissions. Implementation: change `accumulatedAssistantText += text` to `accumulatedAssistantText = text` in `events.onText` (cc-dispatcher.ts:1054).

**Invariant:** the value of `accumulatedAssistantText` at the instant `onTextTurnEnd` fires is what persists. No reordering, no merge.

**Falsifiable proof:** T-W8-emission-order test asserts that even with reversed SDK emission order, persistence matches UI render (both reflect the LATEST emission). Drift between persistence and UI stays zero regardless of emission ordering.

**Note (rev-2):** This supersedes the filter-by-predicate approach in spec rev-1. The filter approach required a sentinel the SDK doesn't reliably emit (router preamble is model-generated narration, not a structured marker). Replace-not-append guarantees persistence-to-UI parity by construction.

### FR6: Hydration regression test (W4, PR-A)

A test asserts that `api-messages.ts` returns cc-row entries (rows with `leader_id = CC_ROUTER_LEADER_ID`) — guards against a future accidental approach-2-style filter regression.

### FR7: Migration cohort affordance (W5, PR-B)

Inline marker on conversations matching the cohort query renders the user-facing copy: *"Some assistant replies from this conversation weren't captured before [date]. New replies are saved normally."* A "Continue conversation" CTA resumes the SDK session if `conversations.session_id` is still valid. Marker dismissible per-user and sunset 90 days after PR-B merge.

### FR8: Rollout banner (W5, PR-B)

Dismissible banner on the chat surface during PR-A rollout window (30 days from PR-A merge): *"Chat history for older conversations may be incomplete. New conversations save normally."* Banner is suppressed for users with zero affected cohort conversations.

### FR9: Privacy Policy + DPD refresh (W6, PR-C)

`docs/legal/privacy-policy.md` §4.7, §7, §8.1 and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` activity #10 receive a one-sentence acknowledgement that conversation data — including cc-soleur-go assistant turns — is persisted to the database at stream-end under the same retention/cascade-delete rules. Route via `/soleur:legal-generate`; mark draft, route to professional review before merge.

### FR10: DSAR audit (W7, PR-C)

Sentry/audit-log review of Art. 15 export requests issued 2026-05-05 → AC11 verification date. If any cohort user exported, prepare supplementary disclosure: *"a portion of assistant-generated content in cc-soleur-go conversations created after 2026-05-05 was retained in volatile session storage and was not included in your export; that content has since [been persisted / expired and is no longer available]."* Send only if any export actually occurred.

## Technical Requirements

### TR1: Tenant-isolation invariants (W1)

Per CLO assessment:

1. `conversation_id` in WHERE clause of every hydration read; no session-id-only lookup.
2. RLS on `messages` derives access via `messages.conversation_id → conversations.user_id = auth.uid()`. Assert via fixture that bypassing RLS returns zero rows (do not rely on app-layer filtering).
3. Stream-end write derives `conversation_id` + `user_id` from the authenticated WS/HTTP session, not the SDK callback payload.
4. Dedup key is `(conversation_id, turn_id)`, never `turn_id` alone.
5. Hydration never falls back to SDK session content; empty DB result renders empty.
6. Two-user-two-conversation matrix test (FR2).
7. Sentry P0 mirror if `messages.user_id != session.user_id` is ever observed (per `cq-silent-fallback-must-mirror-to-sentry`).

### TR2: Abort-flush wiring (W2)

`onWorkflowEnded` already declared in `soleur-go-runner.ts:DispatchEvents`. Hook into `cc-dispatcher.ts:dispatchSoleurGo`'s `onWorkflowEnded` callback (existing site). If `accumulatedAssistantText` is non-empty and status ≠ `completed`, call `saveAssistantMessage({status:"aborted"})`. Then reset `accumulatedAssistantText`. Cite `agent-runner.ts:2044-2055` as reference contract.

### TR3: Retry latch (W3)

A `Map<string, Set<number>>` keyed by `conversationId` mapping to in-flight turn indices, scoped to the `dispatchSoleurGo` closure. `saveAssistantMessage` checks-and-sets atomically. Latch entries cleared on `onWorkflowEnded`.

### TR4: Schema / migration

No new migration. Existing `messages.status` and `messages.usage` from migration 040 are sufficient. RLS from migration 001 unchanged.

### TR5: Sentry mirror contract

Every save failure (FR3, FR4, FR5) calls `mirrorWithDebounce(err, ctx, userId, errorClass)` per `cc-dispatcher.ts:183-197`. The cross-tenant assertion (TR1.7) bypasses debounce — every observation P0 to Sentry.

### TR6: Cohort detection query (FR7)

```sql
SELECT c.id, c.created_at
FROM conversations c
WHERE c.created_at BETWEEN '2026-05-05'::date AND :ac11_verification_date
  AND c.user_id = :auth_uid
  AND EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id AND m.role = 'user')
  AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id AND m.role = 'assistant')
```

Index coverage: existing `messages (conversation_id, created_at)` from migration 001 covers the EXISTS subqueries. Acceptable runtime even at 10× current user count.

### TR7: GDPR-gate invocations

Per `hr-gdpr-gate-on-regulated-data-surfaces`, `/soleur:gdpr-gate` runs:
- Plan Phase 2.7 (for PR-A and PR-C plans).
- Work Phase 2 exit (for PR-A and PR-C work).
- Ship Phase 5.5 (for PR-A and PR-C ship).

PR-B (migration banner UX) does not touch a regulated-data surface — gate not required.

### TR8: PR sequence

```
Step 0 (operator):    AC11 prod verification on cc/KB-Concierge thread
            │
            ▼
PR-A (engineering, GDPR-gated):
  W1 cross-tenant matrix test
  W2 flush-on-abort
  W3 retry latch
  W4 status/usage parity + hydration regression test
            │
            ▼
PR-B (UX, no gate):
  W5 migration cohort marker
  W5 rollout banner (suppressed if no cohort)
            │
            ▼  (B and C independent; can ship in parallel)
PR-C (legal, gated for W6 surface):
  W6 privacy-policy.md §4.7 + DPD activity #10 refresh
  W7 DSAR audit-log review + supplementary-disclosure prep
```

### TR9: Files touched

- `apps/web-platform/server/cc-dispatcher.ts` (FR3, FR4, FR5).
- `apps/web-platform/server/soleur-go-runner.ts` (verify `DispatchEvents` contract for `onWorkflowEnded` + `onTextTurnEnd` mutual exclusion within a turn).
- `apps/web-platform/server/api-messages.ts` (FR6 regression test only; no production change).
- `apps/web-platform/test/cc-dispatcher.test.ts` (FR2, FR6 tests).
- `apps/web-platform/lib/types.ts` (FR5 type — verify `status` / `usage` already typed).
- `apps/web-platform/components/chat/*` (FR7, FR8 — banner + inline marker).
- `docs/legal/privacy-policy.md` (FR9 §4.7, §7, §8.1).
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (FR9 activity #10).
- `knowledge-base/legal/compliance-posture.md` (post-ship entry citing #3603).

## Acceptance Criteria

- AC1: AC11 verification logged in session learning before PR-A plan starts.
- AC2 (PR-A): Two-user-two-conversation matrix test passes under concurrent load; failure of any of the seven invariants in TR1 fails CI.
- AC3 (PR-A): Forced abort (mock `onWorkflowEnded` with `runner_runaway`) persists a row with `status:"aborted"` and the accumulated partial text.
- AC4 (PR-A): Mocked SDK retry emitting `text` twice produces exactly one inserted row.
- AC5 (PR-A): cc rows hydrate from `api-messages.ts` with `status` and `usage` columns populated; regression test asserts cc rows are NOT filtered.
- AC6 (PR-A): `/soleur:gdpr-gate` passes at plan 2.7, work 2 exit, ship 5.5.
- AC7 (PR-B): Cohort detection query returns expected rows on synthesized fixture; marker renders inline on those conversations; sunset behavior asserted in test.
- AC8 (PR-B): Banner suppressed for users with zero cohort rows.
- AC9 (PR-C): Privacy Policy §4.7 + DPD activity #10 contain the acknowledgement sentence; professional-review sign-off attached to PR.
- AC10 (PR-C): DSAR audit log produced; if any exports occurred in window, supplementary-disclosure draft is in the PR.
