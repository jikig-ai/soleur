# Tasks — fix: test-all runtime ceiling and stale-sibling exclusion (#7869)

Plan: `knowledge-base/project/plans/2026-09-06-fix-test-all-lock-orphan-holder-plan.md`

## Phase 1 — Capacity first (RED before GREEN)

- [ ] 1.1 Write Guard 2 arms in `scripts/test-contention.test.sh` against a **synthetic procfs**:
      M8 (filter removed), M9 (inverted comparison), M10 (count filtered but report not),
      M11 (unreadable elapsed must still be counted), M12 (second stale sibling),
      H4 (zero-sibling fixture must fail, not pass empty), H5 (one fresh + one stale — refusal
      still fires on the fresh one). Confirm they are RED.
- [ ] 1.2 Add the ceiling constant and its environment seam to `scripts/lib/test-contention.sh`.
- [ ] 1.3 Filter siblings whose measured `elapsed_s` exceeds the ceiling out of the
      `TC_SIBLING_RUN_COUNT` promotion, reusing the rows `_tc_scan_procs` already emits — no
      second `/proc` walk.
- [ ] 1.4 Emit `SOLEUR_TEST_ALL_STALE_SIBLING_EXCLUDED` naming pid and elapsed, and keep the
      reported sibling list consistent with the filtered count (M10).
- [ ] 1.5 Confirm Guard 2 arms are GREEN.

## Phase 2 — Guard 1 suite (RED before GREEN)

- [ ] 2.1 Create `scripts/test-all-runtime-ceiling.test.sh` with M1–M7 and H1–H3, derived from
      the plan's design rather than from the implementation's eventual shape.
- [ ] 2.2 Include the M4 arm explicitly: terminate with a **live suite child**, then assert a
      fresh acquirer obtains the lock. This is the only arrangement in which the inherited-fd
      defect is observable.
- [ ] 2.3 Include the M3 arm: no process-group signal is introduced.
- [ ] 2.4 Confirm the suite is RED.

## Phase 3 — The ceiling (GREEN)

- [ ] 3.1 Initialise the run-start timestamp at **top level, before the acquire/epilogue splice
      window** — two sibling suites replace that window wholesale and neuter the acquire, so a
      variable first assigned inside it aborts their sandboxes under `set -u`.
- [ ] 3.2 Add the elapsed check to `run_suite`'s body; fail toward keep-running on an unreadable
      reading and emit `SOLEUR_TEST_ALL_CEILING_UNAVAILABLE`.
- [ ] 3.3 On crossing: emit `SOLEUR_TEST_ALL_RUNTIME_CEILING` (with elapsed and ceiling) **first**.
- [ ] 3.4 Then terminate descendants of the run **one pid at a time, never as a process group** —
      under lefthook the inherited pgid's leader is `git commit`, and a group signal strands
      `.git/index.lock`.
- [ ] 3.5 Emit the summary line and mark the repo-write boundary reported, so the terminating run
      does not skip the summary or trigger an unrelated boundary NOTE.
- [ ] 3.6 Exit 3.
- [ ] 3.7 Confirm Guard 1's suite is GREEN.

## Phase 4 — Contract, ADR, registration

- [ ] 4.1 Widen the exit-code contract comment in `scripts/test-all.sh` so 3 covers a run that
      terminated itself, not only `>= 1` killed suite. Do not touch `suite_exit_class`.
- [ ] 4.2 Amend ADR-133: the dead-holder rejection stands and was re-measured; it does not
      quantify over a live-but-ownerless holder, which is bounded by runtime rather than by any
      ownership inspection.
- [ ] 4.3 Register `test-all-runtime-ceiling` in the runner's suite list.
- [ ] 4.4 Run the affected suites: `test-all-runtime-ceiling`, `test-contention`,
      `test-all-killed-classification`, `test-all-capacity-signal`, `suite-exit-class-parity`.
- [ ] 4.5 Verify every acceptance criterion in the plan.
