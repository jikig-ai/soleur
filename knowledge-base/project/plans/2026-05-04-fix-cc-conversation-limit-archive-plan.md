---
title: "fix: archive must release the concurrent-conversation slot"
type: fix
date: 2026-05-04
branch: feat-cc-conversation-limit-archive
classification: user-blocking-prod
requires_cpo_signoff: true
related_brainstorms: []
related_specs: [feat-cc-conversation-limit-archive]
related_migrations: [029_plan_tier_and_concurrency_slots.sql]
deepened_on: 2026-05-04
---

# Fix: Archive Must Release the Concurrent-Conversation Slot

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Risks, Acceptance Criteria, Test Scenarios, Sharp Edges

### Key Improvements

1. **Resolved Risk #5 (status='completed' design call):** The trigger fires on
   `archived_at` transitions ONLY. Status='completed' alone must NOT release
   the slot because `resume_session` does not re-acquire — releasing on
   completed would let a resumed conversation run outside the slot ledger and
   break cap arithmetic. The user's reported scenario is still fixed because
   they archived after marking completed.
2. **Discovered second slot-leak source:** the inactivity sweep in
   `apps/web-platform/server/agent-runner.ts:447` bulk-flips
   `waiting_for_user → completed` without calling `releaseSlot`. Filed as a
   follow-on issue (Phase 6), out of scope for this PR — the user's reported
   scenario does not depend on this path.
3. **Trigger semantics tightened:** AFTER UPDATE WHEN clause restricts the
   trigger to rows where `archived_at` actually transitioned NULL → non-NULL.
   The `WHEN` filter must use `IS DISTINCT FROM` to correctly compare
   nullable values (Postgres `=` returns NULL when either side is NULL).
4. **Migration sequencing pinned:** Next available index is 036 (035 is the
   most-recent migration on this branch, verified via `ls
   apps/web-platform/supabase/migrations/`).
5. **Test harness aligned with codebase reality:** Vitest cannot exercise
   Postgres triggers natively. Tests assert call-ordering against mocked
   Supabase clients; the definitive verification is the post-merge prod-DB
   read (AC14).

### New Considerations Discovered

- `resume_session` (line 812 of ws-handler.ts) does NOT call `acquireSlot`.
  Today this is fine because the slot row persists for completed/active
  conversations. After this fix, this stays fine — slots are released only
  on archive, and archived conversations cannot be resumed in the active
  list anyway (the rail filter is `archived_at IS NULL`).
- The bulk inactivity sweep in `agent-runner.ts` is a parallel slot-leak
  path. Tracked separately so this PR remains scoped.
- `release_conversation_slot` is idempotent (plain DELETE keyed on
  `(user_id, conversation_id)`), so the trigger calling it after
  `close_conversation` already called it is a safe no-op.



## Overview

A user on the free tier (cap = 1) — and any user at any tier — can be hard-locked
out of starting new conversations after archiving (or marking as completed) all
visible conversations. The Command Center sidebar correctly shows zero active
conversations and `+ New conversation`, but the WebSocket close fires with code
`4010 CONCURRENCY_CAP` and the banner reads `Concurrent-conversation limit
reached`. There is no in-product recovery path short of waiting for the pg_cron
sweep (≤ 60 s after the WS heartbeat finally lapses ~120 s after disconnect).

The slot ledger lives in `public.user_concurrency_slots` (migration 029). Slot
acquire/release goes through three SECURITY DEFINER RPCs:
`acquire_conversation_slot` / `touch_conversation_slot` /
`release_conversation_slot`. **Nothing in the archive path or the
status-mark-completed path calls `release_conversation_slot`**, and while the
WebSocket session remains open, `touch_conversation_slot` keeps refreshing the
heartbeat every 30 s — so the lazy 120 s sweep never fires either. The slot
leaks until the user disconnects entirely, and even then only pg_cron reclaims
it (1-minute cadence).

The bug is symmetric across two surfaces:

