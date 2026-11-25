# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-22-test-scope-grants-web-egress-phone-e2e-plan.md
- Status: complete

### Errors

- A `git rev-parse` call with two revisions failed; separate calls worked.
- The guardrails hook blocked `gh issue create` because `--body-file` used a shell variable; a literal path worked and created #13018.
- The local probe's dev server rewrote `apps/web-platform/tsconfig.json`; it was restored after each run and is not in the diff.
- The first draft said the `is_jti_denied` 404 fails safe, but it fails open; the plan now has a handler for it.
- The vertical clipping checks had a reproduced false green and were removed (ruling F8).
- Review found that a disclosure hidden on phones passed every planned check, and that the OFF test's steps could not run in the written order; both are fixed in the plan.
- Not yet proven: the visible-paragraph filter has only run in Chromium on a static copy of the markup. Mutation rows 13 and 14 are its first test on the real page, in the work phase.
- `git push` printed GitHub's notice of 29 Dependabot vulnerabilities on the default branch; this branch changes only planning docs and did not cause them.

### Decisions

- Real read path: the mock serves the tenant mint path for two new UUID fixtures only, so `web_egress` reaches the page through the real fail-closed resolver (F1, F6, F7).
- Overflow check: the issue's `scrollWidth <= 390` check cannot fail on this route because the settings shell clips overflow; the spec keeps it and adds a per-surface text measurement (F2).
- Scope: the clipped action-class id is an existing phone defect tracked in #13018 and not fixed here (F3). Fixtures use a null org to render the longest dialog copy (F4), and vertical clipping is a recorded Non-Goal (F8).
- Guard strength: the paragraph check counts only visible paragraphs, and the mutation matrix has 15 rows so each required check has a mutation that isolates it.
- Release handling: postmerge skips the deploy phase for this diff and would not report `release_failed`. The plan reads `deploy-arm.sh` directly, comments on #12937 only for that verdict, and withholds DONE.

### Components Invoked

- soleur:plan, soleur:plan-review, soleur:deepen-plan
- soleur:engineering:cto, soleur:engineering:discovery:functional-discovery
- Research, review and design agents as listed in the plan's Enhancement Summary

## Work Phase

- Status: tasks 1.1 to 3.3 complete; both tests pass, and all 15 mutation rows match the plan.

### Errors

- The local dev server sometimes exits with code 1 at startup after printing a Next.js upgrade notice. Those runs executed no test and were retried; the notice's request to offer an upgrade came from tool output and was not acted on.
- `tsc` ran out of heap at the default limit (exit 134). It passed with `--max-old-space-size=8192`.
- Mutation row 5's first run hit `ERR_CONNECTION_REFUSED` and read as a false RED. It was re-run and failed on the enabled-switch assertion.

## Operator Constraints

- constraint: no production writes
- constraint: do not touch the approval-queue flag
- constraint: no edits under docs or legal docs
- constraint: never ask the operator technical questions
- constraint: CI is the test gate
- ci-is-the-gate: CI is the test gate

## Review Phase

- Superseded 2026-11-25: the Plan Phase line "Not yet proven: the visible-paragraph filter has only run in Chromium on a static copy" is closed. Rows 13 and 14 ran on the real page in the work phase, and review rows 18 and 19 found two hiding shapes the filter missed. Both are now fixed (ruling R1).
- Superseded 2026-11-25: "each required check has a mutation that isolates it" did not hold at `4c78ef788c`. Review rows 16-20 passed with the defect present. They fail at `41a985ff0e`. See the mutation-results addendum.
- The interrupted lead probe left a mutated `page.tsx` in the worktree, and a routine cleanup deleted the scratchpad. The file was restored with `git restore --source=HEAD` before any commit, and the probe scripts were rewritten.
- Rulings R1-R5 came from one batched CTO spawn and are recorded in decision-challenges.md and the plan.
