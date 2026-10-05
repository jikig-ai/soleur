---
feature: lock-timeout-no-isolation
date: 2026-08-12
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-08-12-lock-timeout-no-isolation-brainstorm.md
related_adrs: ["ADR-133"]
related_issues: ["#7454", "#7476", "#7376", "#7432", "#6828"]
---

# Spec — instrument the `test-all.sh` advisory-lock wait

## Problem Statement

`scripts/test-all.sh` takes a cross-worktree advisory lock (ADR-133 Decision item 3) before running
the gate. The lock is deliberately fail-open: on timeout it prints `LOCK_CONTENDED_PROCEEDING` and
proceeds, never aborting. `TC_LOCK_TIMEOUT` defaults to 900 s
(`scripts/lib/test-contention.sh:51`).

Measured 2026-08-11 and recorded in the ADR-133 addendum: a run waited the **full 900 s** and then
proceeded **while three sibling runs executed concurrently** (3,775 s / 5,787 s / 5,763 s elapsed).
It paid 15 minutes of wall-clock on the ship critical path and obtained zero isolation.

Mechanically, a 900 s wait budget cannot reliably serialise a critical section of ~2,700 s
(uncontended) to 5,787 s (contended), and the effect is self-reinforcing: each waiter that proceeds
lengthens the holder's run.

**The blocking gap is that nobody can tell how often the wait succeeds.** Lock-wait duration is
recorded nowhere: `tc_acquire` emits a status line per outcome with no elapsed time
(`test-contention.sh:534, 541, 546, 552, 557, 562`), `TEST_TIMING_LOG` carries per-suite ms and
tmpfs/bytes deltas but no wait datum, and `session-state.sh:acquire_lock` (`:90-120`) is a blocking
`flock -w` returning only a status code. The two candidate fixes — raise the timeout, or short-circuit
a provably-futile wait — point in **opposite directions** depending on that unmeasured ratio.

The 900 s value itself was introduced in PR #6828 with no recorded derivation, and is documented
nowhere operator-facing.

## Goals

- G1. Make the lock-wait observable: every `tc_acquire` invocation records how long it waited and
  how it ended.
- G2. Disclose a possible multi-minute wait to the operator/agent **before** it is incurred.
- G3. Leave the lock's mechanism and fail-open behaviour byte-for-byte unchanged.
- G4. Leave a recorded, evidence-triggered decision point for the mechanism change.

## Non-Goals

- NG1. `/tmp`-headroom admission control, **including** the "headroom bypass on top of the mutex"
  named in the ADR-133 addendum. A bypass is admission control and inherits the TOCTOU and
  non-monotonic-degradation objections. Gated behind #7454 item 3's evidence bar.
- NG2. Changing `TC_LOCK_TIMEOUT`'s value.
- NG3. Short-circuiting the wait on sibling detection or holder age.
- NG4. Abort-on-timeout — already REJECTED in ADR-133 Alternatives Considered.
- NG5. Concurrency-N semaphores, per-suite locks, fair-share queueing, defaulting the lock off.
- NG6. Any change to the CI exemption or the `SOLEUR_DISABLE_SESSION_STATE` kill switch.
- NG7. Any change to `#7376` / `#7432` parallel-suite flake work.
- NG8. Re-opening any of #7454's three deferred items — all three triggers verified unfired
  2026-08-12.

## Functional Requirements

- **FR1.** `tc_acquire` records elapsed wait seconds on the **acquired** path, alongside the existing
  `LOCK_ACQUIRED` banner.
- **FR2.** `tc_acquire` records elapsed wait seconds on the **timed-out** path, alongside the existing
  `LOCK_CONTENDED_PROCEEDING` banner.
- **FR3.** Both records carry the terminal outcome as a distinguishable value (acquired vs
  timed-out), so the ratio is derivable without parsing prose.
- **FR4.** The early-exit paths (`LOCK_SKIPPED_DISABLED`, `LOCK_SKIPPED_CI`, `LOCK_UNAVAILABLE`)
  are distinguishable from a zero-second acquisition — a skip is not a fast win.
