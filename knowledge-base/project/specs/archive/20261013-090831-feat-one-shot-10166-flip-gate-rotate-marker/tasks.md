# Tasks - fix(infra): d6_replace_stale accepts only a real rotate run (#10166)

Plan: knowledge-base/project/plans/2026-10-13-fix-git-data-d6-gate-rotate-marker-plan.md
Guardrails: no workflow dispatch, terraform apply, Doppler write, volume wipe or destroy; do not dispatch the modified workflow after merge; skip the local affected gate (CI covers it); run only the focused suites in 6.

## 1. Marker step
- 1.1 Append `Rotate completed (d6 marker)` as the LAST step of `git_data_host_replace` (after `Dispatch summary`), `if: inputs.apply_target == 'git-data-host-rotate' && inputs.plan_only != true`, comment inside the step, no always()/continue-on-error
- 1.2 Leave `Validate dispatch inputs (rotate confirm token)` untouched (unconditional, census G5c)

## 2. Lib and suite (scripts/lib/)
- 2.1 Write the suite rows first (R1-R15, S1-S7, M1-M4, floor, `gh()` function with refusal epilogue) - RED
- 2.2 `git-data-rotate-stamp.sh`: constants, `git_data_rotate_run_verdict` (8-row table, stamped before attempt rows, always prints a token), `git_data_d6_scan` (fd 3, `</dev/null`, queued-no-jobs = in flight)
- 2.3 Set `MIN_ASSERTIONS` from the final green run; shellcheck; `scripts/guard-vacuity-floor.test.sh`

## 3. Gate
- 3.1 Rewrite the d6 block in `git-data-cutover.yml` `flip_preconditions`: corrected comment, source lib with `|| fail d6_run_unreadable`, captured `gh run list` (limit 100, `databaseId,status`) with `|| fail`, `git_data_d6_scan <<<"$ids"`, `case` with five verdict arms and a fail-closed `*)`
- 3.2 No inline step-selection jq left; `last_ok` kept for the final echo

## 4. Docs
- 4.1 ADR-220 one-sentence dated correction
- 4.2 Runbook: three verdict rows + the marker/legacy/sticky-block sentences

## 5. Parity pins
- 5.1 `checkRotateMarkerWiring` + pins P-a..P-g (comment-stripped, anchored) in `plugins/soleur/test/terraform-target-parity.test.ts`
- 5.2 Six mutation rows (drop plan_only conjunct, drop apply_target conjunct, add always(), append step after marker, restore old confirm-step read, change a constant), each asserting the text changed and the control is clean

## 6. Verify (focused)
- 6.1 lib suite; parity test (filtered, then whole file); census suite G5a-c; boot-signal-poll suite; guard-vacuity-floor suite
- 6.2 PR body: `Closes #10166`, nothing dispatched/applied, re-dispatch of rotate (#10138) needed after merge, no dispatch of the modified workflow