1. `apps/web-platform/hooks/use-conversations.ts:325` — `archiveConversation`
   issues a direct client-side `supabase.from("conversations").update({
   archived_at })`. No slot release.
2. `apps/web-platform/server/conversations-tools.ts:191` — the MCP tool
   `conversation_archive` does an analogous server-side UPDATE. No slot
   release.
3. `apps/web-platform/hooks/use-conversations.ts:351` — `updateStatus` writes
   `status: 'completed'` directly. The WS handler's `close_conversation` path
   already releases the slot when it transitions a conversation to `completed`,
   but the Command Center's status-update bypass never reaches the WS handler.

The fix lives at the DB layer — a Postgres trigger that calls
`release_conversation_slot` whenever `archived_at` transitions from `NULL` to
non-`NULL`, OR `status` transitions to `completed`. This closes the loop for
every current and future writer (hook, MCP tool, future API endpoint, manual
DB write) and matches the existing pattern in migration 029 where slot lifecycle
is owned by SECURITY DEFINER functions, not by application code.

## Reproduction (verified against user report)

1. User connected as `jean.deruelle@jikigai.com`.
2. Free-tier cap = 1, but two slots present in `user_concurrency_slots`
   (acquired across two separate conversations earlier in the session).
3. User clicks "Mark as completed" → `useConversations.updateStatus`
   updates `conversations.status = 'completed'`. Slot still held.
4. User clicks "Archive" → `useConversations.archiveConversation` updates
   `conversations.archived_at = now()`. Slot still held.
5. Recent Conversations sidebar (default `archiveFilter: "active"`,
   `is("archived_at", null)`) is now empty.
6. User clicks "+ New conversation" → WS sends `start_session` with new
   `pendingId`. Server calls `acquire_conversation_slot(userId, pendingId,
   1)`. Lazy sweep doesn't fire (heartbeats are fresh from the user's other
   active WS connections). Slot count after insert = 3 > cap = 1.
7. RPC returns `cap_hit`. WS closes with 4010 + `concurrency_cap_hit`
   preamble. Client renders `Concurrent-conversation limit reached`.

The "Session Failed to Start within 10 seconds" banner is the same bug — the
client's session-start watchdog races the 4010 close.

## User-Brand Impact

**If this lands broken, the user experiences:** complete inability to start
new conversations after a normal cleanup workflow (archive + mark-as-completed).
The Command Center is unusable until either pg_cron (≤ 60 s) or the 120 s
heartbeat-lapse sweep clears the orphaned slots — and that only after the
user fully disconnects every WS, which most users won't think to do.

**If this leaks, the user's workflow is exposed via:** N/A — this is a
liveness/availability bug, not a confidentiality bug. No cross-tenant data
crosses any boundary. The slot ledger is per-user.

**Brand-survival threshold:** `single-user incident`. Soleur is positioning as
the agent platform for solo founders. A user who archives every conversation
"to clean up" and is then locked out of creating new ones — with an error
message that says they hit a *concurrency* cap when they have *zero* active
conversations — concludes the product is broken. For a paid tier this lasts
until the next pg_cron tick; for a free-tier prospect this is a churn event.

CPO sign-off required (per `hr-weigh-every-decision-against-target-user-impact`).
`user-impact-reviewer` will be invoked at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: New migration `036_release_slot_on_archive.sql` adds an
      AFTER UPDATE trigger on `public.conversations` that calls
      `public.release_conversation_slot(user_id, id)` when **and only when**
      `archived_at` transitions from `NULL` to non-`NULL`. The trigger does
      NOT fire on `status='completed'` transitions — see Risk #5 + Sharp
      Edges below for why. The `WHEN` clause must use `IS DISTINCT FROM`
      (not `=`) to compare nullable `archived_at` correctly.
