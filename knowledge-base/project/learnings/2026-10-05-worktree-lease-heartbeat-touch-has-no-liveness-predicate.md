# Learning: `touch_worktree_lease` has no liveness predicate — a zombie heartbeat resurrects tombstones forever

## Problem

PR #9541's stale-resume recovery needed the dying query's `closeQuery` to
keep the worktree lease held so the synchronous re-dispatch could
re-acquire same-host keep-gen. The first fix-round attempt skipped
`record.handle.release()` entirely, reasoning that the heartbeat would
"self-terminate on 2 missed beats" once the retry's own close
tombstoned the row. Two fix-round seats independently refuted this:

- `release_worktree_lease` tombstones by setting `heartbeat_at =
  '-infinity'` while **keeping `host_id` and `lease_generation`**.
- `touch_worktree_lease` matches **only** `host_id` +
  `lease_generation` — no recency check ("No time predicate ⇒ no
  clock-skew false-zero", migration 116).
- So a still-beating handle's next touch succeeds on a tombstoned row,
  sets `heartbeat_at = now()`, and `held=true` — `consecutiveMisses`
  never increments, `onLost` never fires, and the `setInterval` runs for
  the process lifetime issuing a write every 50s while permanently
  pinning the row to this host.

A skipped release is therefore never "self-healing" — it is a leaked
interval plus a phantom-live lease row, and it fires even on paths with
no successor acquire (supersede, factory-throw, no-listener).

## Solution

`WorktreeLeaseHandle.detach()` — `settled = true` + `clearInterval` +
`unregisterHeldLease` with **no RPC**. The stale-resume close calls
`detach()` instead of `release()`: the row stays live for the retry's
keep-gen acquire (natural expiry is the fallback if no retry lands),
and nothing is left beating to resurrect a later tombstone. The
`_ccWorktreeLeases` map record is kept on `skipRelease` so the
factory-throw cleanup (`releaseCcWorktreeLease`) can still reach the
record — `release()` no-ops on a settled handle, which is the honest
240s natural-expiry fallback.

## Key Insight

**When a release mechanism is built as "stop heartbeat + tombstone",
skipping only the tombstone leaves the heartbeat alive — and a
heartbeat that ignores liveness state is worse than none.** Audit the
heartbeat's *match predicate*, not just the release path: ask "what
does a touch do to a dead row?" before concluding a skipped release is
safe. The same shape applies anywhere a liveness probe writes on
match-only semantics (heartbeats, keepalives, lock renewals).

## Tags
category: concurrency
module: server/worktree-write-lease.ts, server/cc-dispatcher.ts
