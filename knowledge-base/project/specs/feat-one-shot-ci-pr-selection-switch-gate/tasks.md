# Tasks: ci: stop paying for the dark pr-selection selector (Ref #9729)

Plan: `knowledge-base/project/plans/2026-10-15-feat-ci-pr-selection-switch-gate-plan.md`. Write each executed test first and watch it go red before the edit.

## Phase 1: Driver gate (scripts/ci-pr-selection.sh, scripts/ci-pr-selection.test.sh)

- 1.1 Add `row_switch_gate` to the suite (AC1, AC2, AC3, AC4 shapes); run against the unmodified driver and confirm it is red.
- 1.2 Add the gate before `stage=2`: `reason=switch_off`, `[ "$sw" = on ] || return 0  # GUARD:G2-16-SWITCH-GATE`.
- 1.3 Flip the harness default `SWITCH=` to `SWITCH=on`; rewrite "G2-13 dark: would-skip evidence" and "LEAK the run still reaches stage 2"; keep the explicit unset rows.
- 1.4 Add the Guard 1 mutants (10 rows: 9 + 1, incl. `!= invalid` and the before-`paths_too_long` reorder with an over-cap and a `bigok` fixture), each confirmed LANDED and KILLED; add harness rows (default flipped back reds control rows; `krn` and `k2` must-PASS).
- 1.5 Update the driver header comment (stage 2 only on exactly `on`; `sel_s` is 0 when stage 2 did not run; `switch_off` reason).

## Phase 2: Job gate (.github/workflows/ci.yml)

- 2.1 Phase 3 pins first (red), then set `pr-selection` `if: github.event_name == 'pull_request' && vars.CI_PR_AFFECTED != ''`.
- 2.2 Rewrite the comment block above the job (dark = job skipped; non-empty non-`on` = stage 1 only; `on` = stage 2 with the lock). The docs check is done (unset `vars.X` is an empty string; `vars` is available in a job-level `if`); the comment states only that. Also fix the stale clauses (dark job "only annotates", "stage-2 even while dark", "Off a pull_request the job is skipped"). No edit inside the `test` aggregator step.

## Phase 3: Pin suites

- 3.1 `scripts/ci-push-dedupe.test.sh`: `PRSEL_IF` constant exported to `chk.py`; `P-JOBIF` against it; rebuild the nine `y-prsel-*` anchors and `y-budget-10` from it; no "did NOT land" mutant remains.
- 3.2 Same file: `darkequiv` mode over the real parsed `if:` strings (AC7) with the Guard 2 mutants (8 job-`if` rows, 3 gated-job rows and, from the review rounds, 12 switch-census rows) and harness rows; model `vars.CI_PR_AFFECTED` unset as the empty string (documented).
- 3.3 `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`: G1-8c rows (add `pull_request` to the existing G1-8 event loop; empty inputs, `HEAD_SHA_OK` in empty and `false`) and the 3 Guard 3 mutants (AC8): a new `tolmut.py` operator loosening `HEAD_SHA_OK`, one new probe row in the `mutate_tol` p-set (p23: non-empty listed skip with `HEAD_SHA_OK=''`; the empty-inputs probes were dropped at review as non-kills), one compound mutant. `AGG_DIGEST` unchanged.
- 3.4 Re-run `scripts/ci-draft-light.test.sh` unchanged.

## Phase 4: Docs

- 4.1 ADR-276 amendment (dated 2026-10-15) and its index line: gates, supersession of the dark-cost bullets, measured figures with their source commands, accurate measurement procedure, PR C note. Keep `gh run rerun` and the release workflow file name off one line.
- 4.1b Amendment must also carry: rollback prose (deleted variable means the job is skipped on re-run), the `ready_for_review`/no-`ACTION` PR C item, the dark telemetry stream stopping, the optional `off`-value real check as a separately authorized step.
- 4.2 One sentence appended to the `ci.yml` row of `scripts/pr-fanout-ledger.txt` (count stays 27).

## Phase 5: Floors and the full run

- 5.1 `bash scripts/ci-pr-selection.test.sh | tail -3`; set `BASE_ROWS` and `MIN_MUTANTS` from the measured green run; also re-derive `ci-test-aggregator-diagnosis` `MIN_ROWS`/`MIN_MUTANTS` and `ci-push-dedupe` `_FLOOR`/`MUT_RUN` minimum.
- 5.2 Run the whole Re-run List in the plan (brief's list plus the ratchets); fix baselines only downward with a named cause.
- 5.3 `python3 scripts/lint-guard-contract.py` over the plan.

## Phase 6: Ship

- 6.1 PR body: `Ref #9729`, no closing keyword, a `## Changelog` section; record the live proof from this PR's own CI run (AC9b) after checking its preconditions (variable absent via `gh api repos/jikig-ai/soleur/actions/variables/CI_PR_AFFECTED` returning 404; run not a light draft): `pr-selection` skipped, gated legs and `test` success. After merge, repeat on the first doc-only PR (AC9c).
- 6.2 Review runs `soleur:engineering:review:user-impact-reviewer` (single-user incident).
