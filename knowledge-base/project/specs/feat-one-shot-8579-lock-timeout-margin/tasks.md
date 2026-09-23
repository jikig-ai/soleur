---
title: "Tasks — serialize test-all advisory-lock waiters FIFO (#8579)"
branch: feat-one-shot-8579-lock-timeout-margin
issue: 8579
plan: knowledge-base/project/plans/2026-09-22-fix-tc-lock-timeout-fifo-queue-plan.md
lane: cross-domain
---

# Tasks

Derived from the plan after the deepen-plan pass. Every wait path must keep ADR-133's contract:
proceed-with-banner, never abort, `rc=0`. `scripts/test-all.sh` and
`plugins/soleur/scripts/lib/session-state.sh` are **not edited** — all mechanism work lives in
`scripts/lib/test-contention.sh`; all ordering assertions land in `scripts/test-contention.test.sh`.

## Phase 1 — ticket machinery (`scripts/lib/test-contention.sh`)

- [x] 1.1 Add `_tc_queue_dir <name>` — resolves `"$LOCK_DIR/<name>.queue.d"` after calling
     `_session_state_init_dirs` when declared; returns 1 when `LOCK_DIR` is unresolvable
     (stubbed session-state) so the caller can degrade.
- [x] 1.2 Add `_tc_ticket_mint <qdir>` — acquire `.alloc` via `flock -n` in a bounded counted-retry
     loop (no `flock -w` anywhere; #7697), mint `serial = 1 + max(numeric entries)`, create the
     file, `flock -x` it, write `pid worktree epoch` content — all inside the `.alloc` critical
     section; sweep unlocked tickets older than `TC_RUNTIME_CEILING_S` in the same hold.
- [x] 1.3 Add `_tc_queue_position <qdir> <serial>` — deliberately WITHOUT `.alloc`
  (advisory heartbeat reading; a stale value changes a log line, never a decision) — count strictly-earlier
     ticket files still `flock -n`-held; emits `position=N`.
- [x] 1.4 Add `_tc_queue_wait <qdir> <serial> <budget_s>` — poll head-check every
     `TC_QUEUE_POLL_S` (default 5); rc 0 at head, rc 1 at `TC_QUEUE_TIMEOUT` (default =
     `TC_LOCK_TIMEOUT`).
- [x] 1.5 Restructure `tc_acquire` between `LOCK_WAITING` and the `acquire_lock` call: mint a
     ticket when the queue resolves, emit `LOCK_QUEUED '<name>' ticket <serial>`; on degrade emit
     `LOCK_QUEUE_DEGRADED reason=<…>` and fall through to the existing acquire block unchanged.
- [x] 1.6 Queue-timeout arm emits `LOCK_QUEUE_TIMEOUT` then the existing
     `LOCK_CONTENDED_PROCEEDING` tail with `queue_timeout=1` appended (triage grep keys on
     `LOCK_CONTENDED`).
- [x] 1.7 Extend `_tc_wait_heartbeat`: bracket the whole wait (queue + lock), budget =
     `TC_QUEUE_TIMEOUT + timeout_s`, add `position=N`, switch token to `LOCK_WAIT_OVERRUN` once
     `waited ≥ timeout_s`. Keep the `waited=<N>s of <M>s` substring shape.
- [x] 1.8 Ticket fd held in a lib scalar for the process lifetime (mirror `_SESSION_LOCK_FDS`
     semantics — never close on return; kernel releases on exit/death). Every new failure arm ends
     `return 0` or degrades; every new `grep -c` carries `|| true`.

## Phase 2 — suite arms (`scripts/test-contention.test.sh`, new Phase 3b)

- [x] 2.1 T1 free-lock arm: `LOCK_WAITING` → `LOCK_QUEUED` → `LOCK_ACQUIRED` ordering; `rc=0`;
     ticket released on shell exit.
- [x] 2.2 T2/T3 serialization arm: held main lock, waiters A+B; A proceeds contended while its
     ticket is held; B emits no proceed line and reports `position=2`; after A's shell exits B
     becomes head and proceeds. Determinism via `await_held`-style `flock -n` probes on ticket
     files and trailing `sleep` to keep A's ticket held.
- [x] 2.3 T4 FIFO-order arm: three waiters minted in order; proceed order equals serial order.
- [x] 2.4 T5 SIGKILL arm: kill the head's whole shell; ticket releases with no reaper; next
     waiter proceeds.
- [x] 2.5 T6 queue-timeout arm: `TC_QUEUE_TIMEOUT=2` non-head → `LOCK_QUEUE_TIMEOUT` +
     `LOCK_CONTENDED_PROCEEDING queue_timeout=1`, `rc=0`.
- [x] 2.6 T7 degrade arm: session-state stub without `_session_state_init_dirs` →
     `LOCK_QUEUE_DEGRADED` + direct acquire, `rc=0`.
- [x] 2.7 T8 skip-path arms: kill switch / CI / no flock / no lib / no `acquire_lock` / empty name
     — `LOCK_WAITING` stays absent AND `*.queue.d` gains no entries.
- [x] 2.8 T9 heartbeat arm: `position=` present during queue stage; `LOCK_WAIT_OVERRUN` past
     `timeout_s`; self-terminate at combined budget.
- [x] 2.9 T10 mutation controls for Guard 1 rows 1–6 (dispatch stub, inverted probe direction,
     third-waiter gap, `.alloc`-section reorder, window-internal position probe, harness-row).
- [x] 2.10 T11 sweep arm: unlocked-and-old tickets removed under `.alloc`; held tickets never
     removed; numbering never regresses below a live ticket.
- [x] 2.11 Keep `pass_n + fails == cases`; bump the anti-vacuity assertion floor in lockstep with
     the new arms.

## Phase 3 — docs + ADR

- [x] 3.1 ADR-133 dated addendum: ticket-queue extension of Decision 3, `flock -n`-only probing
     (#7697), `TC_QUEUE_TIMEOUT` semantics, corrected `_RUN_START_EPOCH` ceiling arithmetic,
     mixed-version caveat.
- [x] 3.2 `plugins/soleur/skills/work/SKILL.md`: update the queued-run semantics (~:1144) and
     LOCK_WAITING stall-vs-queue triage (~:1508) for `position=`/`LOCK_WAIT_OVERRUN`.

## Phase 4 — verification

- [x] 4.1 `bash scripts/test-contention.test.sh` green.
- [x] 4.2 `bash scripts/test-all-capacity-signal.test.sh` green (stubbed session-state exercises
     the degrade path; AC14's `TC_LOCK_TIMEOUT > 2700` pin unaffected).
- [x] 4.3 `bash scripts/lib/repo-write-boundary.test.sh` and
     `bash plugins/soleur/test/fanout-suite-scope.test.sh` green (anchors untouched).
- [x] 4.4 `grep -n 'flock' scripts/lib/test-contention.sh` shows no new `-w` waits (AC9).
- [x] 4.5 `scripts/test-all.sh scripts` (or the suite-shard equivalent) green including the
     `scripts/test-contention` suite registered at `test-all.sh:1901`.