- [ ] AC2: Trigger pins `SET search_path = public, pg_temp` and qualifies every
      relation as `public.<table>` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- [ ] AC3: Migration is non-`CONCURRENTLY` (Supabase wraps each migration in
      txn; matches 025/027/029 pattern).
- [ ] AC4: Vitest unit test in `apps/web-platform/test/conversation-archive-release-slot.test.ts`
      asserts that calling `archiveConversation(id)` triggers a
      `release_conversation_slot` RPC call (assertion runs against the
      mocked Supabase client used in sibling test files;
      e.g., `apps/web-platform/test/conversations-list-archive-tools.test.ts`).
      Negative case: `updateStatus(id, "completed")` does NOT call
      `release_conversation_slot` (slot remains held until archive or
      explicit close).
- [ ] AC5: Vitest test in `apps/web-platform/test/conversations-list-archive-tools.test.ts`
      extended to assert the same invariant for the MCP `conversation_archive`
      tool. The test asserts the trigger fires (slot row removed) when the
      tool's UPDATE lands.
- [ ] AC6: WS-handler test
      `apps/web-platform/test/ws-handler-archive-releases-slot.test.ts`:
      with an active WS session for user A holding a slot, simulate a
      `conversations.archived_at` UPDATE from outside the WS handler (via
      direct service client). Assert that `acquireSlot` for a *new* pendingId
      under the same user A immediately succeeds (slot count post-archive
      under cap) and does not return `cap_hit`. Negative test: pre-fix code
      path returns `cap_hit`. (The negative side is covered by deleting the
      trigger and re-running the test.)
- [ ] AC7: All tests pass locally (`bun test apps/web-platform/test/conversation-archive-release-slot.test.ts apps/web-platform/test/conversations-list-archive-tools.test.ts apps/web-platform/test/ws-handler-archive-releases-slot.test.ts`).
- [ ] AC8: `tsc --noEmit` clean.
- [ ] AC9: No new AGENTS.md rules added — discoverability exit applies (the
      cap_hit error is a clear runtime failure that surfaces immediately, and
      the new trigger + tests prevent recurrence at the data layer). A
      learning file MUST be written to
      `knowledge-base/project/learnings/bug-fixes/<topic>.md` documenting the
      gap (slot lifecycle owned in DB; client-side `archived_at` update
      bypassed it).
- [ ] AC10: PR body uses `Closes #<issue-number>` once the tracking issue
      is filed (Phase 6 below).
- [ ] AC11: User-brand impact section above is filled (not `TBD` / `TODO` /
      placeholder), per `deepen-plan` Phase 4.6.
- [ ] AC12: WS-handler in-process state is consistent with the new DB
      reality. After archive, if a WS session has the just-archived
      conversationId set as its `session.conversationId`, the next chat from
      that session will land an UPDATE on `conversations` for an archived
      row. Verify this is not silently broken: either (a) the WS handler
      detects archived conversations and forces a fresh `start_session`, or
      (b) the existing `expectMatch` invariant in `updateConversationFor`
      already guards against it. **Action:** trace the path during work and
      add a Sharp Edge below if (a) is needed. Initial read: existing logic
      writes `last_active` and `status` regardless of `archived_at` — this is
      defensible because the user can unarchive and resume — so (b) is the
      likely answer, but verify.

### Post-merge (operator)

- [ ] AC13: Apply migration to `prd` Supabase via `supabase db push --db-url
      "$(doppler secrets get SUPABASE_DB_URL -p soleur -c prd --plain)"`. This
      is a destructive write against shared prod (per
      `hr-menu-option-ack-not-prod-write-auth`); show the exact command,
      wait for explicit per-command go-ahead.
- [ ] AC14: Verify in prod via `psql` (read-only connection):
      `select count(*) from public.user_concurrency_slots where user_id =
      '<jean.deruelle@jikigai.com user_id>'` — should be 0 immediately after
      he archives the test conversations.
- [ ] AC15: Reach out to user (jean.deruelle@jikigai.com) to confirm he can
      create new conversations after the deploy lands.

