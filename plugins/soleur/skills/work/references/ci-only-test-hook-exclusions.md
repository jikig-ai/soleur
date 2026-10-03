# CI-Only Test Hook Exclusions

Use this procedure only after the operator authorizes relying on CI for test validation.

1. Read `lefthook.yml` and identify every hook that starts a test runner for the staged files.
2. Add every exact hook key to the comma-separated `LEFTHOOK_EXCLUDE` value. In this repo, `bun-test` and `plugin-component-test` are separate hooks with different globs; excluding only one leaves the other active.
3. Read the commit-hook output. Confirm every test hook is explicitly marked skipped and every required non-test hook ran.
4. If an excluded hook also performs a required non-test check, run that check separately or confirm an equivalent CI gate covers it.

Keep security, secret, formatting, typecheck, and other non-test hooks enabled unless the operator's instruction also covers those checks.
