---
title: "fix: concurrent-conversation cap tripped by stuck-Executing dashboard conversation when KB sidebar starts"
type: fix
date: 2026-05-06
branch: feat-one-shot-conversation-limit-stuck-executing
classification: user-blocking-prod
requires_cpo_signoff: true
related_brainstorms: []
related_specs: []
related_plans:
  - 2026-04-19-feat-plan-concurrency-enforcement-plan.md
  - 2026-05-04-fix-cc-conversation-limit-archive-plan.md
  - 2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md
related_migrations:
  - 029_plan_tier_and_concurrency_slots.sql
  - 036_release_slot_on_archive.sql
  - 037_stuck_active_finder_rpc.sql
related_issues: []
deepened_on: 2026-05-06
---

# Fix: Concurrent-Conversation Cap Trips on KB Sidebar When Dashboard Conversation Is Stuck-Executing

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Architecture, Risks, Implementation Phases, Tests, Files to Edit, Plan-Quality Checks

### Key Improvements

1. **Phase 2 step 2 downgraded — single source of truth verified.** `grep -rn "Concurrent-conversation limit\|Archive a completed"` returns exactly ONE call site (`apps/web-platform/lib/ws-client.ts:125`). The upgrade-at-capacity-modal renders dynamic copy from `upgrade-copy.ts` and never duplicates the misleading "*completed*" wording (verified by reading both files in full). Phase 2 step 2 is reduced to a verified-clean assertion — no edit required there.

