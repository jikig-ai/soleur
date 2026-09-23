# Tasks: close #4781 — auth alert empty-filter recurrence guard

Plan: `knowledge-base/project/plans/2026-09-23-fix-sentry-auth-alert-empty-filter-recurrence-guard-plan.md`

## Phase 1: RED (suite)

- [ ] 1.1 In `tests/scripts/test-sentry-alert-live-fidelity.sh`, make `_drift_case` fail when `$_out` contains `command not found`
- [ ] 1.2 Add F35 `t_auth_rules_emptied_4781`, a custom multi-assert row: the 4 auth rules plus `sandbox-startup-failure` emptied. Register it and set `EXPECTED_TESTS=68`
- [ ] 1.3 Tighten F10 to assert the literal `` `def excluded` `` in the UNMANAGED finding. Add `! grep -qF 'command not found'` to F22
- [ ] 1.3b Build the F35 fixture with `map(if … else . end)`, never `map(select(…))`, and assert no `DELETED or RENAMED` plus the `N` / `N+2` header
- [ ] 1.4 Run the suite in the background and record the RED result: F35 and F10 fail, every other row passes

## Phase 2: GREEN (probe + guide)

- [ ] 2.1 In `scripts/sentry-alert-live-fidelity.sh`, escape the backticks on the UNMANAGED `_finding` line
- [ ] 2.2 Move the UNMANAGED loop below the `missing_cap` refusal and above the frozen pin. For names in `frozen_names_json`, emit `FROZEN RULE LEFT SCOPE: '<name>'` (use `_safe`, never a silent skip)
- [ ] 2.3 Add the epilogue clause for the new class
- [ ] 2.4 In `.github/workflows/scheduled-sentry-alert-drift.yml`, add `FROZEN RULE LEFT SCOPE` to the FROZEN guide bullet, then run actionlint
- [ ] 2.5 Re-run the suite: expect 68 passed, 0 failed
- [ ] 2.6 Run the Guard Contract matrix (M1-M6, H1, H2), revert each mutation, and record the results in the PR body

## Phase 3: Lore correction

- [ ] 3.1 Append a 2-3 line `Corrected 2026-09-23 (#4781)` blockquote to each of the 6 non-anchor learnings, with file-specific sentences only for warn-level-debounce and warning-level
- [ ] 3.2 Append a closing note to the anchor learning: the guard, its limits, how to check today, and the list of corrected files
- [ ] 3.3 Edit `cloud-scheduled-tasks.md` in place
- [ ] 3.4 Edit `oauth-probe-failure.md` narrowly: the ownership row, the auth-per-user-loop paragraph, and "#4781 still open"

## Phase 4: Stale comments

- [ ] 4.1 In `issue-alerts.tf`, delete the stale banner and write 3-4 accurate comment lines
- [ ] 4.2 Rewrite the stale sentence in the `apply-sentry-infra.yml` L38-41 comment
- [ ] 4.3 Verify: comment-only diffs, and `alert-reference.json` and the projection are untouched

## Phase 5: Ship

- [ ] 5.1 Run the pre-push lints: skill-body-budget, diagnosis-claims, infra-no-human-steps `--changed --base origin/main`, and markdownlint
- [ ] 5.2 Open the tracking issue for guide-versus-probe class parity (deferral)
- [ ] 5.3 Write the PR #8654 body. Its first line is the no-prod-mutation statement, followed by `Closes #4781`, the measurements, the census and the limits
- [ ] 5.4 After merge, confirm the apply run is green and its post-apply probe passes, then comment on #4781 citing that run and the limits
