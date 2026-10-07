# CI-Only Test Hook Exclusions

Use this procedure only after the operator authorizes relying on CI for test validation.

1. Read `lefthook.yml` and identify every hook that starts a test runner for the staged files.
2. Add every exact hook key to the comma-separated `LEFTHOOK_EXCLUDE` value. In this repo, `bun-test` and `plugin-component-test` are separate hooks with different globs; excluding only one leaves the other active.
3. Read the commit-hook output. Confirm every test hook is explicitly marked skipped and every required non-test hook ran. If no hook verdict appears, inspect `core.hooksPath`; run the relevant non-test checks directly and record any selector exclusions. A successful commit is not evidence that its hooks ran.
4. If an excluded hook also performs a required non-test check, run that check separately or confirm an equivalent CI gate covers it.

Keep security, secret, formatting, typecheck, and other non-test hooks enabled unless the operator's instruction also covers those checks.

## Exact-head CI verdict

Before claiming CI verified, bind the reading to the remote PR head and inspect the latest applicable workflow runs with `gh run list --commit <head>` and `gh run view <run-id> --json headSha,status,conclusion,jobs`. Require completed successful run conclusions and the required aggregate jobs defined in the workflow; distinguish explicitly superseded cancellations from current runs. Recheck the PR head after collecting results.

`gh pr checks` and the PR monitor enumerate reported checks only. A workflow can fail before creating its required aggregate while every reported job succeeds. A missing aggregate, failed workflow, failed API probe or bounded-watch timeout is unresolved or failed CI, never a green verdict. The monitor's green line does not replace the workflow-run check. Evidence: PR #9051, CI run 37638922063, where GitHub reported an internal server error and omitted the required `test` job despite 35 successful jobs.
