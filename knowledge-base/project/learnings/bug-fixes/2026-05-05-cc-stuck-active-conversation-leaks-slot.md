---
module: KB Chat / Concurrency
date: 2026-05-05
problem_type: liveness_bug
component: server_websocket
symptoms:
  - "Conversation stuck in Executing badge for 10+ minutes"
  - "Free-tier user sees 'Concurrent-conversation limit reached' after one conversation"
  - "WS closes 4010 on Ask about this document despite user perceiving zero active threads"
root_cause: invariant_violation
resolution_type: code_fix
severity: high
tags: [cc-chat, concurrency, slots, agent-runner, ws-handler, stuck-active]
synced_to: []
---

# Learning: stuck-active conversation leaks concurrency slot

## Problem

A free-tier user (effective_cap=1) opens a PDF in the Knowledge Base, asks a question, and the assistant responds. Some downstream step in the result branch throws (sendToClient on a dead WS, syncPush failure, expectMatch:true status flip on a concurrently archived row, or the Node process is killed). The conversation stays at `status='active'` and the corresponding `user_concurrency_slots` row stays held — because the WS session is still alive its 30-second heartbeat keeps refreshing `last_heartbeat_at`, so neither the 120-s lazy sweep in `acquire_conversation_slot` nor the 1-min pg_cron sweep ever reclaims it. The next "Ask about this document" hits cap_hit and the WS closes with code 4010.

## Root Cause

Status transition is the LAST step in the agent-runner result branch. After `saveMessage` (line ~1079) there are six throw-eligible steps before `updateConversationStatus(..., "waiting_for_user")` (line ~1134) lands: cost RPC `.then` callback, two `sendToClient` calls, `syncPush` await, the status update itself (which throws on `expectMatch: true` 0-row), and the `session_ended` send. The pre-fix outer `catch` only fires `failed`-status when `controller.signal.aborted` is true — a clean throw from any of those six steps falls through unhandled, leaving the row at `active` and the slot stranded.

Compounding factors:

1. The startup-only `cleanupOrphanedConversations` runs once at boot — long-running deploys leave rows accumulating.
2. The pg_cron sweep checks heartbeat staleness, NOT conversation-row vs slot-row consistency, so an orphan slot whose conversation was hard-deleted sits forever as long as the WS session is alive.
3. The error message ("Archive a completed conversation to free a slot") points the user at the wrong remediation — the stuck row is not in the user's mental model of "completed".

## Resolution

Three independent fixes, in order of decreasing user-blast radius:

1. **Result-branch try/catch wrap (AC1).** `agent-runner.ts` now wraps the entire result-branch body in a try/catch that finalizes the conversation row to `waiting_for_user` (if `saveMessage` succeeded) or `failed` (if not), then calls `releaseSlot(userId, conversationId)`, then re-throws so the outer catch's existing side effects (sanitize → client `error` → status `failed` fallback) still run. The `assistantPersisted` boolean flips immediately after `saveMessage` resolves, so the catch knows whether to attempt `waiting_for_user` first.

2. **Periodic stuck-active reaper (AC2).** A new 60-s interval calls `find_stuck_active_conversations(p_threshold_seconds := 120)` (migration 037) — a SECURITY DEFINER RPC that returns conversations at `status='active'` with no slot row OR a stale-heartbeat slot row. Per-row order is status flip → `releaseSlot` → `abortSession`. The signal is slot-heartbeat staleness rather than `last_active` because long tool-heavy turns streaming partials don't update `last_active` and would otherwise be falsely reaped.

3. **Self-healing cap_hit recovery (AC4).** `tryLedgerDivergenceRecovery` runs in `ws-handler.ts` BEFORE the cap_hit close path. It SELECTs visible-active conversations and slot rows, finds slots whose `conversation_id` is not in the visible set, releases each orphan, and mirrors a single `feature: "concurrency-ledger-divergence"` Sentry event. The caller retries `acquireSlot` once. Recursion is forbidden — a second cap_hit falls through to the existing close path.

## Prevention

- **Sweep mechanisms must agree on a single liveness threshold.** The reaper threshold (120 s) and pg_cron threshold (migration 029, 120 s) match by design. Diverging thresholds create windows where one mechanism reaps and the other doesn't.
- **`last_active` is not a liveness signal.** It updates only on status writes and message inserts. A streaming agent turn does not refresh it. Use `user_concurrency_slots.last_heartbeat_at` (refreshed every 30 s by the WS handler) when the question is "is this conversation alive?".
- **Status transitions are the LAST step in the success path.** When a code path's terminal state write is preceded by N awaits or N sendToClient calls, every intermediate step is a wedge candidate. Wrap such bodies in try/catch with explicit terminal-state finalization, not just at the iteration boundary.
- **Self-healing branches must be observable.** Every recovery emits one Sentry event with a stable `feature` tag so the recovery rate is monitorable. A non-zero rate post-deploy means a NEW slot-leak class crept in — file an issue, don't let recovery silently absorb it.
- **AC2 (reaper) and AC4 (cap_hit self-heal) are co-required.** They are not independent layers — the system relies on AC4 to mask the AC2 race window during the worst-case 60-180 s reap interval (60 s tick + 120 s threshold). Shipping AC2 without AC4 would leave a user dead-ended at "Archive a completed conversation" during that window.
- **The 120 s liveness threshold is coupled across three sites** — migration 029 lazy sweep (line ~131), migration 029 pg_cron sweep (line ~224), and migration 037 RPC default (line ~39). The TS const `STUCK_ACTIVE_THRESHOLD_SECONDS` in `agent-runner.ts` and the SQL default in migration 037 carry coupling comments referencing the other sites so future changes desync visibly.

