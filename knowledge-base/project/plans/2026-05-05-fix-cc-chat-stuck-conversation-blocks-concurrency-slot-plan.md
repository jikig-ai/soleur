---
title: "fix: stuck-active conversation blocks concurrency slot in Knowledge Base chat"
type: fix
date: 2026-05-05
branch: feat-one-shot-cc-chat-stuck-conversation-blocks-concurrency-slot
classification: user-blocking-prod
requires_cpo_signoff: true
related_brainstorms: []
related_specs: []
related_plans:
  - 2026-04-19-feat-plan-concurrency-enforcement-plan.md
  - 2026-05-04-fix-cc-conversation-limit-archive-plan.md
related_migrations: [029_plan_tier_and_concurrency_slots.sql, 036_release_slot_on_archive.sql]
related_issues:
  - "#3219 (inactivity-sweep slot leak — overlapping concern)"
deepened_on: 2026-05-05
---

# Fix: Stuck-Active Conversation Blocks Concurrency Slot in KB Chat

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** Risks, Acceptance Criteria, Implementation Phases, Sharp Edges, Files to Edit

### Key Improvements

1. **Risk #1 resolved — switch reaper signal from `last_active` to slot heartbeat absence.** Direct code read confirmed `saveMessage` (agent-runner.ts:321-340) does NOT update `last_active`. Only `updateConversationStatus` (line 350) and `cc-dispatcher.ts:518` write `last_active`. A long-running tool-heavy turn that streams partials without status writes would have `last_active` go stale → reaper would falsely reap a live conversation. **New design:** the reaper joins `conversations` against `user_concurrency_slots` and reaps only rows where `status='active'` AND **either** (a) no slot row exists at all, OR (b) the slot's `last_heartbeat_at < now() - 120s`. The slot heartbeat is refreshed every 30s by `ws-handler.ts:1590-1598` for the active conversation — its absence/staleness is the authoritative liveness signal, not `last_active`. This eliminates the false-positive class entirely.

2. **Threshold raised + cadence re-tuned.** Reaper threshold becomes `slot heartbeat ≥ 120s stale` (matches the existing pg_cron sweep threshold in migration 029 line 224). Cadence becomes 60s (matches pg_cron). This converges the two sweep mechanisms onto the same threshold and makes reasoning about "how long does a stuck conversation last" simple: `≤ 120s after last heartbeat`.

3. **Reaper merged with the existing pg_cron sweep — application-layer reaper is the conversation-row finalizer, pg_cron stays as the slot-row finalizer.** The two now compose: pg_cron reclaims orphan slot rows; the new app-layer reaper reclaims orphan conversation rows tied to those slots BEFORE pg_cron deletes them, so slot deletion + status flip happen atomically as a pair. Order matters — see Phase 3 step 2 below.

