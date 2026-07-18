---
title: Concurrency-slot reap gated on agent-loop liveness, not socket focus
status: accepted
date: 2026-07-18
issue: null
supersedes: null
---

# ADR-123: concurrency-slot reap gated on agent-loop liveness, not socket focus

## Context

A Supabase Disk-IO write-reduction PR (2026-07-18) doubles the concurrency-slot heartbeat interval
(30 s → 60 s) to halve its steady-state WAL, and in lockstep raises the slot staleness threshold
120 s → 240 s (migration 133 + the shared `SLOT_STALENESS_THRESHOLD_SECONDS`). Raising the threshold
introduces a regression at the `single-user incident` brand-survival threshold: a user AT their
concurrency cap whose WebSocket socket crashes and then starts a **new** conversation is denied
(`CONCURRENCY_CAP`) for up to 240 s (was 120 s). The crashed conversation's slot is still
visible-active (not an orphan) and stale for < 240 s (not caught by the stale-heartbeat reap in
`tryLedgerDivergenceRecovery`), so neither existing recovery branch frees it, and the normal reconnect
mints a fresh conversation UUID (so `ON CONFLICT` never matches the crashed row).

The mitigation is an immediate, **threshold-independent** reclaim: reap the crashed slot on
`start_session` cap-hit without waiting out the staleness window. The design question is **which
liveness signal** decides "this slot is dead and reclaimable".

The naive predicate — "reap any slot whose conversation is not the socket's focused conversation" —
is **unsafe**. `sessions` (server/ws-handler.ts) is keyed by userId (one focused conversation per
socket), and the heartbeat only touches that focused conversation. But agent loops persist across
socket crashes in **two** process-local, conversationId-keyed registries: the cc-soleur-go runner
(`activeQueries`, via `hasActiveCcQuery`, server/cc-dispatcher.ts — the dominant path) **and** the
legacy `activeSessions` map (server/agent-session-registry.ts). On crash → reconnect →
new-conversation, the old conversation's loop keeps running (its grace-abort is cancelled by the
reconnect handler and short-circuited by the owning-host guard) while it is no longer focused. A
focus-only reap would kill that backgrounded-but-live loop and destroy its buffered replay
(feat-stream-since-disconnect #5273); it would likewise kill a conversation paused on a human
review gate (`reapIdle` deliberately keeps `awaitingUser` cc queries alive).

## Decision

A concurrency slot is reaped by the `start_session` recovery path **iff its conversation has no live
agent loop on this instance AND is not the focused socket conversation**. Concretely, reap slot for
`convX` when all hold:

- `convX` is not `sessions.get(userId).conversationId` and not `.pending?.id` (the focused-but-idle
  conversation has a fresh heartbeat but no loop — keep it), AND
- `!hasActiveCcQuery(convX)` (cc-soleur-go runner registry), AND
- no `activeSessions` entry matches `userId:convX[:leaderId]` (legacy registry, via
  `forEachSessionForConversation`).

This is encoded as `hasLiveAgentLoop(userId, convX)` in ws-handler.ts, consulted by the new
dead-socket reap class in `tryLedgerDivergenceRecovery`. The reap is threshold-independent (restores
immediate reclaim) and runs **only** on the cap-hit slow path (no steady-state WAL cost, consistent
with the PR's Disk-IO intent). Liveness is reconciled against **agent-loop** liveness, never
**socket focus**, because a slot's liveness must track whether work is actually running, not whether
a socket happens to be pointed at it.

## Rejected alternatives

- **Focus-only reap** (reap every slot whose conversation ≠ the focused conversation): conflates "no
  socket focused here" with "no loop here". Kills stranded-live loops after crash+reconnect and
  review-gate-paused conversations — the exact single-user incident this PR exists to avoid.
- **Descope the immediate reclaim** (accept the 240 s self-lockout): a real regression against the
  single-user-incident threshold when the agent-loop-liveness signal is already in-process and cheap
  to consult on the cold path. Deferring immediate reclaim buys nothing.

## Scope / consequences

- Replicas = 1 today, so "no live loop on this instance" == "no live loop anywhere". The cross-host
  generalization is ADR-068's coordinator-lease seam and is out of scope here.
- Adds SELECT-free filtering + bounded idempotent `releaseSlot` DELETEs on the cap-hit cold path
  only. No new hot-path write, no new steady-state WAL.
- Tests: `test/ws-handler-cap-hit-self-heal.test.ts` covers both the dead-socket reap (no live loop →
  reaped) and the protection property (live loop → not reaped).