## Files to Edit

- `apps/web-platform/supabase/migrations/036_release_slot_on_archive.sql` *(new)*
- `apps/web-platform/test/conversation-archive-release-slot.test.ts` *(new)*
- `apps/web-platform/test/conversations-list-archive-tools.test.ts` *(extend)*
- `apps/web-platform/test/ws-handler-archive-releases-slot.test.ts` *(new)*
- `knowledge-base/project/learnings/bug-fixes/<topic>.md` *(new — date picked at
  write-time per `cq-pg-…` discipline; topic suggestion: `cc-archive-must-release-slot`)*

**Files NOT edited (intentional):**

- `apps/web-platform/hooks/use-conversations.ts` — leaving the direct client
  UPDATE; the trigger handles slot release regardless of writer. Modifying the
  hook to also call a slot-release RPC would be belt-and-suspenders but
  doubles the surface that has to stay correct.
- `apps/web-platform/server/conversations-tools.ts` — same reasoning: the
  trigger covers the MCP tool's UPDATE.
- `apps/web-platform/server/ws-handler.ts` — `close_conversation` already
  calls `releaseSlot` explicitly. The trigger will additionally fire when
  `status: 'completed'` lands (already true on this path). That's idempotent
  — `release_conversation_slot` is a plain DELETE keyed on
  `(user_id, conversation_id)` — so a second invocation is a no-op.

## Implementation Phases

### Phase 1 — Trigger Migration (RED)

1. Create `apps/web-platform/supabase/migrations/036_release_slot_on_archive.sql`.
2. Define `public.release_slot_on_archive()` SECURITY DEFINER function:
   - `language plpgsql`
   - `set search_path = public, pg_temp`
   - Body: invokes `perform public.release_conversation_slot(NEW.user_id, NEW.id);`
     and `return NEW;` (per-row body needs no extra guards because the
     `WHEN` clause filters at trigger-evaluation time and the RPC is
     idempotent).
3. Define
   `create trigger conversations_release_slot_on_archive
    after update of archived_at on public.conversations
    for each row
    when (OLD.archived_at IS DISTINCT FROM NEW.archived_at
          AND NEW.archived_at IS NOT NULL)
    execute function public.release_slot_on_archive();`
   - `OF archived_at` keeps the trigger no-op for unrelated column updates
     (cheap eval — Postgres doesn't even fire the trigger if the named
     column wasn't in the UPDATE's SET list).
   - `IS DISTINCT FROM` correctly handles the NULL → non-NULL transition.
4. `revoke all on function public.release_slot_on_archive() from public;`
   + no grants (trigger executes as definer; no direct callers).
5. Header comment cites migration 029 for the search_path pin lineage and
   the slot-ledger contract.

**Research Insights — Postgres trigger best-practices applied:**