4. **Catch-block coverage expanded.** Direct trace through agent-runner.ts:1076-1144 shows SIX throw-eligible steps after `saveMessage`: (1) cost RPC `.then` callback (line 1099-1108 — fire-and-forget, no await, can't throw to caller), (2) `usage_update` send (1110-1116 — `sendToClient` can throw on dead WS), (3) `syncPush` await (1120 — internally try/caught but the await itself could be aborted), (4) `stream_end` send (1128 — same throw class as #2), (5) `updateConversationStatus` (1134 — throws on `expectMatch: true` 0-row), (6) `session_ended` send (1140-1143). The catch must wrap from BEFORE line 1079 (so `assistantPersisted=false` is the initial state) to AFTER line 1144.

5. **Self-healing recovery tightened — orphan detection is the slot-row-without-corresponding-conversation case.** Direct read of `acquire_conversation_slot` (migration 029 line 101-166) confirms: lazy sweep at line 129 checks heartbeat staleness, NOT slot-row vs conversation-row consistency. An orphan slot whose conversation was hard-deleted (or whose conversation_id never existed because of a bug) sits forever — heartbeat keeps refreshing IF the WS still has it as `session.conversationId`. Self-heal explicitly checks the `conversation_id NOT IN (SELECT id FROM conversations WHERE user_id = $1)` set.

6. **CFO-class concern surfaced and dismissed.** Reaper writes are bounded: at 60s cadence × ~1k users × ~5% genuinely stuck rate × 1 RPC call = ~50 RPC calls/min steady-state. Each is a single-row keyed UPDATE. Cost is negligible.

### New Considerations Discovered

- **`cc-dispatcher.ts:518` is a parallel status writer** (writes `last_active` + status from a different code path — the `/soleur:go` runner). The catch in agent-runner.ts does NOT cover this path. Filed as a deepen-time concern: the cc-dispatcher path has its own try/catch shape. Verify at work-time whether the same stuck-active class is reachable there. Initial read says no — `updateConversationFor` with `expectMatch: true` either succeeds-or-throws, and the dispatcher's throw-handler at line 736-741 already finalizes ownership. Keep on the radar.
- **The user's WS session may be stuck holding `session.conversationId` of the dead conversation.** When the reaper flips status to `failed` and calls `releaseSlot`, the WS handler's heartbeat (`ws-handler.ts:1596`) will keep firing `touchSlot` for that `(userId, convId)` and getting a 0-row return (touch_conversation_slot returns 0 when slot was deleted). The heartbeat does NOT re-acquire when this happens (concurrency.ts:151 returns `false` but the caller at ws-handler.ts:1596 is `void touchSlot(...)` — return value discarded). So the slot stays freed, but the WS-side `session.conversationId` is now pointing at a dead row. Next user message will hit `expectMatch: true` and throw. **Resolution:** the catch added by AC1 already handles this — sending another message lands the `failed` status update fast. But the user's UX for that one message is bad. Document as Sharp Edge; not blocking.
- **`activeSessions.get(key)?.controller.signal.aborted`** is the in-process abort flag. The reaper's call to `abortSession(userId, id)` at agent-runner.ts:459 (in the inactivity timer) uses this. For the `active` reaper, calling `abortSession` is also correct — it triggers the `controller.signal.aborted` branch at line 1166-1180, which skips the `failed` write because the reaper already wrote it. Order matters: status flip → releaseSlot → abortSession (so the SDK iterator sees the abort and exits).

## Overview

User `jean.deruelle@jikigai.com` (free tier, `effective_cap = 1`) opens a PDF in
the Knowledge Base, clicks **Ask about this document**, and sees:

> Connection Error: Concurrent-conversation limit reached. Archive a completed
> conversation to free a slot.

The Command Center dashboard shows exactly **one** conversation, titled
"can you please summarize this PDF?", stuck in **Executing** status (status
label that maps to `conversations.status = 'active'` per
`apps/web-platform/lib/types.ts:344`) for 10 minutes. The assistant produced a
text response — *"I'm unable to read the PDF in this environment — here's…"* —
which means the message-save path on `result` event in `agent-runner.ts:1079`
did succeed, but the conversation status never transitioned `active →
waiting_for_user` (which happens at `agent-runner.ts:1134`, AFTER the
fire-and-forget cost RPC and the `syncPush` await on line 1120). The slot
acquired at `start_session` time (`ws-handler.ts:886`) is therefore still
held — and because the user's WS session is still alive, the 30-second
heartbeat (`ws-handler.ts:1590-1598`) keeps refreshing
`user_concurrency_slots.last_heartbeat_at`, so the 120-s lazy sweep + 1-min
pg_cron sweep (migration 029, lines 127-131 / 219-225) never reclaim it
either.

The fix has three independent surfaces, in order of decreasing user-blast
radius:

1. **Stop conversations from getting stuck in `active`.** Wrap the
   `result`-branch in `agent-runner.ts:1076-1144` so any throw between
   `saveMessage` (line 1079) and `updateConversationStatus(... ,
   "waiting_for_user")` (line 1134) lands a deterministic terminal state
   (`waiting_for_user` if the assistant text was saved, `failed` otherwise).
   The current `try/catch` boundary fires only on top-level iterator throws
   (line 1165) — exceptions from `syncPush`, `increment_conversation_cost`,
   or `sendToClient` between `saveMessage` and the status update fall through
   the success-branch ordering and leave the row at `active`.
2. **Add a periodic reaper for stuck-active conversations.** The current
   `cleanupOrphanedConversations` (`agent-runner.ts:420`) sweeps `active +
   waiting_for_user` rows older than 5 min, but it runs **only on server
   startup** (`server/index.ts:89`). A long-running deploy or a process that
   doesn't restart for hours leaves stuck rows accumulating + slots leaking.
   Promote the sweep to a periodic timer alongside the existing
   `startInactivityTimer` (`agent-runner.ts:440`), and add an explicit
   `releaseSlot` call in the loop so reclaimed slots free immediately
   instead of waiting for the next pg_cron tick.
3. **Don't deny new sessions silently when the user has zero visible
   active conversations.** Even with #1 + #2 closed, transient bugs and
   future regressions can re-introduce slot leaks. When `acquire_conversation_slot`
   returns `cap_hit` and the user's **visible** active-conversation count
   (status in `("active", "waiting_for_user")`, `archived_at IS NULL`,
   matching current `repo_url`) is **less than the cap**, the cap_hit is a
   ledger-truth divergence — log to Sentry with `feature:
   "concurrency-ledger-divergence"`, force-release any orphaned slots
   whose `conversation_id` is not in the visible set, and retry acquire
   once. This is a self-healing branch, not a primary fix; #1 + #2 are
   the load-bearing fixes.

The user's reported scenario is fixed by **#1 alone** (and confirmed by
manually clearing the stuck row + slot in prod, see Phase 5). #2 + #3 are
defense-in-depth against the broader class.

## Reproduction

1. User on free tier opens a PDF in the Knowledge Base.
2. Click "Ask about this document" → `chat-surface.tsx:257` calls
   `startSession({ resumeByContextPath })`.
3. WS handler receives `start_session` (`ws-handler.ts:842-874`); resume
   lookup by `context_path` finds NO existing thread (first time on this
   PDF) → falls through to deferred-creation path (line 877-955).
4. `acquireSlot(userId, pendingId, cap=1)` succeeds. `session.pending = {
   id: pendingId, … }`. Conversation row inserted at first user message
   with `status: 'active'` (`createConversation`, `ws-handler.ts:439`).
5. User asks "can you please summarize this PDF?". Agent runs via
   `startAgentSession`. Streaming produces a text response. `saveMessage`
   writes the assistant text (`agent-runner.ts:1079`). The response was
   `"I'm unable to read the PDF in this environment — here's…"` — a normal
   completion, not an error.
6. **The stuck-state begins**. Some throw between line 1079 and line 1134
   short-circuits the success branch. Candidate roots:
   - `syncPush` succeeds quickly but the awaited `recordKbSyncHistory`
     inside it errors AFTER it returns (it shouldn't, but `syncPush` is
     wrapped in `try/catch` so it can't bubble — ruled out for this
     specific user but listed for completeness).
   - `sendToClient` (`stream_end` at line 1128) throws synchronously when
     the WS is in `CLOSING` state. The throw propagates out of the
     `result` branch.
   - `updateConversationStatus` (line 1134) throws `expectMatch: true`
     when the row was concurrently archived — but per `036_release_slot_on_archive.sql`
     the archive trigger fires AFTER UPDATE, not before, so the row exists.
     Still, a 0-row write here would throw on `expectMatch: true` (see
     line 360-364 of agent-runner.ts).
   - The Node process is killed (SIGKILL, OOM, deploy) between line 1079
     and line 1134.
7. Whatever the immediate cause: the row stays at `status='active'` and
   the slot stays held. The 30-s WS ping keeps heartbeating the slot
   (line 1590-1598) — heartbeat is keyed on `session.conversationId`,
   which the WS handler set at `start_session`. The slot is therefore
   immortal until the WS session closes.
8. User clicks "Ask about this document" again on a DIFFERENT PDF (or the
   same PDF after a tab reload that clears `session.conversationId`):
   `start_session` resume lookup misses (different context_path or
   archived state), falls through to `pendingId = randomUUID()`,
   `acquireSlot` returns `cap_hit` (slot count = 1, cap = 1, new pending
   would be slot 2). WS closes with code 4010, banner reads
   "Concurrent-conversation limit reached".