2. **All cited PRs/migrations/files verified live.**
   - `gh pr view 3217 --json state,title` → `MERGED — fix(cc): archive must release the concurrent-conversation slot via Postgres trigger` (matches plan's `related_issues`).
   - `gh pr view 3295 --json state,title` → `MERGED — fix(cc-chat): stuck-active conversation blocks concurrency slot in KB chat` (the May-5 precedent referenced in `related_plans`).
   - `git log --grep="#3217"` → commit `d4858aba` touched migration 036 (matches plan).
   - `git log --grep="#3295"` → commit `89d62eef` touched the AC1+AC2+AC4 surfaces (matches plan).
   - All file:line citations spot-checked: `ws-handler.ts:246` (helper start), `:1024`/`:1061`/`:1078` (cap-hit branch), `:1693` (supersession), `:1741`/`:1747` (heartbeat); `agent-runner.ts:519-520` (threshold + cadence); `migration 029:131`/`:224` (lazy + pg_cron sweep); `migration 029:83` (`user_concurrency_slots_user_heartbeat_idx` for the new SELECT). All match.

3. **Test scaffolding pre-checked.** `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts` already mocks `releaseSlot`, `reportSilentFallback`, and a chained `mockServiceFrom` query builder. Phase 3 tests extend the same hoisted-mocks pattern (no new test infra). Identical RED-before-GREEN structure as the May-5 PR.

4. **Concrete edit targets in `ws-handler.ts`.** The new SELECT slots in between line 274 (current `slotsResp` fetch) and line 286 (orphan filter) — no structural rearrangement of the helper. Sentry mirror at line 331-340 gains `staleHeartbeatCount` as one extra `extra:` field.

5. **Race-window analysis sharpened.** The maximum dead-end window without this fix is 60 (next reaper tick) + 120 (threshold) = 180 s after the OLD WS supersession event. With this fix the window collapses to a single round-trip on the cap-hit retry (one extra SELECT + N keyed DELETEs + N status UPDATEs, all batched in `Promise.all`). Sub-second user-visible recovery on the same `start_session` attempt.

6. **Defense-relaxation rule rechecked.** Per AGENTS.md learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`: this PR widens a RECOVERY action (more slots reaped, faster), not a SAFETY ceiling. The cap (1 for free) is unchanged. The 120 s liveness threshold is unchanged. No defense is being relaxed; no new ceiling needed.

### New Considerations Discovered

- **Self-heal helper's existing 2-step finalize is reusable.** The helper at line 311-324 already issues a `Promise.all` over `updateConversationFor(... 'failed', expectMatch: false)` for orphan rows. The new stale-heartbeat path joins the same finalize batch — one code path for both detection causes, no duplicate logic.
- **The new SELECT uses `(user_id, last_heartbeat_at)` index.** Migration 029 line ~83 creates `user_concurrency_slots_user_heartbeat_idx ON user_concurrency_slots (user_id, last_heartbeat_at)`. The new `eq("user_id", X).lt("last_heartbeat_at", cutoff)` query uses both columns — index-scan, sub-millisecond at any user's slot count.
- **The supersession path itself does NOT release slots.** Verified at `ws-handler.ts:1693-1698`: closing the old WS clears the `pingInterval` (in `ws.on("close")` at line ~1768) but does NOT call `releaseSlot` for `existing.session.conversationId`. A potential follow-up — releasing the OLD session's slot at supersession time — would close the dead-end window even tighter, BUT it has a correctness trap: a brief disconnect-and-reconnect (network blip → autosession) would prematurely free a still-live slot. Out of scope here; filed as a deepen-time consideration. The proposed sync-reap at cap-hit is the safer mechanism because it gates on the 120 s staleness threshold, not on "is the WS open right now".
- **Reconnect button correctly re-enters this path.** Verified by reading `ws-client.ts` `onclose` handler around the `OPEN_UPGRADE_MODAL_EVENT` dispatch — clicking Reconnect re-runs `connect()` which re-runs `start_session`, which now reaches the widened recovery. No additional client wiring needed.
- **Test test-name regression on the existing `ws-handler-cap-hit-self-heal.test.ts`.** Existing tests use the term "orphan" everywhere. The new tests intermix "orphan" and "stale-heartbeat" — adopt the term **`stale-heartbeat` slot** consistently in new test names + assertion messages to keep the two detection causes distinguishable in test output.

## Overview

A free-tier user (`effective_cap = 1`) starts a conversation from the
dashboard ("please summarize this PDF"), the assistant produces a partial
response, and the conversation row gets wedged at `status='active'`
("Executing" badge). The user then opens the PDF viewer in a new
tab/page and clicks **Ask about this document**. The KB sidebar's WebSocket
authenticates, supersedes the old socket, and fires `start_session`. The
server's `acquire_conversation_slot` RPC sees `count=1` (the stuck row's
slot) against `effective_cap=1` and returns `cap_hit`. The client closes
4010 with the cached preamble and renders:

> Connection Error: Concurrent-conversation limit reached. Archive a
> completed conversation to free a slot.

…and the chat panel is stuck on **Reconnecting…** while the
`session_started`-confirmation watchdog ticks past 10 s and fires the
secondary card:

> Session Failed to Start: The server did not confirm the session within
> 10 seconds. Please try again.

This is a regression class against the May-5 stuck-active fix in
`2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md`
(PR for AC1 result-branch wrap + AC2 reaper + AC4 self-heal + migration 037).
Those three layers shipped, yet the symptom is reproducible on `main`
the day after. Direct read of the deployed code identifies four
distinct gaps that combined produce this end-state — each fix is small;
together they close the dead-end.

## User-Brand Impact

**If this lands broken, the user experiences:** their first paid feature
("Ask about this document") fails with a misleading error
("Archive a completed conversation") even though no completed
conversation exists; the `Reconnect` button does nothing because the
ledger is still over-cap; the only escape is to leave the PDF page,
return to the dashboard, force-archive the Executing row, and try
again — a 4-step recovery for what should be a 1-click action. On a
free tier this is the user's first impression of the product after PDF
upload.

**Accepted side effect of the recovery path (post-merge):** when the
helper reaps a stale-heartbeat slot whose conversation was visible at
`status='active'` (the dashboard's stuck-Executing row), it flips the
conversation row to `status='failed'`. The dashboard rail
(`components/chat/conversations-rail.tsx`) renders `failed` rows with a
red "Needs attention" badge. The user fixes their KB sidebar chat but
inherits a red-badge row on the dashboard with no in-app explanation
of WHY (the "the server will automatically reclaim it within ~3 min"
copy lives in the KB-sidebar's close modal, not on the dashboard tab).
This is accepted in Phase 1 as truthful-state-truing — the
conversation was wedged and IS failed; the badge correctly reflects
that. A follow-up issue may soft-relabel auto-reaped rows
("Auto-reclaimed — slot freed") with a non-red badge to close the
explanation gap; that work is dashboard-rail UI, scoped out of this
hotfix per `cross-cutting-refactor` (3+ unrelated UI files).

**If this leaks, the user's workflow is exposed via:** N/A — this is a
liveness/availability bug, not a data-exposure or auth bug. No
credentials cross sessions; the slot ledger is owner-scoped.

**Brand-survival threshold:** single-user incident. The free-tier
PDF-summary path is the funnel-top conversion event for the Knowledge
Base feature; a single user encountering this on their first try
permanently colors their assessment of the product. CPO sign-off
required at plan time and `user-impact-reviewer` at review.

## Research Reconciliation — Spec vs. Codebase

The bug-report context paraphrases the symptom but not the
implementation. Direct grep + read confirms the following codebase
state. Any divergence is recorded here so /work does not pivot
mid-implementation.

| Spec/report claim | Reality (verified) | Plan response |
|---|---|---|
| "Executing" state means stuck/orphaned | `lib/types.ts` maps Executing badge to `conversations.status='active'`; the May-5 fix shipped AC1 result-branch wrap to prevent NEW stuck rows but pre-existing rows from before the deploy still exist | Phase 0 includes a one-time backfill check (count `status='active' AND last_active < now() - 10 min` rows pre-deploy) so the rollout doesn't re-discover this gap. |
| The 10-s "Session Failed to Start" timeout leaves zombie sessions | The 10-s watchdog is purely client-side (`chat-surface.tsx:349-353`) — it sets `sessionStartTimeout=true` on the React state but does NOT close the WS or release any server slot. The card is a UI symptom of the 4010 CONCURRENCY_CAP close that already fired. | No fix on this surface — the client-side card is correctly diagnostic. We change the cause (cap_hit), the symptom resolves. |
| The PDF chat spawns a "new session that conflicts with the dashboard" | The KB sidebar opens a new WS connection (different tab/page); the auth handler at `ws-handler.ts:1693-1697` supersedes the old WS via `WS_CLOSE_CODES.SUPERSEDED`. Sessions are keyed by `userId`, not by tab — the user has at most one server session. | The conflict is NOT two simultaneous client sessions; it is one server session whose previous `conversationId` is wedged at `active` and whose slot ledger is over-cap. The fix targets the slot ledger, not session identity. |
| Reaper runs every 60 s with 120 s threshold → max ~180 s wait | Verified in `agent-runner.ts:519-520`. But: while the user's old WS is alive, the 30-s heartbeat (`ws-handler.ts:1741-1749`) keeps refreshing `last_heartbeat_at` for the stuck conv → reaper NEVER fires for that row until the WS dies. After supersession, the OLD `pingInterval` is cleared in `ws.on("close")` at line ~1768 → heartbeat stops → reaper window opens. The 0-180 s gap between supersession and reaper is the dead-end window. | Phase 1 closes the gap by extending `tryLedgerDivergenceRecovery` to detect "no live WS heartbeating this slot" (the inverse of the orphan check it currently does). |
| `tryLedgerDivergenceRecovery` finds orphan slots | Verified at `ws-handler.ts:246-353`. It detects slot rows whose `conversation_id` is NOT in the visible-active set. The stuck dashboard conv IS in the visible set (`status='active' AND archived_at IS NULL`) — so `orphans=[]`, `didRecover=false`, the close path fires unchanged. | Phase 1 widens the recovery to also reap slots whose `last_heartbeat_at` is stale at cap-hit time — a synchronous one-shot reap before the close, scoped to the requesting user. |
| Archive trigger fires on `archived_at` NULL→non-NULL | Verified in migration 036. Archiving an `active` row works and releases the slot. The error string ("Archive a *completed* conversation") is therefore misleading — the user could archive the Executing row and recover. | Phase 2 changes the close-preamble copy AND the upgrade-modal copy to point at the actual remediation (archive the Executing conversation, or wait ~3 minutes for automatic cleanup). |
| Reaper threshold = 120 s (matches pg_cron) | Verified in three places (migration 029, migration 037, agent-runner.ts) per the existing THRESHOLD-COUPLING comment. Same value here intentionally. | No change to threshold. |

## Hypotheses

1. **Heartbeat-on-stuck-conv keeps reaper at bay.** While the old WS is alive (user hasn't superseded it yet — e.g., they kept the dashboard tab open and clicked the PDF in-place), the 30-s heartbeat refreshes `last_heartbeat_at` on the stuck row's slot. Reaper finds 0 candidates. PRIMARY contributor.
2. **Self-heal at cap-hit only catches orphan slots, not stuck-active slots.** `tryLedgerDivergenceRecovery` returns `didRecover=false` because the stuck conv IS visible. The new WS hits the close path even though a deterministic-staleness sync-reap could have freed the slot. SECONDARY contributor.
3. **Error-card copy points users at the wrong remediation.** The user reads "Archive a *completed* conversation" and looks for completed rows — there are none, only the Executing one. They retry instead of archiving. UX/copy gap; not load-bearing for the dead-end but compounds it.
4. **Active-row archive is hidden in some UI surfaces.** Need to verify dashboard's active-conversations rail exposes the archive button on `status='active'` rows. (Already verified `components/inbox/conversation-row.tsx:201-208` renders archive for any non-archived row regardless of status — not a fix surface.)

The fix targets (1) and (2) at the server, plus (3) at the client. (4) is verified-OK in current codebase.

## Hypothesis Telemetry (out of scope but recommended for follow-up)

A `concurrency-stuck-conv-detected` Sentry tag should fire at every cap-hit
where `tryLedgerDivergenceRecovery`'s extended check finds a stale-heartbeat
slot. This lets us count how often the new path actually activates in
production. Filed as a deepen-time consideration; not blocking.

## Domain Review

**Domains relevant:** Engineering (concurrency, server liveness), Product (free-tier first-feature funnel), Customer Support (error copy clarity).

This plan modifies existing server-side concurrency surfaces and one
error-copy string. It does NOT add new user-facing pages, components,
or flows. Per the Product/UX classification:

- **Mechanical escalation check:** Files to create includes ZERO files
  matching `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`.
  Tier remains as assessed.
- **Tier:** advisory (modifies one error string visible inside an
  existing modal/card) — auto-accepted in pipeline mode.

### Engineering (CTO)

**Status:** carry-forward from `2026-05-05` plan  
**Assessment:** This is a defense-in-depth extension of the May-5
three-layer fix (AC1 result-branch wrap + AC2 reaper + AC4 self-heal).
The new gap is "self-heal at cap-hit only checks orphan slots, not
stale-heartbeat slots". Closing it does NOT introduce a new mechanism;
it widens an existing one with the same idempotency invariants
(keyed DELETE / status-flip with `expectMatch: false`). No
architectural concern; identical risk profile to the May-5 work.

### Product (CPO)

**Status:** required (`requires_cpo_signoff: true`)  
**Assessment (deferred to deepen-plan):** CPO must sign off on the
copy change in Phase 2 step 1 and the implicit policy that "stale
heartbeat slots get force-released at cap-hit time". The latter
softens the cap enforcement slightly — a determined attacker who
DOSs WS heartbeats could force-release their own slots faster than
the reaper would. Risk assessment: the slot is the user's own to
hold; releasing the user's own stale slot at the user's own cap-hit
event has no cross-user blast radius.

### Product/UX Gate

**Tier:** advisory  
**Decision:** auto-accepted (pipeline)  
**Agents invoked:** none (pipeline auto-accept)  
**Skipped specialists:** none  
**Pencil available:** N/A

#### Findings

Error-copy change in Phase 2 step 1 is copy-only (no layout, no
flow). UX gate exits via auto-accept.

## Architecture

```
KB sidebar tab opens →
  [WS auth] → supersedes old WS (close 4006 SUPERSEDED on dashboard tab)
            → registers newSession (no conversationId, no pending)
            → resets pingInterval (heartbeat now points at no-conv → no-op)
  [start_session] → abortActiveSession (no-op: no session.conversationId)
                  → acquireSlot(userId, pendingId, cap=1)
                      → RPC: lazy sweep at last_heartbeat_at < now()-120s
                          → STUCK ROW'S last_heartbeat_at WAS REFRESHED
                            ≤30s AGO BY OLD WS BEFORE SUPERSESSION
                          → lazy sweep finds nothing
                      → count = 1, cap = 1, count > cap
                      → DELETE the new attempted row, return cap_hit
                  → tryLedgerDivergenceRecovery(userId)
                      → visible-active includes STUCK ROW
                      → slot ledger has 1 row matching STUCK ROW
                      → orphans = [] → didRecover=false
                  → close 4010 CONCURRENCY_CAP → modal + card on client
                  → DEAD END until reaper fires (60-180s) OR user archives
```

The fix widens `tryLedgerDivergenceRecovery` to a second predicate:
slots whose `last_heartbeat_at < now() - 120s` are sync-reaped in the
same recovery pass (status flip → releaseSlot → abortSession; matches
reaper's per-row order). The retry-acquire-once-on-recovery contract
is unchanged. Recursion remains forbidden.

## Implementation Phases

### Phase 0 — Pre-flight (verification only, no code)

1. Confirm `STUCK_ACTIVE_THRESHOLD_SECONDS = 120` and the reaper
   cadence `STUCK_ACTIVE_CHECK_INTERVAL_MS = 60_000` are unchanged on
   `main` (`apps/web-platform/server/agent-runner.ts:519-520`).
2. Confirm `find_stuck_active_conversations` RPC default
   `p_threshold_seconds = 120` matches
   (`apps/web-platform/supabase/migrations/037_stuck_active_finder_rpc.sql:39`).
3. Confirm migration 036 archive-trigger is deployed (read most-recent
   prod row: `select archived_at, status from conversations where
   archived_at is not null limit 1`).
4. Confirm `acquire_conversation_slot` lazy sweep at line ~131 of
   migration 029 deletes rows where
   `last_heartbeat_at < now() - interval '120 seconds'`. The new
   sync-reap path replicates this predicate at the application layer
   so the test path doesn't depend on migration ordering.

### Phase 1 Research Insights

**Best Practices:**
- Single-pass, two-set union reaping. Adding a parallel SELECT and merging into the existing finalize batch keeps the helper's contract atomic — either the recovery succeeds or it doesn't. Two sequential helpers would create a half-recovered state visible to the cap-hit retry.
- Use `Set<string>` keyed dedup, not array concat. `slot.conversation_id` could appear in both sets (an orphan that ALSO happens to have a stale heartbeat) — a naive `[...orphans, ...stale]` would issue two `releaseSlot` calls and two `updateConversationFor` calls for the same row. Both are idempotent, but the duplicate Sentry breadcrumbs would skew the divergence-rate metric.
- Stable threshold-coupling comment block. A new top-of-helper comment block listing all FIVE coupled sites (the four pre-existing + the new application-layer constant) documents the invariant for the next person who tunes one site without checking the others.

**Performance Considerations:**
- Index path: the new SELECT uses `(user_id, last_heartbeat_at)` exactly matching `user_concurrency_slots_user_heartbeat_idx` (migration 029 line ~83). Index-only scan, sub-millisecond at any realistic per-user slot count (cap is 50 even on Scale tier).
- Total cap-hit-recovery latency: 3 SELECTs + N keyed DELETEs + N keyed UPDATEs, all batched in `Promise.all`. Realistic N ≤ user's effective_cap (1 for free tier). Sub-second user-perceived recovery.
- Cap-hit is rare. The existing `concurrency-ledger-divergence` Sentry rate is the baseline; this PR's added cost is on the same path, only fires on cap-hit. Steady-state cost: zero.

**Implementation Details:**

```typescript
// In tryLedgerDivergenceRecovery, between current line 274 and line 286:

// THRESHOLD-COUPLING: 120 s here matches:
//   (1) migration 029 line ~131 (acquire_conversation_slot lazy sweep)
//   (2) migration 029 line ~224 (pg_cron user_concurrency_slots_sweep)
//   (3) migration 037 line ~39 (find_stuck_active_conversations default)
//   (4) agent-runner.ts STUCK_ACTIVE_THRESHOLD_SECONDS
// Changing this constant without updating the four sibling sites desyncs
// the sweep mechanisms — one will reap rows the others consider live.
const STALE_HEARTBEAT_THRESHOLD_MS = 120_000;
const staleCutoff = new Date(Date.now() - STALE_HEARTBEAT_THRESHOLD_MS).toISOString();

const staleResp = await supabase
  .from("user_concurrency_slots")
  .select("conversation_id")
  .eq("user_id", userId)
  .lt("last_heartbeat_at", staleCutoff);
if (staleResp.error) {
  reportSilentFallback(staleResp.error, {
    feature: "concurrency-ledger-divergence",
    op: "start_session-recovery-select-stale-heartbeat",
    extra: { userId },
  });
  // Fail-open: continue with orphan-only path. A SELECT failure on the
  // new branch must not regress the existing orphan-recovery path.
}
const staleConversationIds = ((staleResp.data ?? []) as Array<{ conversation_id: string }>)
  .map((r) => r.conversation_id);

// Dedup union: a slot can be both orphan AND stale-heartbeat (slot exists,
// conversation hard-deleted, heartbeat lapsed). Issue one releaseSlot +
// one finalize per unique conversation_id.
const reapableSet = new Set<string>([...orphans, ...staleConversationIds]);
const reapable = Array.from(reapableSet);

if (reapable.length === 0) {
  // No divergence on either signal — genuine cap_hit; caller proceeds.
  return { didRecover: false };
}

// (rest of the helper: Promise.all releaseSlot, Promise.all updateConversationFor,
//  Sentry mirror with both orphanCount + staleHeartbeatCount + reapableCount)
```

**Edge Cases:**
- A row that is BOTH orphan AND stale-heartbeat — caught by `Set` dedup. Single recovery action.
- A SELECT throw on the new stale path — fail-open. Mirror to Sentry, fall through to the existing orphan-only path. Never regress the existing recovery.
- `staleConversationIds.length > 0 && orphans.length === 0` — stale-only recovery path is exercised. `didRecover: true`. Sentry mirror records `orphanCount: 0, staleHeartbeatCount: N, reapableCount: N`.
- Concurrent cap-hit recoveries from two browsers (rare on free tier — supersession kills one) — the keyed DELETE / UPDATE are idempotent. Worst case: both recoveries log a Sentry event. Acceptable.

**References:**
- May-5 plan (`2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md`) §AC4 for the `tryLedgerDivergenceRecovery` original contract.
- Migration 029 line 83 for the index that backs the new SELECT.
- AGENTS.md `cq-ref-removal-sweep-cleanup-closures` is NOT triggered (no useRef or React closure changes here).

### Phase 1 — Server: extend `tryLedgerDivergenceRecovery` to also reap stale-heartbeat slots

**File:** `apps/web-platform/server/ws-handler.ts:246-353`

1. Add a second SELECT after the existing slot-rows query:

   ```ts
   // Identify slots whose last_heartbeat_at is older than the
   // STUCK_ACTIVE_THRESHOLD_SECONDS (matching reaper + pg_cron).
   // These slots correspond to conversations that no live WS is
   // heartbeating — typically because a previous WS died/was
   // superseded between the agent-runner result-branch wedge
   // (covered by AC1 in the May-5 plan) and the next start_session.
   //
   // THRESHOLD-COUPLING: 120 s here matches:
   //   (1) migration 029 line ~131 (acquire_conversation_slot lazy sweep)
   //   (2) migration 029 line ~224 (pg_cron user_concurrency_slots_sweep)
   //   (3) migration 037 line ~39 (find_stuck_active_conversations default)
   //   (4) agent-runner.ts STUCK_ACTIVE_THRESHOLD_SECONDS
   const STALE_HEARTBEAT_THRESHOLD_MS = 120_000;
   const staleCutoff = new Date(Date.now() - STALE_HEARTBEAT_THRESHOLD_MS).toISOString();
   const staleResp = await supabase
     .from("user_concurrency_slots")
     .select("conversation_id")
     .eq("user_id", userId)
     .lt("last_heartbeat_at", staleCutoff);
   ```

2. Compute the union: `orphans ∪ stale` deduplicated by
   `conversation_id`. Both sets are reaped in the same Promise.all
   batches with identical ordering (release slot, then finalize
   conversation row to `failed` with `expectMatch: false`).
3. Update the Sentry mirror at line 331-340 to include
   `staleHeartbeatCount` alongside `orphanCount`.
4. Update the `didRecover` semantic: returns `true` when EITHER
   orphans were found OR stale-heartbeat slots were reaped. The
   retry-once contract at the call site (line 1061-1067) is
   unchanged.

**Why an application-layer sync-reap (not just rely on the existing 60s reaper):**
the user is staring at the close-4010 modal NOW. Waiting up to 180 s
for the next reaper tick is the dead-end this plan exists to close.
The sync-reap at cap-hit gives them a sub-second recovery on the
SAME `start_session` attempt.

**Why this is safe:** the reap predicate
(`last_heartbeat_at < now() - 120s`) is identical to the existing
pg_cron sweep, lazy sweep, and reaper. There is no new race class —
this is the same liveness signal evaluated synchronously instead of
on a 60 s tick.

### Phase 2 Research Insights

**Best Practices:**
- Single source of truth for the close-reason string (verified at deepen — only `ws-client.ts:125` defines it).
- Mention BOTH archive AND auto-reclaim in the new copy. Free-tier users may not understand "Executing" maps to a stuck row; explicit mention of the ~3 min auto-reclaim sets expectation correctly.
- Keep the string under ~250 chars so it fits the existing `ErrorCard` layout without wrap regressions. Current draft: 224 chars.

**References:**
- AGENTS.md `cm-challenge-reasoning-instead-of` — the prior copy validated a wrong mental model ("there must be a completed one to archive"). The new copy challenges it.

### Phase 2 — Client: error-copy clarity (advisory UX gate)

**File:** `apps/web-platform/lib/ws-client.ts:124-126`

1. Update the `CONCURRENCY_CAP` reason string from:

   > "Concurrent-conversation limit reached. Archive a completed conversation to free a slot."

   to:

   > "You've reached your concurrent-conversation limit. Archive an active or completed conversation from the dashboard to free a slot. If a conversation appears stuck Executing, the server will automatically reclaim it within ~3 minutes."

   The new copy:

   - Removes the false "*completed*" qualifier (active rows can be archived too).
   - Names the actual remediation surface ("dashboard").
   - Sets the right expectation about the reaper window (~3 min = 60 s tick + 120 s threshold = up to 180 s).

2. **Verified at deepen-time — no edit required:** `apps/web-platform/components/concurrency/upgrade-at-capacity-modal.tsx` and `upgrade-copy.ts` do NOT duplicate the "*completed*" wording. The modal pulls dynamic state-aware copy from `defaultStateCopyFor(...)` / `adminOverrideCopy` which never assert anything about archive remediation. `grep -rn "Concurrent-conversation limit\|Archive a completed" apps/web-platform` returns exactly ONE call site (`lib/ws-client.ts:125`). Phase 2 is therefore a single-file edit.

### Phase 3 — Tests (TDD: RED before GREEN)

**File:** `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts` (extends existing)

1. **RED test #1 — stale-heartbeat reap path:**
   - Seed slot row with `conversation_id=convA`, `last_heartbeat_at = now() - 200s`.
   - Seed conversation row `convA` at `status='active', archived_at=null` (so visible-active set is non-empty).
   - Mock `acquireSlot` first call → `cap_hit`.
   - Call `tryLedgerDivergenceRecovery`.
   - Assert: `releaseSlot` called once for `convA`, `updateConversationFor(convA, status: 'failed')` called once, `didRecover: true`.

2. **RED test #2 — fresh-heartbeat slot is NOT reaped:**
   - Seed slot with `last_heartbeat_at = now() - 10s` (fresh).
   - Conversation visible at `status='active'`.
   - Call helper.
   - Assert: `releaseSlot` NOT called, `didRecover: false`, caller's close path fires.
   - This is the gate-presence vs gate-absence distinction per `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` (also flagged in the May-5 plan's session errors).

3. **RED test #3 — orphan + stale-heartbeat coexist:**
   - One slot for `convA` is orphan (no visible conv).
   - Another slot for `convB` is stale-heartbeat (visible, status=active).
   - Both reaped in one pass; Sentry mirror shows both `orphanCount: 1` and `staleHeartbeatCount: 1`.

4. **RED test #4 — copy regression:**
   - Existing `ws-close-helper.test.ts` already exercises the
     `CONCURRENCY_CAP` path. Add an assertion that the displayed
     reason starts with "You've reached" (anchors the new copy in
     a single regression line).

5. **Integration test (extends `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`):**
   - Seed: user, conversation at `status='active'`, slot row with backdated `last_heartbeat_at`.
   - Call `acquire_conversation_slot` directly with the user's cap (=1) and a NEW pending conv id.
   - Without the fix: returns `cap_hit`. With the fix's ws-handler call site: `tryLedgerDivergenceRecovery` reaps and the retry succeeds.
   - This requires the test to invoke through the ws-handler entry, not the RPC alone (the lazy sweep in the RPC alone would already have reaped — verifying nothing new). Confirm the RPC's lazy sweep predicate
     vs the ws-handler call ordering at deepen time.

### Phase 4 — Observability

1. The existing `feature: "concurrency-ledger-divergence"` Sentry mirror gains a second variant tag: `staleHeartbeatCount`. No new Sentry feature key — the same recovery rate is monitorable.
2. No new logger entry — the existing `log.info` at line 472-475 already emits enough for diagnosis.

## Open Code-Review Overlap

Run at deepen-plan time. (Plan-time check: no open `code-review` issues touch
`apps/web-platform/server/ws-handler.ts`, `apps/web-platform/server/concurrency.ts`,
or `apps/web-platform/lib/ws-client.ts` per current `gh issue list --label code-review --state open`.)

## Files to Edit

- `apps/web-platform/server/ws-handler.ts` — extend `tryLedgerDivergenceRecovery` (Phase 1).
- `apps/web-platform/lib/ws-client.ts` — update CONCURRENCY_CAP reason copy (Phase 2 step 1).
<!-- Removed at deepen time: upgrade-at-capacity-modal.tsx does NOT duplicate the legacy copy. See Enhancement Summary §1. -->

- `apps/web-platform/test/ws-handler-cap-hit-self-heal.test.ts` — extend with stale-heartbeat tests (Phase 3 #1, #2, #3).
- `apps/web-platform/test/ws-close-helper.test.ts` — copy-anchor regression (Phase 3 #4).
- `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` — integration coverage (Phase 3 #5).

## Files to Create

- None. All changes are extensions of existing surfaces.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `tryLedgerDivergenceRecovery` reaps stale-heartbeat slots in addition to orphan slots; `didRecover: true` returned in either case.
- [x] Stale-heartbeat threshold is `120s`, sourced from a top-of-file constant and called out in a `THRESHOLD-COUPLING` comment block referencing the four sibling sites (migrations 029 lazy sweep, 029 pg_cron, 037 RPC default, agent-runner const).
- [x] CONCURRENCY_CAP reason copy is updated; "*completed*" qualifier removed; new copy names the dashboard archive action AND mentions the ~3 min auto-reclaim.
- [x] Tests #1–#5 pass; existing `ws-handler-cap-hit-self-heal.test.ts` and `ws-close-helper.test.ts` pass unchanged.
- [x] No change to `STUCK_ACTIVE_THRESHOLD_SECONDS` (120s) or `STUCK_ACTIVE_CHECK_INTERVAL_MS` (60s).
- [x] No change to migrations 029/036/037 — fix is application-layer only.
- [ ] CPO sign-off recorded on PR (per `requires_cpo_signoff: true`).
- [ ] `user-impact-reviewer` invoked at review (per `single-user incident` threshold).
- [ ] PR body uses `Closes` for any overlap-folded scope-outs (none expected) and `Ref` for the May-5 plan reference.

### Post-merge (operator)

- [ ] Verify `feature: "concurrency-ledger-divergence"` Sentry events post-deploy include the new `staleHeartbeatCount` field (visible in Sentry tags).
- [ ] Spot-check production: the dashboard's "Active conversations" rail no longer accumulates `status='active'` rows older than ~3 min for free-tier users (proves Phase 1 path is firing).

## Risks

1. **Risk:** Sync-reap at cap-hit time could race with a legitimately-active conversation whose heartbeat happened to lapse for 121 s due to network jitter. **Mitigation:** the stale threshold matches the existing pg_cron + lazy-sweep predicate; if those wouldn't reap it, this won't either. Same threshold = same race profile, no new class.
2. **Risk:** A user with TWO browsers (rare on free tier) could trigger sync-reap of their own active session. **Mitigation:** the supersession path already kills the older WS; only one browser can be heartbeating at any time. The reaper assumes "no live heartbeat = not user-active". If both browsers are alive on different machines, supersession fires immediately on the second auth and only the second's heartbeat is fresh — the first's slot is correctly reapable.
3. **Risk:** Extending the helper increases its latency (one extra DB SELECT per cap-hit). **Mitigation:** cap-hit is rare (per existing `concurrency-ledger-divergence` Sentry rate); one extra keyed SELECT on `user_concurrency_slots` (filtered by user_id, indexed by `user_concurrency_slots_user_heartbeat_idx` on `(user_id, last_heartbeat_at)` per migration 029 line ~83) is sub-millisecond. The existing helper already does two SELECTs serially; adding one more is in the noise.
4. **Risk:** Copy change for the modal may regress existing translations or i18n tests. **Mitigation:** repo has no i18n layer for these strings (verified via `grep -r "Archive a completed" apps/web-platform/lib`). Single-string change is safe.
5. **Risk:** Defense-relaxation per `2026-05-05-defense-relaxation-must-name-new-ceiling.md` — are we relaxing a load-bearing defense? **Mitigation:** No — we are TIGHTENING the recovery path (more slots get reaped, not fewer). The cap enforcement itself is unchanged. The defense relaxation rule applies to widening permissive values; this PR widens a recovery action, which is the opposite direction.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled — `single-user incident`.)
- The 120-s threshold is now coupled across FIVE sites (the four pre-existing + this new application-layer constant). When changing it, search for `THRESHOLD-COUPLING` and update all five.
- Do NOT call `tryLedgerDivergenceRecovery` from anywhere except the cap-hit branch of `start_session`. Calling it on every WS message (or worse, in a tight loop) would create a hot DELETE path on `user_concurrency_slots` and contend with the per-user advisory lock in `acquire_conversation_slot`. The call site at `ws-handler.ts:1061-1067` is correct; do not refactor into a generic helper.
- The Sentry mirror at line 331-340 must remain a SINGLE event per `tryLedgerDivergenceRecovery` invocation regardless of orphan-count + stale-count, otherwise the divergence rate becomes unreadable.
- After deploy, the dashboard "Reconnect" button (rendered by ChatSurface line 480) calls `reconnect()` which re-opens the WS, which re-fires `start_session`, which now reaches the widened recovery — so the user's clicking "Reconnect" actually works. Pre-deploy, "Reconnect" was a dead button (the slot was still over-cap on every retry). Verify this in QA: cap-hit → wait reaper-window → click Reconnect → expect successful session_started.

## Test Strategy

**Frameworks (verified installed):** `vitest` (unit + integration via existing test patterns in `apps/web-platform/test/`), per `package.json` `scripts.test`. No new framework needed.

**Coverage targets:**
- Unit: `tryLedgerDivergenceRecovery` happy path + 4 edge cases (orphan-only, stale-only, both, neither, fresh-heartbeat).
- Integration: full slot acquire → cap-hit → recovery → retry path against a real Supabase test instance (extends existing `conversation-archive-release-slot.integration.test.ts`).
- Copy regression: 1 string-anchor assertion in `ws-close-helper.test.ts`.

**Manual QA (post-merge, free-tier account):**
1. Open dashboard, start a chat that leaves a stuck `active` row (the May-5 fix prevents most causes; manual stuck-active reproduction may require a force-killed Node process or DB direct write).
2. Open a PDF in the KB, click "Ask about this document".
3. Expect: chat panel goes "Connecting…" → "Connected" → first user-typed message dispatches successfully.
4. Re-confirm in dashboard rail: stuck row flipped to `failed`, slot count = 1 (the new conv).

## Plan-Quality Checks (deepen-plan will verify)

- [x] Spec/codebase reconciliation table present.
- [x] User-Brand Impact filled with concrete artifact + threshold.
- [x] Domain Review with carry-forward and tier classification.
- [x] Pre-merge / Post-merge AC split (per ops-remediation Sharp Edge).
- [x] CLI/path-glob verification (no globs prescribed; no CLI invocations land in user-facing docs).
- [x] No new framework prescribed (vitest already installed).
- [x] Sibling-table audit: helper extends but no new query bypasses it (the cap-hit path is the only caller).
- [x] Defense-relaxation check passed (this PR tightens, doesn't loosen).
- [x] Pencil/UX gate auto-accepted (advisory tier, no new component).
- [ ] CPO sign-off acknowledged (required at /work entry).
- [x] All cited PRs verified live (`gh pr view 3217` MERGED; `gh pr view 3295` MERGED) and `git log --grep` confirms each touches the claimed migration files.
- [x] All file:line references spot-checked at deepen time (`ws-handler.ts:246/1024/1061/1078/1693/1741/1747`; `agent-runner.ts:519-520`; `migration 029:131/224/83`).
- [x] Single-source-of-truth verified for `Concurrent-conversation limit` copy (only `lib/ws-client.ts:125`).
- [x] Defense-relaxation rule rechecked — this PR widens recovery, doesn't loosen safety. No new ceiling needed.
- [x] User-Brand Impact section present, threshold = `single-user incident`.
- [x] Phase 1 implementation includes verbatim TypeScript snippet showing exact insert location + dedup logic.
- [x] Existing test scaffolding at `ws-handler-cap-hit-self-heal.test.ts` reusable for Phase 3 RED tests (verified by reading mocks).