- **`AFTER UPDATE OF <column>` + `WHEN`** is the canonical "idempotent
  trigger" shape for column-transition side effects. The `OF archived_at`
  qualifier means Postgres skips the trigger entirely when other columns
  are updated — cheaper than `WHEN`-clause filtering alone (the planner
  doesn't even allocate a tuple snapshot). Source: Postgres `CREATE
  TRIGGER` docs.
- **`IS DISTINCT FROM` vs `=`:** `NULL = NULL` returns NULL (not true),
  which `WHEN` treats as false → trigger silently skips. `NULL IS DISTINCT
  FROM NULL` returns false; `NULL IS DISTINCT FROM '2026-05-04'` returns
  true. This is the documented gotcha that caused multiple Supabase
  community-forum threads on triggers that "never fire."
- **SECURITY DEFINER with `pg_temp` last in search_path** is the
  AGENTS.md `cq-pg-security-definer-search-path-pin-pg-temp` rule. Pin it
  + qualify every relation as `public.<table>`.
- **Bulk UPDATE concern:** AFTER FOR EACH ROW means a 10K-row UPDATE
  fires 10K trigger invocations. The body here is a single keyed DELETE
  with no advisory lock, costing ~100 µs per fire on Supabase's hardware.
  10K × 100 µs = 1 second — acceptable. If a future bulk-archive
  operation runs against millions of rows, an operator can suppress
  triggers via `SET LOCAL session_replication_role = replica`.

### Phase 2 — Tests (RED)

Tests must fail without the migration applied and pass with it. The Vitest
suite for migrations uses `apps/web-platform/test/test-utils/supabase-mock.ts`
patterns where applicable; for the slot-trigger invariant we mock the RPCs
and assert ordering of calls.

1. **`conversation-archive-release-slot.test.ts`** (new, hook-level):
   - Mock `supabase.rpc("release_conversation_slot", …)` to track calls.
   - Mock the `conversations.update` chain to fire the trigger handler in
     a test-double when `archived_at` transitions.
   - Call `archiveConversation(id)` and assert
     `release_conversation_slot` was invoked with the right args.
   - Repeat for `updateStatus(id, "completed")`.

2. **`conversations-list-archive-tools.test.ts`** (extended):
   - Add a test case that asserts the same RPC call after the MCP
     `conversation_archive` tool's UPDATE.

3. **`ws-handler-archive-releases-slot.test.ts`** (new, integration-shaped):
   - Use the existing `apps/web-platform/test/ws-handler*.test.ts` harness.
   - Acquire a slot for user A.
   - Mark the conversation `archived_at = now()` via a direct service client
     UPDATE (simulating the trigger firing).
   - Assert `acquireSlot(userA, newPendingId, cap=1)` returns
     `{ status: "ok" }` (no longer over cap).

### Phase 3 — Wire-up + Verification (GREEN)

1. Apply migration locally: `cd apps/web-platform && supabase db reset
   --linked` against the local Supabase instance, OR
   `supabase migration up`. Record the actual command in the work-skill
   commit.
2. Run the three new test files.
3. Run `bun test --testPathPattern '(archive|conversation-archive)'` to
   sweep adjacent suites.
4. `tsc --noEmit` clean.

### Phase 4 — Sharp-edge Audit (carry-forward from deepen-plan)

The deepen-plan pass already enumerated every site that writes to
`public.conversations`. Carry the audit forward into the PR body so
reviewers can verify:

| Site | Writes | Trigger fires? | Disposition |
|---|---|---|---|
| `apps/web-platform/hooks/use-conversations.ts:329` | `archived_at = now()` | YES | Covered by trigger |
| `apps/web-platform/hooks/use-conversations.ts:342` | `archived_at = null` (unarchive) | NO (no NULL→non-NULL) | Correct — unarchive does not release a slot it shouldn't release |
| `apps/web-platform/hooks/use-conversations.ts:362` | `status = <new>` | NO (archive-only trigger) | Correct — see Risk #5 |
| `apps/web-platform/server/conversations-tools.ts:209` (MCP archive) | `archived_at = now()` | YES | Covered by trigger |
| `apps/web-platform/server/conversations-tools.ts:247` (MCP unarchive) | `archived_at = null` | NO | Correct |
| `apps/web-platform/server/conversations-tools.ts:289` (MCP update_status) | `status = <new>` | NO | Correct |
| `apps/web-platform/server/agent-runner.ts:447` (inactivity sweep) | `status = 'completed'` | NO (archive-only trigger) | **Slot-leak path** — deferred to follow-on issue (Phase 6 step 2) |
| `apps/web-platform/server/ws-handler.ts:198` (supersede-on-reconnect) | `status = 'completed', last_active` | NO | Already calls `releaseSlot` explicitly (line 184); covered |
| `apps/web-platform/server/ws-handler.ts:891` (close_conversation) | `status = 'completed', last_active` | NO | Already calls `releaseSlot` explicitly (line 896); covered |

If the work-skill discovers any additional writers, append rows to this
table and update the PR body.

### Phase 5 — Compound Capture

1. Write learning file at
   `knowledge-base/project/learnings/bug-fixes/<topic>.md`. Topic:
   "Slot lifecycle invariants must live at the DB layer when multiple writers
   bypass the application path." Cite this PR.
2. Decide if any AGENTS.md rule is warranted. **Default: no** —
   discoverability exit applies. The bug surfaced as a hard 4010 close with a
   clear product-visible error; future authors won't silently miss this. The
   trigger itself is the enforcement mechanism going forward.

### Phase 6 — Tracking Issues + Ship

1. **Primary bug.** File a GitHub issue describing the user's reported
   scenario (archive does not release slot), link the user's report from
   jean.deruelle@jikigai.com, and include `Closes #<issue-number>` in the
   PR body.
2. **Follow-on issue (deferred).** File a separate GitHub issue tracking
   the inactivity-sweep slot leak in
   `apps/web-platform/server/agent-runner.ts:442-464` (the
   `startInactivityTimer` bulk UPDATE). Title:
   "fix: inactivity sweep leaks concurrent-conversation slots". Reference
   the resolution path: either add explicit `releaseSlot` calls inside the
   sweep loop, OR add `acquireSlot` to the `resume_session` WS handler so
   the trigger can safely fire on `status='completed'` transitions too.
   Milestone: stability backlog. Reference this PR via `Ref #<this-PR>`.
3. Roadmap impact: none — this is a stability fix in an existing Phase
   (the Command Center conversation surface, already in production).
4. Standard ship pipeline.

## Test Scenarios

| # | Scenario | Pre-fix behavior | Post-fix behavior |
|---|---|---|---|
| 1 | Free-tier user archives 1 of 1 conversations, then starts a new one | `cap_hit` close (4010) | `start_session` succeeds |
| 2 | Free-tier user marks status='completed' (without archiving) on 1 of 1, starts a new one | `cap_hit` (slot held) | `cap_hit` (slot held — INTENDED; resume_session does not re-acquire) |
| 2a | Free-tier user marks status='completed' THEN archives, starts a new one | `cap_hit` | `start_session` succeeds (trigger fires on archive) |
| 3 | Solo-tier user (cap 2) holds 2, archives 1, starts a 2nd new one | `cap_hit` until cron tick | `start_session` succeeds immediately |
| 4 | MCP agent calls `conversation_archive` then `start_session` for a new conversation under same user | `cap_hit` | `start_session` succeeds |
| 5 | User unarchives an archived conversation while at cap | (no slot leak — slot was released by trigger on archive) | new `start_session` for that thread re-acquires a slot via `resume_session` path; existing behavior unchanged |
| 6 | `release_conversation_slot` is called twice (trigger + WS handler `close_conversation`) | n/a | DELETE-based RPC is idempotent; second call is no-op |
| 7 | Archive UPDATE that does NOT change `archived_at` (touches only `last_active`) | n/a | trigger does not fire (`WHEN` clause filters; per-row body re-checks) |
| 8 | Status UPDATE to `'failed'` (not archived) | slot still held | unchanged — trigger fires only on `archived_at` transitions |

## Risks

1. **Trigger fires on bulk DELETE/UPDATE during data-cleanup operations.**
   AFTER UPDATE FOR EACH ROW means a 10K-row backfill that flips `archived_at`
   would call `release_conversation_slot` 10K times. **Mitigation:** the RPC
   is a single keyed DELETE with no advisory lock and no contention; cost is
   acceptable. We have ≤ a few hundred rows per user in practice. If we ever
   do a bulk archive sweep, the operator can `SET LOCAL session_replication_role
   = replica` to suppress triggers for the migration.

2. **Trigger could mask a real bug if `release_conversation_slot` is changed
   to do anything other than a keyed DELETE.** **Mitigation:** the function
   signature + body in migration 029 are stable; any change to
   `release_conversation_slot` semantics must update this trigger in the same
   PR. Add a comment to migration 029's `release_conversation_slot` body
   pointing at this trigger.

3. **`archiveConversation` hook continues to write client-side without
   invoking the slot RPC.** **Mitigation:** that's the intended behavior —
   the trigger is the single source of truth. We considered exposing a
   server-side `/api/conversations/:id/archive` endpoint that explicitly
   calls `releaseSlot`; rejected on the principle that one application layer
   shouldn't have to know about slot lifecycle.

4. **Postgres triggers can be silently dropped by a future migration.**
   **Mitigation:** add the trigger name to the post-migration assertion
   block recommended in `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
   if such an assertion exists; otherwise, the test suite fails loudly when
   the trigger is missing.

5. **`status='completed'` semantics — RESOLVED at deepen-plan.** A user who
   marks a conversation `completed` (without archiving) keeps the row visible
   in the active list (`archived_at IS NULL`). Releasing the slot here would
   mean: when the user `resume_session`'s the same conversation, the WS
   handler does NOT call `acquireSlot` (verified: line 812-862 of
   `apps/web-platform/server/ws-handler.ts` — `resume_session` sets
   `session.conversationId` directly with no slot acquire). The user could
   then run that conversation outside the slot ledger AND start a new one
   that takes the only slot — effectively cap+1 concurrent activity.
   **Decision: trigger fires on `archived_at` transitions ONLY.** The user's
   reported scenario is still fixed because the user archived after marking
   completed. A separate slot-leak — the inactivity sweep in
   `agent-runner.ts:442-464` flipping `waiting_for_user → completed` in bulk
   without calling `releaseSlot` — is a follow-on issue (Phase 6).

6. **Inactivity sweep slot leak (deferred follow-on).** The
   `startInactivityTimer` in `agent-runner.ts` bulk-flips
   `waiting_for_user → completed` after `INACTIVITY_TIMEOUT_MS` and calls
   `abortSession` for in-memory cleanup but does NOT call `releaseSlot`. The
   slot relies on the 120 s heartbeat-lapse sweep + pg_cron 1-minute sweep
   to be reclaimed eventually. This is a separate bug from the user's
   reported scenario but lives in the same problem space. File as
   `Ref #<issue-number>` in the PR body and milestone to the next stability
   pass — do not fold in here. The trigger-on-archive fix handles the user's
   scenario; the inactivity-sweep fix needs a different design (likely an
   explicit `release_conversation_slot` call inside the loop).

## Sharp Edges

- **Trigger fires on `archived_at` transitions ONLY** (decision finalized at
  deepen-plan). Do not extend the trigger body to also fire on
  `status='completed'` without first adding `acquireSlot` to the
  `resume_session` WS handler — otherwise a resumed completed-conversation
  runs outside the slot ledger.
- **Use `IS DISTINCT FROM` for nullable comparisons in the `WHEN` clause.**
  `OLD.archived_at = NEW.archived_at` returns NULL (not false) when both
  sides are NULL, which causes the trigger to MISS the NULL → non-NULL
  transition. Pin the WHEN clause as
  `WHEN (OLD.archived_at IS DISTINCT FROM NEW.archived_at AND NEW.archived_at IS NOT NULL)`.
- **Migration filename matches AC1.** The file is
  `036_release_slot_on_archive.sql` (NOT `..._or_complete.sql`) — the body
  is archive-only.
- The migration is forward-only (matches 029's stance). Rolling back requires
  a new migration that DROPs the trigger; do not rely on `supabase db reset`
  in prod.
- `release_conversation_slot` runs as SECURITY DEFINER. Any change to it that
  introduces a side effect beyond a keyed DELETE (e.g., emitting an event,
  writing audit log) means this trigger becomes a fan-in for that side effect
  on every archive — re-evaluate then.
- Vitest cannot exercise Postgres triggers natively. The Vitest assertions
  here are mocked; the **definitive** verification is the post-merge AC14
  prod-DB read. Document this gap explicitly in the learning file.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Section above is filled with the actual artifact,
  vector, and threshold.

## Research Reconciliation — Spec vs. Codebase

| Spec/Brainstorm Claim | Codebase Reality | Plan Response |
|---|---|---|
| Brainstorm `2026-04-29-command-center-conversation-nav-brainstorm.md` covers archive/release-slot semantics | False — that brainstorm is scoped to the chat-segment Recent Conversations rail; slot lifecycle is out of its scope | Treat this as a separate bug, not a follow-on of the rail feature |
| User report: "marked both as completed and archived them" | Verified — both `useConversations.updateStatus` and `useConversations.archiveConversation` perform direct client-side UPDATEs without slot release | Plan addresses both transitions via single trigger |
| `useConversations` hook already filters Realtime by `user_id=eq.${userId}` | True (line 239 in `use-conversations.ts`); no change needed | n/a |
| Migration 035 is the latest | Verified | Next migration is 036 |
| `release_conversation_slot` RPC exists and is idempotent | True (migration 029, line 193) — plain DELETE; calling twice is a no-op | Trigger calling it is safe even when `close_conversation` also fires |

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** assessed (in-pipeline; no subagent spawn — pipeline mode)
**Assessment:** This is a slot-ledger invariant that must live at the DB
layer. Multi-writer surfaces (hook, MCP tool, future API endpoint) make
application-layer enforcement brittle. AFTER UPDATE trigger calling the
existing SECURITY DEFINER `release_conversation_slot` is the right shape and
matches the migration-029 lineage. Risk #5 (`status='completed'` and
`resume_session` interaction) is the single non-trivial design call;
defaulting to `archive-only` until the resume-acquire path is verified is the
defensible choice.

### Product (CPO)

**Status:** assessed (in-pipeline)
**Assessment:** This is a `single-user incident` blast-radius bug. The user's
mental model (archive = "I'm done with this conversation, free up the slot")
matches the fix. CPO sign-off required at plan time per
`hr-weigh-every-decision-against-target-user-impact`. `user-impact-reviewer`
will be invoked at PR review.

### Legal (CLO)

**Status:** assessed (in-pipeline)
**Assessment:** No new data exposure. Slot ledger is per-user, server-only,
RLS-protected (read-only via `slots_owner_read`; writes are SECURITY DEFINER
RPC-only). No privacy-policy update needed.

### Product/UX Gate

**Tier:** none — no new UI or copy. Existing archive button continues to
behave; the only observable change is that the cap-reached error stops
appearing after archive.

## Open Code-Review Overlap

3 open scope-outs touch files in this PR's blast radius:

- **#2961** review: enforce conversations.repo_url immutability via Postgres
  trigger — *Defer.* This PR adds a different trigger to the same table; the
  immutability trigger is a separate concern. Update the issue with a
  re-evaluation note: "revisit after #036 lands; both are AFTER UPDATE
  triggers and can coexist."
- **#2962** review: extract memoized getServiceClient() shared lazy
  singleton — *Acknowledge.* No interaction with this fix. Rationale: this
  PR's footprint is migration + tests; refactoring the singleton is
  out-of-scope.
- **#2191** refactor(ws): introduce clearSessionTimers helper + add
  refresh-timer jitter — *Acknowledge.* No interaction with this fix. Same
  rationale.

## Plan Review Notes (for plan-review agents)

- This is a fix-class plan, not a feature plan. MINIMAL detail level is
  appropriate but I've used MORE because of the non-trivial Risk #5 + the
  need for the deepen-plan phase to validate the `status='completed'` design
  call.
- Do not propose adding a server-side `/api/conversations/:id/archive`
  endpoint to the plan — the trigger covers all writers and is the simpler
  solution. If a reviewer argues for the API endpoint, the rebuttal is in
  Risks §3.
- Do not propose adding a new AGENTS.md rule — discoverability exit
  applies.
