# Tasks: close #4781 — auth alert empty-filter recurrence guard

Plan: `knowledge-base/project/plans/2026-09-23-fix-sentry-auth-alert-empty-filter-recurrence-guard-plan.md`

## Phase 1: RED (suite)

- [x] 1.1 In `tests/scripts/test-sentry-alert-live-fidelity.sh`, export `LC_ALL=C` in `_run` and `_run_env`
- [x] 1.2 Make `_drift_case` fail when `$_out` matches the bash error prefix, the ERE `sentry-alert-live-fidelity.sh: line [0-9]+:`
- [x] 1.3 Add the file-scope array `F4781_FROZEN=(auth-per-user-loop sandbox-startup-failure)`
- [x] 1.4 Add F35 `t_auth_rules_emptied_4781` as a custom row with a single `if` and `detail+=` messages:
  - build the fixture with `map(if … else . end)`
  - check the header against `N` / `N+${#F4781_FROZEN[@]}` and assert no `DELETED or RENAMED`
  - assert DRIFT ×2 for each burst rule and FROZEN DRIFT for `auth-per-user-loop`
  - assert LEFT SCOPE present and UNMANAGED absent for each frozen name
  - assert no bash-error prefix
- [x] 1.5 Add F36 `t_unmanaged_name_is_scrubbed_and_whole`, using the name `auth-per-user-loop\nx\r::error::spoofed`. Assert:
  - one scrubbed UNMANAGED line
  - no line starting with `::error::spoofed`
  - no LEFT SCOPE for `auth-per-user-loop`
- [x] 1.6 Add the bash-error-prefix check to F22
- [x] 1.7 Scope F10's check to its `UNMANAGED: 'created-in-the-ui'` line and assert that the line contains `def excluded`
- [x] 1.8 Set `EXPECTED_TESTS=69`, run the suite in the background, and record the RED result (F35, F36 and F10 fail, every other row passes)

## Phase 2: GREEN (probe + guide)

- [x] 2.1 In `scripts/sentry-alert-live-fidelity.sh`, escape the backticks on the UNMANAGED line
- [x] 2.2 Replace the bash UNMANAGED loop with a single jq classifier:
  - place it after the `missing_cap` refusal and before the frozen pin
  - match whole keys, and use the same `safe` as the pin
  - emit `LEFT` or `UNMANAGED` lines
- [x] 2.3 Print the `FROZEN RULE LEFT SCOPE: '<name>'` finding with the id-aware remedy, and do not quote the name next to `FROZEN DRIFT`
- [x] 2.4 Add the epilogue clause
- [x] 2.5 Add `FROZEN RULE LEFT SCOPE` to the FROZEN bullet in `.github/workflows/scheduled-sentry-alert-drift.yml` (GET the id first; never delete the captured id), then run actionlint
- [x] 2.6 Re-run the suite: 69 passed, 0 failed
- [x] 2.7 Run the mutation matrix (M1-M8, H1, H1b, H2):
  - confirm the unmutated tree exits 0 first
  - after each mutation, check for exit 1 with the named row `[FAIL]`
  - restore with `git checkout -- <file>`
  - record the full red sets in the PR body

## Phase 3: Lore correction

- [x] 3.1 Append a 2-3 line `Corrected 2026-09-23 (#4781)` blockquote to each of the 6 non-anchor learnings. Add file-specific sentences only for warn-level-debounce and warning-level
- [x] 3.2 Append a closing note to the anchor learning: the guard, its limits, how to check today, and the list of corrected files
- [x] 3.3 Edit `cloud-scheduled-tasks.md` in place
- [x] 3.4 Edit `oauth-probe-failure.md` narrowly: the ownership row, the auth-per-user-loop paragraph, and "#4781 still open"

## Phase 4: Stale comments

- [x] 4.1 In `issue-alerts.tf`, delete the stale banner and write 3-4 accurate comment lines
- [x] 4.2 Rewrite the stale sentence in the `apply-sentry-infra.yml` comment at L38-41
- [x] 4.3 Verify: comment-only diffs, and `alert-reference.json` and the projection are untouched

## Phase 5: Ship

- [x] 5.1 Run the pre-push lints: skill-body-budget, diagnosis-claims, infra-no-human-steps `--changed --base origin/main`, and markdownlint
- [ ] 5.2 Open one tracking issue for three follow-ups: guide/probe class parity, bidi ranges in the sanitizers, and anchoring the verdict grep (W7)
- [ ] 5.3 Write the PR #8654 body:
  - first line: the no-prod-mutation statement
  - then `Closes #4781`, the measurements, the census and the limits
- [ ] 5.4 After merge, confirm the apply run is green and its post-apply probe passes, then comment on #4781 with that run and the limits
