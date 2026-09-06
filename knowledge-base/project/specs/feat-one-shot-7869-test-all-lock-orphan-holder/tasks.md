# Tasks — fix: test-all runtime ceiling and stale-sibling exclusion (#7869)

Plan: `knowledge-base/project/plans/2026-09-06-fix-test-all-lock-orphan-holder-plan.md`

## Phase 1 — Capacity first (independently shippable; touches ONE file)

- [ ] 1.1 Write Guard 2 arms in `scripts/test-contention.test.sh` against a **synthetic procfs**:
      M8 (filter removed), M9 (inverted comparison), M10 (unreadable `elapsed_s` must still be
      COUNTED — fail toward refusing), M11 (second stale sibling), H4 (zero-sibling fixture must
      fail, not pass empty), H5 (one fresh + one stale — the refusal still fires on the fresh
      one). Confirm RED.
- [ ] 1.2 Add the ceiling constant and its environment seam to `scripts/lib/test-contention.sh`.
- [ ] 1.3 Apply the elapsed filter at the **single `sibs=` derivation** inside `tc_preamble` —
      the awk that projects the `run` rows out of the one `_tc_scan_procs` walk. That one
      assignment feeds the reported rows, the sibling count and the exported
      `TC_SIBLING_RUN_COUNT`, so filtering there cannot drift between count and report, and
      **`scripts/test-all.sh` needs no edit for this phase**. No second `/proc` walk.
- [ ] 1.4 Emit `SOLEUR_TEST_ALL_STALE_SIBLING_EXCLUDED` naming pid and elapsed.
- [ ] 1.5 Confirm Guard 2 arms GREEN.

## Phase 2 — Guard 1 suite (RED before GREEN)

- [ ] 2.1 Create `scripts/test-all-runtime-ceiling.test.sh` with M1–M7 and H1–H3, derived from
      the plan's design rather than from the implementation's eventual shape.
- [ ] 2.2 Include **M3, the false-green row**, explicitly: a tripped run that reaches the exit
      ladder without forcing non-zero must redden. Declined suites are green-compatible on this
      runner, so this is the row that stops a curtailed run certifying a battery it never ran.
- [ ] 2.3 Include M4 (an unreadable elapsed reading must NOT trip) and M1 (hoisting the check to
      script top must redden — the window property).
- [ ] 2.4 Confirm the suite is RED.

## Phase 3 — The ceiling (GREEN)

- [ ] 3.1 Initialise the run-start timestamp and the trip flag at **top level, before the
      acquire/epilogue splice window** — two sibling suites replace that window wholesale and
      neuter the acquire, so a variable first assigned inside it aborts their sandboxes under
      `set -u`.
- [ ] 3.2 Add the elapsed check at the **entry** of `run_suite` — placement resolved, not left to
      implementation: at entry the run declines to *start* another suite, which is the property;
      at exit the final suite would produce no check. `run_suite` already reads `EPOCHREALTIME`
      into a `start` local at entry.
- [ ] 3.3 On crossing: emit `SOLEUR_TEST_ALL_RUNTIME_CEILING` (elapsed + ceiling), set the trip
      flag, and `return` — declining this suite and every later one.
- [ ] 3.4 **No descendant teardown and no process-group signal.** Returning at suite entry means
      no suite child is live, so the ordinary exit releases the inherited lock fd. A mid-suite
      `exit` was rejected precisely because the lock fd is inherited and the only teardown
      reaching those children is a group signal — whose leader under lefthook is `git commit`.
- [ ] 3.5 Read the trip flag at the final exit ladder and force exit **3**.
- [ ] 3.6 Fail toward keep-running on an unreadable elapsed reading; emit
      `SOLEUR_TEST_ALL_CEILING_UNAVAILABLE`.
- [ ] 3.7 Confirm Guard 1's suite GREEN.

## Phase 4 — Contract, ADR, registration

- [ ] 4.1 Widen the exit-code contract comment in `scripts/test-all.sh` so 3 covers a
      ceiling-curtailed run. Do **not** touch `suite_exit_class` — its byte-identical parity
      across two files is pinned by a dedicated suite.
- [ ] 4.2 Amend ADR-133: the dead-holder rejection stands and was re-measured; it does not
      quantify over a live-but-ownerless holder, which is bounded by runtime rather than by any
      ownership inspection (every available discriminator resolves to a process outliving the
      session).
- [ ] 4.3 Register `test-all-runtime-ceiling` in the runner's suite list.
- [ ] 4.4 Run: `test-all-runtime-ceiling`, `test-contention`, `test-all-killed-classification`,
      `test-all-capacity-signal`, `suite-exit-class-parity`.
- [ ] 4.5 Verify every acceptance criterion in the plan.