- **FR5.** Before the wait begins, the operator-facing output states the maximum wait that may be
  incurred, so a long wait is legible as a queue rather than a hang.
- **FR6.** The record lands on a channel already pulled by existing tooling (`TEST_TIMING_LOG` is the
  candidate; see OQ1 — it is a run-boundary datum, not per-suite).

## Technical Requirements

- **TR1.** No change to `acquire_lock` in `scripts/lib/session-state.sh`. That primitive is shared
  (four skills wrap `gh pr merge --auto` via `with_lock merge-main 600`) and ships inside the plugin
  per ADR-178; widening it is out of scope (see OQ3).
- **TR2.** All `tc_acquire` exit paths continue to `return 0`. The advisory contract — no failure mode
  of the lock can prevent or wedge a test run — is preserved exactly.
- **TR3.** Instrumentation must not create files, take locks, or delete anything beyond the existing
  `TEST_TIMING_LOG` append, per ADR-133 Decision item 1's observe-only property.
- **TR4.** `TEST_TIMING_LOG` writes must respect the redirection discipline established by PR #7441 —
  a sandboxed test arm must never append its rows into the operator's real timing log (see the
  documented 12 spurious `skip=not_in_diff` + 26 spurious `bytes_tmp=0` rows in
  `scripts/test-all-infra-coverage-notice.test.sh`).
- **TR5.** The five existing arms in `scripts/test-contention.test.sh` (`:428-527`) must continue to
  pass: Arm 10 positive control, Arm 11 advisory timeout (AC4), Arm 12 kill switch (AC3), Arm 13 CI
  exemption + mutation control (AC5), Arm 14 kernel release (AC5b). They pass explicit short timeouts
  (2–3 s), so they exercise both new record paths cheaply.
- **TR6.** New assertions must cover both the acquired and timed-out record paths, and a negative
  control distinguishing a skip from a zero-second acquire (FR4).
- **TR7.** Record the outcome as a further **addendum to ADR-133**, not a new ADR — this amends
  Decision 3's observability, not its mechanism.

## Acceptance Criteria

- AC1. A run that acquires the lock immediately emits a wait record with a near-zero duration and an
  acquired outcome.
- AC2. A run that times out emits a wait record whose duration is the configured timeout and whose
  outcome is timed-out.
- AC3. A run under `SOLEUR_DISABLE_SESSION_STATE=1` and a run under `CI` each emit a record
  distinguishable from AC1.
- AC4. Existing arms 10–14 pass unchanged.
- AC5. The maximum-wait disclosure (FR5) appears before the wait, verifiable by output ordering.
- AC6. No sandboxed test arm's rows appear in the operator's real `TEST_TIMING_LOG` (TR4).

## Open Questions

- **OQ1.** Row shape for a run-boundary datum on a per-suite channel.
- **OQ2.** Minimum number of runs before the acquire-vs-timeout ratio is decidable — state a floor,
  do not leave "enough" undefined. Note this is an existence bar (see both outcomes at least once),
  not the statistical bar #7454 item 3 guards.
- **OQ3.** Whether the same instrumentation belongs on `session-state.sh:acquire_lock` for the
  `merge-main` consumers, or stays at the `tc_acquire` layer only.

## Deferred

The mechanism change itself — raise `TC_LOCK_TIMEOUT` above the critical section, versus
short-circuit a provably-futile wait using holder age (the data `tc_preamble` already computes at
`test-all.sh:626` but does not pass to `tc_acquire` at `:633`). Filed as a follow-up whose
re-evaluation trigger is the telemetry this spec ships.

Note the two options are mutually exclusive and must not both ship. Raising inherits a documented
non-convergent pattern (`2026-03-20-docker-healthcheck-start-period-for-slow-init.md`: three
successive timeout raises against a variable duration that never converged). Short-circuiting must
key on holder **age**, not on mere sibling presence — "skip when a sibling is detected" collapses to
never locking when locking would matter.
