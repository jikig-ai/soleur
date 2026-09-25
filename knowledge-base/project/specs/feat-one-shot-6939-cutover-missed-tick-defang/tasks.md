# Tasks: de-fang the op=verify missed-tick enumeration (#6939)

Plan: `knowledge-base/project/plans/2026-09-25-fix-cutover-missed-tick-defang-plan.md`

## Phase 1 — RED (tests first)

- [ ] 1.1 In `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, delete the vacuous
  assertion `verify auto-emits the missed-tick trigger-cron list (P2-16)`.
- [ ] 1.2 Add Guard 1: a file-wide, comment-stripped zero count of `--function-id`/`--missed-tick`,
  with an anchor-presence precondition (`missed_tick_report() {` plus the `verify)` label).
- [ ] 1.3 Add workflow-shape assertions: the input is `type: boolean` with `default: false`, the env
  mapping line is present, there is exactly one `${{ inputs.missed_tick_candidates` reference, and
  `OP_REFS` still equals 1.
- [ ] 1.4 Add the call-site assertions: the exact whole-line `grep -cxF` (AC3), the call placed
  after the last `exactly-once VERIFIED` echo, and no `for fn in` inside the `verify)` arm.
- [ ] 1.5 Extract `missed_tick_report()` from `$BODY_SH` (column 0) and assert the extract is
  non-empty. Run each case with `set +e; ( set -euo pipefail; source …; missed_tick_report … ) > out; rc=$?; set -e`.
  Never use `$(…) || rc=$?`.
- [ ] 1.6 Add the behavioural cases:
  - 1.6.1 OFF, table-driven over `""` and `false`: no candidate lines and no fixture ids. The
    pointer includes the runbook path and has no quotes or apostrophes. rc 0, and also rc 0 when
    from=`garbage`.
  - 1.6.2 ON with the canonical fixture gives exactly 4 candidate lines (regex from AC5), none
    containing `soleur:` or `--`, rc 0.
  - 1.6.3 ON with the null fixture gives exactly 7 lines, rc 0. Add a comment that #6940 item 5 may
    change this count.
  - 1.6.4 ON with an invalid window gives rc 1, and the `::error::` contains `verdict above STANDS`.
  - 1.6.5 ON with one window argument empty gives a `::warning::` and rc 0.
  - 1.6.6 ON with a full-coverage fixture gives 0 lines, rc 0 (must-PASS).
  - 1.6.7 A newline-injection argument does not forge a `::notice::` line (P7).
  - 1.6.8 Case counter, in the `ACT_EVALS` idiom.
- [ ] 1.7 Run the suite and record the RED count against the unchanged SUT.

## Phase 2 — GREEN (implementation)

- [ ] 2.1 `scripts/cutover-inngest.sh`: add `missed_tick_report()` with a bare definition line,
  the arguments comment and the "do not reshape" comment above it, and `local BODY CRON_PERIOD`.
  Keep the P2-16 header verbatim. Implement the OFF/ON contract with CR/LF stripping.
- [ ] 2.2 Replace the inline block in `verify)` with the single one-line plain call.
- [ ] 2.3 Update the `doublefire_from()` comment that names the missed-tick auto-enumeration.
- [ ] 2.4 `.github/workflows/cutover-inngest.yml`: add the `missed_tick_candidates` boolean input
  (default false) and the `CUTOVER_MISSED_TICK_CANDIDATES` env mapping. Update the
  `CUTOVER_ANCHOR_FROM` and `CUTOVER_WINDOW_FROM/UNTIL` comments without writing
  `inputs.missed_tick_candidates` in them.
- [ ] 2.5 Run the suite: 0 FAIL, and a PASS count above 914. Also run `bash -n scripts/cutover-inngest.sh`,
  and `actionlint` if it is installed.

## Phase 3 — Docs + ADR

- [ ] 3.1 Runbook `inngest-server.md`: in the op=verify step, replace "Re-fire that list" with the
  pointer plus the opt-in input. Under `### Bounded-outage note`, write the fail-safe procedure
  (the single source): the `MONITOR_SLUG` lookup, the check-in margin, "no monitor means do not
  re-fire", the three risky crons, and the event-only rule.
- [ ] 3.2 ADR-146 § Deferred: fix the header count, add the item-2 "Interim de-fang landed" note,
  and add a new item 5 with its re-check condition.
- [ ] 3.3 ADR-106: add a dated sentence giving the block's current location.
- [ ] 3.4 Run the AC6 `cut26` plus `cmp` verdict byte-identity check (rc 0).
- [ ] 3.5 Run the AC1 class-wide `git grep`; it must print nothing.

## Phase 4 — Tracker hand-off

- [ ] 4.1 `gh issue comment 6940`: add the #6939 proper fix as a separate item, with its re-check
  condition and the interim state.
- [ ] 4.2 In the PR body, put `Closes #6939` and `Ref #6940`, and note the ADR-143 → ADR-146
  renumber.
