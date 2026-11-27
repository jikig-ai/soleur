# Tasks: feat-one-shot-cf-token-scope-mock-live-codes

Plan: `knowledge-base/project/plans/2026-11-26-test-cf-token-scope-mock-live-grant-codes-plan.md`
Lane: single-domain. Ref #12931 (never Closes or Fixes).

## Phase 1: Setup

- 1.1 Baseline. Run `bash plugins/soleur/test/cf-token-scope.test.sh > <scratch log> 2>&1` and read only the tail. Expect `680 passed, 0 failed`.

## Phase 2: Core implementation (all in `plugins/soleur/test/cf-token-scope.test.sh`)

- 2.1 RED. In M2, replace the permissive settings `has_re` with `M2_SET_LINE` and `M2_BOT_LINE`, and two `assert_eq ... 1 "$(grep -cxF -- ... "$OUTFILE" || true)"` whole-line pins, after M2's other assertions and before any later run overwrites `$OUTFILE` (review of #13080: `count_f` is a substring count). Run the suite. Expect `679 passed, 2 failed`, where the two failures are exactly the new pins.
- 2.2 GREEN. In the mock write branch, choose the granted 400 code by URL: settings 1006, bot_management 10400, anything else 10026. Use neutral synthetic messages and a comment saying no #12931 comment records 10026 for those rows (reworded in review of #13080 from "never measured").
  - 2.2.1 Rewrite the settings-branch sentence "ASSUMED here" so it cites the 2026-11-26 measurement (#12931 comment 7201789881).
  - 2.2.2 Leave the write-branch header comment unchanged (CTO R2).
- 2.3 Raise `MIN_ASSERTIONS` from 680 to 681. Run the suite. Expect rc 0 and `681 passed, 0 failed`.

## Phase 3: Testing

- 3.1 Work-time mutation run (nothing committed). On scratch copies of the test file and the script, apply Guard Contract matrix rows 2-5 one at a time. Each must red as stated. Also run harness rows H1-H3. Delete the copies afterwards.
- 3.2 Check AC3-AC6 with the greps in the plan. The diff touches the test file, SKILL.md, the script header comment, the migration runbook and the KB plan and spec files (plan addendum supersedes AC6).
- 3.3 PR body. Use `Ref #12931`. Note that the SKILL.md "not yet measured" sentence and the runbook edits were included in scope (decision-challenges rows).
- 3.4 Do not run any of the epic's operator-authorized acts. Make no live Cloudflare calls, and never print a token.