## Discoverability

This bug surfaced as a 4010 WS close + a visible "Executing" badge stuck for 10+ minutes. Both are clear product-visible signals — no hidden constraint. AGENTS.md does NOT need a new rule (discoverability exit applies). This learning file is the durable artifact.

## Related

- Plan: `knowledge-base/project/plans/2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md`
- Migration 029 — pg_cron sweep + acquire_conversation_slot
- Migration 036 — release-slot-on-archive trigger
- Migration 037 — `find_stuck_active_conversations` RPC (this PR)
- PR #3217 — archive-trigger slot release (commit `d4858aba`, migration 036; same incident class on `archived_at` transition)

## Session Errors

1. **Plan author cited non-existent PR `#3219`.** Plan attributed the archive-trigger slot-release work to #3219; git-history-analyzer verified via `git log --grep="#3219"` that #3219 does not touch slot/sweep logic — the actual precedent is #3217 (commit `d4858aba`, migration 036). **Recovery:** review caught the misattribution; corrected inline across plan, learning frontmatter, and Related section in commit `91a16a9e`. **Prevention:** when a plan cites "related PR/issue #N", verify with `gh pr view N --json title,state` (or `gh issue view N`) and `git log --grep="#N"` BEFORE finalizing. This is now enforced in the deepen-plan skill's Quality Checks (added in this session).

2. **Plan §3 cited an architecturally weak reason for rejecting a DB-level status trigger.** Plan said "resume_session does not call acquireSlot" — true but not load-bearing. The actual blocker is that many call sites (`cc-dispatcher`, `ws-handler.ts:212`/`:1177`, agent-runner status flip) issue `updateConversationFor` writes; a trigger releasing on `active → waiting_for_user` would race with a still-streaming agent that legitimately holds the slot for its next turn. **Recovery:** architecture-strategist surfaced the gap during plan review; reasoning rewritten inline in commit `ad45cc5a` to enumerate the race classes. **Prevention:** when a plan rejects an architectural alternative, the rejection MUST enumerate ALL race/correctness classes the alternative would introduce, not just one symptom. Discoverability exit applies — review caught it.

3. **Reaper RED test was vacuous gate-presence.** test-design-reviewer found that the reaper test asserted reapable rows ARE flipped to `failed`, but never proved unreapable rows are NOT flipped — i.e., the test verified the mock returned what the mock was told to return, not the gate logic. Per existing learning `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`, RED must distinguish gate-present from gate-absent. **Recovery:** added empty-RPC-returns case asserting NO finalize/releaseSlot/abortSession calls occur in commit `c6d43c2a`. **Prevention:** the `cq-write-failing-tests-before` rule and work-skill TDD Gate already mandate this — discoverability exit applies, no new rule.

4. **Missing partial index on `find_stuck_active_conversations`.** performance-oracle found the LEFT JOIN driver scans `idx_conversations_status` (low-selectivity over a status enum); needed partial `idx_conversations_active_unarchived ON conversations(id) WHERE status='active' AND archived_at IS NULL`. **Recovery:** added inline to migration 037 in commit `41710bbb`. **Prevention:** when adding a SECURITY DEFINER RPC that LEFT JOINs on a status predicate, check whether source-table indexes are appropriately partial to the predicate. Discoverable via performance-oracle review — exit applies.

5. **Outer catch missing `releaseSlot`.** pattern-recognition-specialist found `agent-runner.ts:1354+` outer catch flips conversation to `failed` but does NOT call `releaseSlot` for non-result-branch errors → slot leaks for up to 60 s waiting for the reaper. **Recovery:** added `releaseSlot` calls to controller-aborted-non-superseded and generic-error branches in commit `e9618445`. **Prevention:** when a function has multiple catch layers, each catch that finalizes terminal state should release any owned resources symmetrically. Discoverable via review — exit applies.

6. **`tryLedgerDivergenceRecovery` left orphan `status='active'` rows alone.** pattern-rec found the helper released slots but did not finalize the orphaned conversation rows, creating a 60 s window of `slot-released` + `conv-active`. **Recovery:** helper now also flips orphan conversations to `failed` in the same pass (commit `e9618445`). **Prevention:** when a helper enforces ledger consistency between two tables, it must converge BOTH tables in one pass. Discoverable via review — exit applies.

7. **5 of 12 review agents hit Anthropic rate limits** (security-sentinel, data-integrity-guardian, code-quality-analyst, semgrep-sast, user-impact-reviewer, code-simplicity-reviewer). Review skill's Rate Limit Fallback gate accepted partial coverage (7 substantive findings; reset at 21:40 Europe/Paris). **Recovery:** N/A — system constraint, not a recoverable error in this session. **Prevention:** future runs at peak hours could batch reviewers in waves to avoid simultaneous limits — review-skill optimization, out of scope here.