## User-Brand Impact

**If this lands broken, the user experiences:** complete inability to start
new conversations from the Knowledge Base "Ask about this document" entry
point — and from any other entry point — after a single transient failure
during a previous turn. The Command Center sidebar shows ONE active
conversation that the user perceives as "running forever" (badge:
"Executing" for 10+ min); archiving it works around the problem (the
prior PR #3219-precursor trigger releases the slot on archive), but the
user has no way to know archive is the recovery action — the error
message says "Archive a completed conversation" and the conversation is
NOT in a "completed" state from the user's POV.

**If this leaks, the user's workflow is exposed via:** N/A — this is a
liveness/availability bug, not a confidentiality bug. No cross-tenant
data crosses any boundary.

**Brand-survival threshold:** `single-user incident`. Soleur's positioning
is the agent platform for solo founders; a free-tier prospect who hits
this on the first PDF interaction in their evaluation churns. Free-tier
cap = 1 means a SINGLE stuck conversation locks the user out — there is
no headroom. CPO sign-off required (per
`hr-weigh-every-decision-against-target-user-impact`).
`user-impact-reviewer` will be invoked at PR review.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Stuck-active prevention.** The `result`-branch in
      `agent-runner.ts` (currently lines 1076-1144) is wrapped in a
      `try { … } catch (e) { /* finalize state */ throw e; }` block such
      that any throw between `saveMessage` (line 1079) and
      `updateConversationStatus(..., "waiting_for_user")` (line 1134)
      forces the row to either `waiting_for_user` (if `saveMessage`
      succeeded — assistant text was persisted) or `failed` (if not),
      AND calls `releaseSlot(userId, conversationId)` directly. Use a
      tri-state: `assistantPersisted` boolean flips to `true` after
      line 1079; the catch consults it. The catch does NOT swallow the
      error after finalization — it re-throws so the outer `catch` at
      line 1165 still runs (it currently sends `error` to client).
- [x] **AC2 — Periodic stuck-active reaper, signal = slot-heartbeat absence.**
      A new periodic timer (`startStuckActiveReaper`) runs every 60s and
      finalizes any conversation in `status='active'` whose corresponding
      `user_concurrency_slots` row either does not exist or has
      `last_heartbeat_at < now() - 120s`. **Critical:** the signal is
      slot-heartbeat staleness, NOT `conversations.last_active` —
      `last_active` is updated only by `updateConversationStatus`
      (agent-runner.ts:350) and by `cc-dispatcher.ts:518`, so a long
      tool-heavy turn that streams partials without status writes would
      have stale `last_active` and be falsely reaped. Slot heartbeats
      are refreshed every 30s by `ws-handler.ts:1596` for the active
      conversation; their staleness is the authoritative liveness signal.
      The new timer:
      - SELECTs stuck rows via a SQL helper (Phase 3 step 2 sketches the
        query) joining `conversations LEFT JOIN user_concurrency_slots`
        on `(user_id, conversation_id)`, filter
        `conversations.status = 'active'` AND
        `(slots.id IS NULL OR slots.last_heartbeat_at < now() - 120s)`.
      - Updates rows to `failed` and selects `id, user_id`.
      - For every reclaimed pair, calls `releaseSlot(userId, id)` so any
        still-present orphan slot row frees immediately. Idempotent if
        the row already gone.
      - Calls `abortSession(userId, id)` for in-memory cleanup (matches
        the existing `startInactivityTimer` pattern, line 459). Order:
        status flip → releaseSlot → abortSession.
      - Separate from `startInactivityTimer` (which targets
        `waiting_for_user` at 2h cadence — different status, different
        cadence, different threshold; do NOT merge).
      - 60s cadence converges with the pg_cron `user_concurrency_slots_sweep`
        cadence (migration 029 line 219-225) so the two sweep
        mechanisms agree on a single 120s liveness threshold.
- [x] **AC3 — Server startup wires the new timer.**
      `apps/web-platform/server/index.ts` calls `startStuckActiveReaper()`
      (alongside the existing `startInactivityTimer()` at line 89-92)
      AFTER the one-shot `cleanupOrphanedConversations` startup call.
      `.unref()` is applied so it does not block process exit (matches
      the existing pattern in `startInactivityTimer`).
- [x] **AC4 — Self-healing cap_hit retry (defense-in-depth).** When
      `acquireSlot` in `ws-handler.ts:886` returns `cap_hit`, BEFORE
      emitting `concurrency_cap_hit` telemetry and closing the WS, run
      a *ledger-divergence* check:
      1. Count the user's *visible* active conversations:
         `select count(*) from public.conversations where user_id = $1
         and archived_at is null and status in ('active','waiting_for_user')`.
      2. If `visible_count < cap`, the slot ledger has at least one
         orphan. Read the slot table for this user, compare slot
         `conversation_id` against the visible set, force-release any
         slot whose `conversation_id` is NOT in the visible set
         (= orphan slot for an archived/failed/non-existent conversation).
      3. Mirror the divergence to Sentry via `reportSilentFallback` with
         `feature: "concurrency-ledger-divergence"`,
         `op: "start_session-recovery"`, extra:
         `{ userId, visibleCount, slotCount, orphanCount }`.
      4. Retry `acquireSlot` once. If it still returns `cap_hit`, fall
         through to the existing `concurrency_cap_hit` telemetry +
         WS-close path (no behavior change in the genuine cap_hit case).
      The retry MUST NOT log to Sentry on the recovered case (success
      path noise) — only on the divergence detection itself.
- [x] **AC5 — Periodic-reaper test.** Vitest in
      `apps/web-platform/test/agent-runner-stuck-active-reaper.test.ts`:
      seed 3 stuck `active` conversations (one ≥ 5 min old, two recent);
      run the reaper once; assert only the old one transitioned to
      `failed`, `releaseSlot` was called for it, and the recent two
      are unchanged. Mock `setInterval` so the test does not depend on
      real wall-clock.
- [x] **AC6 — Stuck-active prevention test.** Vitest in
      `apps/web-platform/test/agent-runner-result-branch-finalization.test.ts`:
      mock the SDK iterator to emit `result` then throw before line 1134.
      Assert: `updateConversationStatus(..., "waiting_for_user")` was
      called exactly once (or `"failed"` if the throw lands before
      `saveMessage`), AND `releaseSlot` was called exactly once. The
      test must use the existing test-double pattern from
      `apps/web-platform/test/agent-runner-*.test.ts`.
- [x] **AC7 — Self-healing cap_hit test.** Vitest in
      `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts`:
      seed user with cap=1 and a slot referencing a `conversation_id`
      that does NOT exist in `conversations` (orphan slot). Simulate
      `start_session`. Assert: divergence detected, orphan slot
      released, retry succeeds, `session_started` emitted. Negative case:
      slot references a real `active` conversation → no recovery, cap_hit
      proceeds.
- [x] **AC8 — All tests pass locally.** Test runner verified via
      `apps/web-platform/package.json scripts.test = "vitest"` (deepen
      pass). Run from `apps/web-platform/`:
      `bun run test agent-runner-stuck-active-reaper agent-runner-result-branch-finalization ws-handler-cap-hit-self-heal`
      OR equivalent vitest CLI form.
- [x] **AC9 — `tsc --noEmit` clean.**
- [x] **AC10 — No new AGENTS.md rules.** Discoverability exit applies.
      The bug surfaced as a hard 4010 close + visible "Executing" badge
      stuck for 10 min. A learning file at
      `knowledge-base/project/learnings/bug-fixes/<topic>.md`
      (date picked at write time per `cq-pg-…` discipline) MUST document
      the gap (status transition is the LAST step in the success branch;
      anything that throws between the message save and the status update
      leaves the row at `active`).
- [ ] **AC11 — PR body cites tracking issue.** Use `Closes #<N>` for the
      tracking issue filed in Phase 6. Reference `#3219` (inactivity-sweep
      slot leak) with `Ref #3219` — that issue is overlapping but
      independent (waiting_for_user-class, 2-hour cadence).
- [x] **AC12 — User-brand impact section above is filled** (not `TBD` /
      `TODO` / placeholder), per `deepen-plan` Phase 4.6.

### Post-merge (operator)

- [ ] **AC13a — Apply migration 037 to prod Supabase.** Per
      `hr-menu-option-ack-not-prod-write-auth`: show the exact command,
      wait for explicit per-command go-ahead, then run:
      `supabase db push --db-url "$(doppler secrets get SUPABASE_DB_URL -p soleur -c prd --plain)"`.
      The migration is forward-only and read-only at the RPC level
      (RPC body is a SELECT join). Applying it BEFORE the deploy is
      safe (the new RPC is unused by the existing code). Applying
      AFTER the deploy is also safe (the reaper handles "RPC not
      found" via the `error` branch in
      `find_stuck_active_conversations` call). Recommended order:
      migration first, then deploy.
- [ ] **AC13b — Manual prod cleanup for the affected user.** Before
      the reaper's first tick, free the user's stuck conversation by
      explicit operator action (one of):
      1. Read-only verify in prod: `psql … -c "select id, status,
         last_active, archived_at from public.conversations where
         user_id = '<jean.deruelle user_id>' and status = 'active' order
         by last_active desc limit 5"`.
      2. Destructive write (per `hr-menu-option-ack-not-prod-write-auth`):
         show the exact UPDATE + DELETE pair, wait for explicit
         per-command go-ahead, then run:
         `update public.conversations set status='failed' where id='<stuck-id>'
          and user_id='<userId>';`
         `select public.release_conversation_slot('<userId>', '<stuck-id>');`
- [ ] **AC14 — Prod verification.** After the migration-free deploy
      lands, monitor Sentry for new
      `feature: "concurrency-ledger-divergence"` events for 24 h. If the
      rate is non-zero, the self-healing branch is firing — investigate
      the slot-leak class.
- [ ] **AC15 — Reach out to user** (`jean.deruelle@jikigai.com`) to
      confirm "Ask about this document" works after the deploy lands.

## Files to Edit

- `apps/web-platform/supabase/migrations/037_stuck_active_finder_rpc.sql`
  *(new — SECURITY DEFINER RPC `find_stuck_active_conversations` that
  joins conversations × user_concurrency_slots; pinned `search_path =
  public, pg_temp`; `language sql`)*
- `apps/web-platform/server/agent-runner.ts` *(edit — wrap result branch
  catch in success path + add `startStuckActiveReaper`)*
- `apps/web-platform/server/ws-handler.ts` *(edit — add ledger-divergence
  recovery branch in `start_session` cap_hit path; add
  `tryLedgerDivergenceRecovery` helper)*
- `apps/web-platform/server/index.ts` *(edit — wire the new periodic
  reaper alongside `startInactivityTimer()`)*
- `apps/web-platform/test/agent-runner-stuck-active-reaper.test.ts` *(new)*
- `apps/web-platform/test/agent-runner-result-branch-finalization.test.ts` *(new)*
- `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts` *(new)*
- `knowledge-base/project/learnings/bug-fixes/<topic>.md` *(new — topic
  suggestion: `cc-stuck-active-conversation-leaks-slot`; date picked at
  write time)*

**Files NOT edited (intentional):**

- `apps/web-platform/supabase/migrations/` — **no new migration**. The
  fix is application-layer because the slot-release contract is already
  in place (migration 036's `release_slot_on_archive` trigger).
  Database-layer enforcement of "release slot when status transitions
  out of `active`" was rejected at PR #2954 deepen because
  `resume_session` does not call `acquireSlot` and a slot-release-on-completed
  trigger would let a resumed conversation run outside the ledger
  (Risk #5 of the prior plan).
- `apps/web-platform/hooks/use-conversations.ts` — no change. The hook's
  archive path is already covered by the migration-036 trigger.
- The `release_conversation_slot` RPC itself — no signature change. The
  trigger and the new code paths all call the same DELETE-keyed contract.

## Implementation Phases

### Phase 1 — Stuck-Active Prevention (RED)

**Test first** per `cq-write-failing-tests-before`.

1. Write `apps/web-platform/test/agent-runner-result-branch-finalization.test.ts`:
   - Test 1: `result`-emit followed by a throw from `sendToClient`
     (mocked to throw on `stream_end`). Assert
     `updateConversationStatus(..., "waiting_for_user")` was called
     once, `releaseSlot` was called once, the original error
     propagates.
   - Test 2: `result`-emit followed by `updateConversationStatus`
     throwing (e.g., `expectMatch: true` on a 0-row result). Assert
     `releaseSlot` was called even though the status update failed;
     status is *attempted* to be set to `"waiting_for_user"`; the
     subsequent `failed` write at line 1173 is the catch-fallback.
   - Test 3: positive case — clean `result`-emit, no throws. Assert
     existing behavior is unchanged: status →`waiting_for_user`,
     `releaseSlot` is NOT called (the slot stays held — the conversation
     is alive and waiting; release happens on archive or close).
2. Tests fail against current code.

### Phase 2 — Stuck-Active Prevention (GREEN)

1. In `agent-runner.ts`, wrap the `result`-branch body (lines 1076-1144)
   in a `try { … } catch (resultBranchErr) { /* finalize then rethrow */ }`.
2. Inside the catch, branch on a fresh `assistantPersisted` boolean:
   - Set the boolean `true` immediately after line 1079 succeeds
     (`saveMessage` resolved).
   - On error: if `assistantPersisted`, attempt `updateConversationStatus(..., "waiting_for_user")`
     in a `.catch(() => updateConversationStatus(..., "failed"))` chain
     (so a status-update failure cascades to `failed`); else
     `updateConversationStatus(..., "failed")` directly.
   - Always: `await releaseSlot(userId, conversationId)` (best-effort —
     `releaseSlot` already swallows errors per concurrency.ts:158-181).
   - Re-throw `resultBranchErr` so the outer catch at line 1165 still
     runs (sends `error` to client, logs, etc.).
3. Verify Phase 1 tests pass.

### Phase 3 — Periodic Stuck-Active Reaper (RED → GREEN)

1. Write `apps/web-platform/test/agent-runner-stuck-active-reaper.test.ts`:
   - Seed: (a) `active` row with NO slot row (orphan-by-missing-slot —
     the most common case; covers process-killed-mid-stream); (b)
     `active` row with a slot whose heartbeat is fresh (legit live
     turn — must NOT be reaped); (c) `active` row with a slot whose
     heartbeat is 130s stale (must be reaped); (d) `waiting_for_user`
     row with stale slot (out of scope — inactivity timer's domain).
   - Mock `setInterval` (Vitest fake timers).
   - Call `startStuckActiveReaper()`; advance fake clock past one tick.
   - Assert: (a) reaped → `failed` + `releaseSlot` (idempotent no-op
     for already-missing slot); (b) untouched; (c) reaped + slot
     released; (d) untouched.

2. In `apps/web-platform/supabase/migrations/`, add a new migration
   `037_stuck_active_finder_rpc.sql` defining a SECURITY DEFINER RPC
   that returns the candidate set. Application-side joins via PostgREST
   `select` are awkward when the predicate involves a LEFT JOIN —
   easier to push the predicate into one RPC. Sketch:
   ```sql
   create or replace function public.find_stuck_active_conversations(
     p_threshold_seconds integer default 120
   ) returns table (id uuid, user_id uuid)
   language sql
   security definer
   set search_path = public, pg_temp
   as $$
     select c.id, c.user_id
     from public.conversations c
     left join public.user_concurrency_slots s
       on s.user_id = c.user_id and s.conversation_id = c.id
     where c.status = 'active'
       and c.archived_at is null
       and (
         s.id is null
         or s.last_heartbeat_at < now() - (p_threshold_seconds || ' seconds')::interval
       );
   $$;

   revoke all on function public.find_stuck_active_conversations(integer) from public;
   grant execute on function public.find_stuck_active_conversations(integer) to service_role;
   ```
   Pin `search_path = public, pg_temp` per
   `cq-pg-security-definer-search-path-pin-pg-temp`. Migration is
   forward-only, no `CONCURRENTLY` (Supabase wraps in txn). Body uses
   `language sql` (no plpgsql blocks needed).

3. In `agent-runner.ts`, add `startStuckActiveReaper()`:
   ```ts
   const STUCK_ACTIVE_THRESHOLD_SECONDS = 120;
   const STUCK_ACTIVE_CHECK_INTERVAL_MS = 60 * 1_000;

   export function startStuckActiveReaper(): void {
     const timer = setInterval(async () => {
       const { data, error } = await supabase().rpc(
         "find_stuck_active_conversations",
         { p_threshold_seconds: STUCK_ACTIVE_THRESHOLD_SECONDS },
       );
       if (error) {
         log.error({ err: error }, "Stuck-active reaper find error");
         reportSilentFallback(error, {
           feature: "concurrency-stuck-active-reaper",
           op: "find",
         });
         return;
       }
       const candidates = (data ?? []) as Array<{ id: string; user_id: string }>;
       if (candidates.length === 0) return;

       for (const conv of candidates) {
         // Idempotent: if another replica already flipped the row,
         // updateConversationFor with expectMatch=false is safe.
         const result = await updateConversationFor(
           conv.user_id,
           conv.id,
           { status: "failed", last_active: new Date().toISOString() },
           {
             feature: "concurrency-stuck-active-reaper",
             op: "finalize",
             expectMatch: false,
           },
         );
         if (!result.ok) {
           log.warn(
             { conv, err: result.error },
             "stuck-active reap: status flip failed (will retry next tick)",
           );
           continue;
         }
         // Order: status flip → releaseSlot → abortSession.
         // releaseSlot is the keyed DELETE; abortSession triggers the
         // controller.signal.aborted branch in agent-runner.ts:1166-1180,
         // which sees the row already-failed and skips its own write.
         await releaseSlot(conv.user_id, conv.id);
         abortSession(conv.user_id, conv.id);
       }
       log.info(
         { count: candidates.length },
         "stuck-active reaper finalized rows",
       );
     }, STUCK_ACTIVE_CHECK_INTERVAL_MS);
     timer.unref();
   }
   ```

4. Wire into `apps/web-platform/server/index.ts` after the existing
   `startInactivityTimer()` call.

5. **Important:** Do NOT extend `cleanupOrphanedConversations` to do
   this — that function's contract is "called once at startup", uses
   `last_active < cutoff` as its threshold, and is load-bearing for
   cold-boot recovery (catches rows where the slot row was deleted by
   pg_cron during the outage but the conversation row was never
   finalized). The two functions are complementary:
   - `cleanupOrphanedConversations` — startup-only, `last_active`-based
     (catches cold-boot rows even if their slot rows are gone).
   - `startStuckActiveReaper` — periodic, slot-heartbeat-based
     (catches steady-state leaks while the server is running).

6. Verify tests pass.

### Phase 4 — Self-Healing cap_hit Recovery (RED → GREEN)

1. Write `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts`:
   - Seed user (cap=1) with one row in `user_concurrency_slots` whose
     `conversation_id` does NOT match any row in `conversations`
     (orphan).
   - Simulate `start_session`. Assert: divergence path fires,
     orphan slot deleted, retry succeeds, `session_started` emitted.
   - Negative case: slot references a real `active` conversation; no
     recovery; cap_hit proceeds with `concurrency_cap_hit` telemetry
     and WS close.
2. In `ws-handler.ts`, between line 916 (after Stripe webhook-lag
   fallback) and line 918 (`if (acquire.status === "cap_hit" || …)`),
   add a divergence-recovery block:
   ```ts
   if (acquire.status === "cap_hit") {
     const recovered = await tryLedgerDivergenceRecovery(userId, supabase);
     if (recovered.didRecover) {
       acquire = await acquireSlot(userId, pendingId, cap);
     }
   }
   ```
3. Define `tryLedgerDivergenceRecovery(userId, supabase)` in a new
   helper section in `ws-handler.ts` (keep it nearby so the call site
   reads top-down):
   - SELECT visible-active conversations as listed in AC4.
   - SELECT `user_concurrency_slots` for this user.
   - Compute orphan set = slots with `conversation_id` not in visible.
   - If `orphans.length === 0`: no recovery; return
     `{ didRecover: false }`.
   - Else: for each orphan, call `releaseSlot(userId, slot.conversation_id)`
     (best-effort).
   - `reportSilentFallback(new Error("ledger-divergence"), { feature:
     "concurrency-ledger-divergence", op: "start_session-recovery",
     extra: { userId, visibleCount, slotCount, orphanCount } })`.
   - Return `{ didRecover: orphans.length > 0 }`.
4. Verify tests pass.

### Phase 5 — Wire-up + Verification (GREEN)

1. Run all three new test files locally.
2. Run `bun test apps/web-platform/test/agent-runner*.test.ts apps/web-platform/test/ws-handler*.test.ts` (after
   verifying the runner via the deepen pass — see AC8).
3. `tsc --noEmit` clean.
4. Manual smoke: stand up local Supabase + WS server, simulate the
   reproduction (kill agent process between `saveMessage` and
   `updateConversationStatus`); verify the row transitions to `failed`
   within 5 min and the slot frees.

### Phase 6 — Tracking Issues + Compound + Ship

1. **Primary bug.** File a GitHub issue: "fix: stuck-active conversation
   blocks concurrency slot in KB chat". Title body cites the user report
   from `jean.deruelle@jikigai.com`, both screenshots attached. PR body:
   `Closes #<this-issue>`.
2. **Reference, do NOT close, #3219** (inactivity-sweep slot leak). It
   addresses the parallel `waiting_for_user → completed` bulk-flip leak
   in `agent-runner.ts:447`. The fix shape there is different (add
   explicit `releaseSlot` calls inside the existing inactivity
   timer's loop). PR body: `Ref #3219`. Do not fold in — keeps PR
   scope tight.
3. **Roadmap impact:** none — this is a stability fix.
4. Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
5. Standard ship pipeline (review → QA → merge).

## Test Scenarios

| # | Scenario | Pre-fix behavior | Post-fix behavior |
|---|---|---|---|
| 1 | Free-tier user, agent throws between `saveMessage` and `updateConversationStatus` | Conversation stuck at `active`; slot leaks indefinitely | Row → `waiting_for_user` (text was saved) or `failed`; slot released immediately |
| 2 | Free-tier user, conversation stuck at `active` for ≥ 5 min (any cause) | Slot held forever (heartbeats keep refreshing) | Row → `failed` within 5 min; slot released; user can start new conversation |
| 3 | Free-tier user, slot exists but matching conversation row is missing (orphan) | `cap_hit` indefinitely until pg_cron 120-s lazy sweep + heartbeat lapse | Self-healing branch detects divergence, releases orphan slot, retries acquire, succeeds |
| 4 | Free-tier user, genuine cap_hit (1 active visible + 1 visible) | `cap_hit` close (4010); telemetry emitted | Same — no behavior change for genuine cap |
| 5 | Process killed mid-`result`-branch (SIGKILL, no clean catch) | Row stuck `active`; slot held | Row → `failed` within 5 min via reaper; slot released |
| 6 | `syncPush` succeeds but `updateConversationStatus` (`expectMatch: true`) lands 0 rows because conversation was concurrently archived | Row stuck `active` (now-archived); slot leaks until pg_cron tick AFTER user disconnects fully | Catch in `result`-branch sets `failed` + releases slot directly; archive trigger from migration 036 also releases (idempotent) |
| 7 | Multi-leader dispatch with 1 leader throwing on `result` | Row at `active` if the throwing leader was the last to set status | Catch finalizes status; the other leaders' status writes are idempotent (last-writer-wins on `last_active`) |
| 8 | Reaper hits a row with `status='active'` and `last_active = now() - 4 min` | Reaper does not fire (threshold is 5 min) | Same — threshold preserved |

## Risks

1. **Reaper races with a long-running legitimate `active` session —
   RESOLVED at deepen-plan.** Code-read confirms `saveMessage`
   (agent-runner.ts:321-340) does NOT update `last_active`. Only
   `updateConversationStatus` (line 350) and `cc-dispatcher.ts:518` do.
   A long tool-heavy turn streaming partials without status writes
   would have stale `last_active`. **Resolution:** the reaper signal
   was switched from `last_active` to `user_concurrency_slots.last_heartbeat_at`
   (refreshed every 30s by `ws-handler.ts:1596` for the active conversation).
   Fresh slot heartbeat = WS session is alive + still claiming this
   conversation as its current = legit live turn = NOT reaped. Stale
   heartbeat (no WS session, or WS session moved on) = reapable.
   This eliminates the false-positive class.

2. **Self-healing recovery masks a real bug.** If `acquireSlot` returns
   `cap_hit` and the recovery path always succeeds, future regressions
   that leak slots are silently absorbed by the recovery branch.
   **Mitigation:** every recovery emits a Sentry event with
   `feature: "concurrency-ledger-divergence"`. AC14 mandates
   monitoring this rate for 24 h post-deploy. If non-zero, the user-impact
   is contained but a new issue must be filed.

3. **Reaper reaps a conversation whose process is alive but stalled.**
   If the agent runner is still in `for await (const message of ...)`
   on line 1040 but the SDK iterator is hung, the reaper will set
   the row to `failed` and release the slot — but the in-process
   `activeSessions` Map still has the entry. **Mitigation:** the
   reaper calls `abortSession(userId, id)` (matches line 459 of
   `startInactivityTimer`); `abortSession` cancels the SDK iterator
   via `AbortController.abort()`. The outer `try` at line 1165 then
   sees `controller.signal.aborted` and skips the `failed` write
   (line 1167-1180). No double-write.

4. **Reaper's `releaseSlot` races with `acquireSlot` on the same
   `(userId, conversationId)`.** Unlikely (the reaper only touches
   stuck rows; `acquireSlot` only touches new pendingIds), but if it
   happens the RPC is a plain DELETE keyed on `(user_id,
   conversation_id)` — idempotent and harmless.

5. **`tryLedgerDivergenceRecovery` runs on every `cap_hit` —
   adds 2 SELECTs per cap_hit deny.** Cost is negligible
   (cap_hit is rare; the user is already on a deny path), but
   document it. **Mitigation:** none needed; cap_hit is a deny
   path that already invokes Stripe + telemetry.

6. **`updateConversationStatus` with `expectMatch: true` on a
   concurrently-archived row throws.** The new catch in the result
   branch handles this — falls through to `failed` and releases.
   But the archive trigger (migration 036) ALSO calls
   `release_conversation_slot` on `archived_at` transition. The
   result-branch catch's release call is a no-op second invocation
   — idempotent per migration 029 RPC contract. Safe.

7. **Periodic timer + startup-time `cleanupOrphanedConversations`
   double-process the same row at boot.** Both call
   `update().eq("status", "active")` — the second run finds zero
   stuck rows because the first already flipped them. Safe.

8. **Multi-process / horizontal scale-out.** If two server replicas
   run, both schedule the reaper. Both fire every 5 min. Both
   queries are idempotent (last-writer-wins on the UPDATE; the
   DELETE-keyed `releaseSlot` is idempotent). Cost is at most 2x
   trivial DB load. Safe.

## Sharp Edges

- **Status transition is the LAST step in the success path.** The
  `result`-branch in `agent-runner.ts` has SIX steps after the message
  save (cost RPC, usage_update emit, syncPush await, stream_end emit,
  status update, session_ended emit). A throw at ANY of those leaves
  the row stuck. The catch added by AC1 must cover the WHOLE branch
  body — not just the lines around the status update. Trace each step
  during work and confirm the catch boundary fires for all 6.
- **`releaseSlot` is a fire-and-forget no-op on missing slots.** Do
  NOT add an `expectMatch`-style assertion to it — the reaper, the
  archive trigger, and the explicit teardown paths all call it; it
  must remain idempotent.
- **`startStuckActiveReaper` is a NEW timer**, not a refactor of
  `cleanupOrphanedConversations`. The startup-time function stays as
  a one-shot run — its existence is load-bearing for cold-boot
  recovery (handles the case where the server crashes with N stuck
  rows and the reaper's 5-min cadence would otherwise leave them
  stuck for 5 more min after restart).
- **Self-healing recovery must not loop.** If the retry returns
  `cap_hit` again (genuine cap), proceed to the existing close path.
  Do NOT recurse.
- **The `last_active` column is updated only on `updateConversationStatus`
  (every status write) and message inserts.** A long-running agent
  turn that does not write status will appear "stuck" to the reaper
  even though it's live. Verify at deepen-plan whether this is an
  issue in practice (the reaper threshold is 5 min; tool-heavy turns
  could exceed this). If yes, add a `last_active` heartbeat on every
  assistant chunk or raise the threshold.
- **Vitest cannot exercise the WS handler's full integration path
  natively.** AC7 uses the existing `apps/web-platform/test/ws-handler*.test.ts`
  harness pattern with mocked Supabase clients. The definitive
  verification is the post-merge AC14 Sentry monitoring + AC15 user
  confirmation.
- **A plan whose `## User-Brand Impact` section is empty, contains
  only `TBD`/`TODO`/placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6.** Section above is filled.
- **`cc-dispatcher.ts:518` is a parallel status writer** for the
  `/soleur:go` runner. The catch added by AC1 covers `agent-runner.ts`
  only. Verify at work-time whether the same stuck-active class is
  reachable through the dispatcher path (initial read says no — its
  `expectMatch: true` path at line 736-741 already finalizes
  ownership, but worth a 5-minute trace).
- **WS-side `session.conversationId` may stale after a reap.** When the
  reaper finalizes a row to `failed`, the WS session that was holding
  it as `session.conversationId` does NOT learn about it — its 30s
  heartbeat fires `touchSlot` and gets 0-row return (concurrency.ts:151)
  but the return is `void`-discarded at `ws-handler.ts:1596`. If the
  user sends another chat message on that conversation, `expectMatch:
  true` at agent-runner.ts:356 throws and the catch from AC1 quickly
  finalizes again (idempotent). User UX for that one message is bad
  but recoverable. Filed as a follow-up: have the WS heartbeat re-acquire
  on 0-row return (or close the session with a `session_replaced`
  preamble). Out of scope for this PR.
- **Migration 037 is forward-only** (matches 029/036 stance). The RPC
  it adds is read-only — rolling back is just `drop function`. No
  data dependency.
- **Reaper ordering matters.** Status flip → `releaseSlot` →
  `abortSession`. Reversing #2 and #3 is fine (idempotent), but doing
  `abortSession` first triggers the existing
  `controller.signal.aborted` branch at agent-runner.ts:1166 which
  itself writes `failed` — racing with the reaper's write. Status
  flip first means the abort-branch sees an already-`failed` row and
  the catch's status write is a no-op (`expectMatch: false`).

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase Reality | Plan Response |
|---|---|---|
| User report: "stuck in Executing state from 10m ago" | Verified — "Executing" maps to `status='active'` (lib/types.ts:344) | Plan addresses status transition reliability + reaper |
| User report: "response was 'I'm unable to read the PDF…'" | Means `saveMessage` (agent-runner.ts:1079) succeeded; the throw is between line 1079 and line 1134 | Plan's catch must distinguish post-save from pre-save throws (AC1) |
| Existing `cleanupOrphanedConversations` runs periodically | False — runs ONCE on startup (server/index.ts:89) | Plan adds a periodic reaper |
| Existing `startInactivityTimer` covers stuck `active` | False — sweeps only `waiting_for_user` at 2-hour cadence (agent-runner.ts:447) | Reaper addresses `active` separately at 5-min cadence |
| Migration 036's archive trigger fixes this | False — the trigger releases slot only on `archived_at` transition; user's stuck conversation has `archived_at IS NULL` | App-layer fix needed |
| `release_conversation_slot` is idempotent | True (migration 029, line 200-203) — plain keyed DELETE | Recovery + reaper + catch can all call it without coordination |
| `acquireSlot`'s lazy sweep would reclaim the orphan | False — lazy sweep checks `last_heartbeat_at < now() - 120s`; the heartbeat is fresh because the WS session is alive (ws-handler.ts:1590-1598) | Self-healing branch in AC4 explicitly handles this |
| #3219 (inactivity-sweep slot leak) is the same bug | Partially — #3219 covers `waiting_for_user → completed` bulk-flip in `agent-runner.ts:447`. This plan covers stuck `active`. Both leak slots; both need fixes; different code paths. | Reference-only; do not fold in |

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** assessed (in-pipeline; no subagent spawn — pipeline mode)
**Assessment:** This is an availability-class bug rooted in a
status-machine invariant violation: the success path's last step is the
status transition, with at least 5 throw-eligible steps before it. The
fix is a try/catch wrapping the result branch + a periodic reaper for
defense-in-depth + a self-healing recovery on cap_hit. All three are
application-layer; no migration. Aligns with prior PRs #3219
(inactivity-sweep) and the migration-036 archive trigger — all three
are slot-lifecycle invariants spread across multiple code paths;
consolidating into a single DB constraint is rejected because
`resume_session` does not call `acquireSlot` (Risk #5 of
2026-05-04-fix-cc-conversation-limit-archive-plan.md).

### Product (CPO)

**Status:** assessed (in-pipeline)
**Assessment:** `single-user incident` blast-radius. A free-tier user
who hits this on first KB chat interaction churns. The error message
("Archive a completed conversation") is misleading because the stuck
conversation is NOT in the user's mental model of "completed" —
they perceive it as still running. CPO sign-off required at plan time
per `hr-weigh-every-decision-against-target-user-impact`.
`user-impact-reviewer` will be invoked at PR review.

### Product/UX Gate

**Tier:** none — no new UI or copy. The error message stays the same;
the fix is server-side. A follow-up issue to improve the error message
("This conversation appears stuck — refresh and try again, or wait 5
min for automatic recovery") would be valuable but is out-of-scope.

## Open Code-Review Overlap

3 open scope-outs touch files in this PR's blast radius:

- **#3219** fix: inactivity-sweep slot leak (agent-runner.ts:447) —
  *Acknowledge.* Same code file, parallel concern. This PR addresses
  `active`-class stuck rows; #3219 addresses the
  `waiting_for_user → completed` bulk-flip on the inactivity timer.
  Both are slot-leak paths. Folding in would require a different fix
  shape (explicit `releaseSlot` calls inside the inactivity timer's
  loop) — keep them separate to keep this PR scoped. PR body: `Ref #3219`.
- **#2955** arch: process-local state assumption needs ADR + startup
  guard — *Acknowledge.* This PR's reaper inherits the same
  process-local assumption (`abortSession` operates on in-process
  `activeSessions` Map). Not folding in; the ADR is a separate
  architectural question.
- **#2961** review: enforce conversations.repo_url immutability via
  Postgres trigger — *Acknowledge.* No interaction; different table
  invariant.

## Plan Review Notes (for plan-review agents)

- This is a fix-class plan with three independent surfaces. MORE detail
  level chosen because the result-branch wrap (AC1) is non-trivial: 6
  throw-eligible steps after the message save; the catch must finalize
  state for all of them.
- Do NOT propose a DB-level "release slot when status leaves `active`"
  trigger. It was rejected at the prior PR's deepen pass (Risk #5 of
  2026-05-04-fix-cc-conversation-limit-archive-plan.md): `resume_session`
  does not call `acquireSlot`, so a release-on-completed trigger lets a
  resumed conversation run outside the slot ledger.
- Do NOT propose merging the new reaper with `startInactivityTimer`.
  Cadences differ (5 min vs 1 hour), thresholds differ (5 min vs 2
  hours), and status-sets-being-reaped differ (`active` vs
  `waiting_for_user`).
- Do NOT propose adding a new AGENTS.md rule. Discoverability exit
  applies: the bug surfaces as a 4010 close + a 10-min "Executing"
  badge — clear product-visible failure that future authors can
  diagnose without a hidden-constraint rule.
- The risk #1 (reaper races with a legitimate long-running turn) is
  the single most important verification to fold in at deepen-plan.
  Trace `last_active` updates through the SDK iteration loop and
  decide between (a) heartbeat `last_active` on every assistant
  chunk, or (b) raising the reaper threshold.
