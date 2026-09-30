# Tasks: fix email-triage-row retry-clears-error flake (#9126)

Plan: knowledge-base/project/plans/2026-09-30-fix-email-triage-row-retry-error-flake-plan.md

## Phase 1: Reproduce (RED)

- 1.1 Run the CPU-burner load harness against the unmodified test (`-t "retry after"`); record failure rate
- 1.2 If baseline shows 0 failures in 5 runs, raise burners/iterations before proceeding

## Phase 2: Fix (GREEN)

- 2.1 Edit apps/web-platform/test/components/inbox/email-triage-row.test.tsx, retry test tail
  - 2.1.1 Keep `waitFor(onChanged called once)` as positive anchor
  - 2.1.2 Replace immediate `expect(queryByRole("alert")).toBeNull()` with a separate `waitFor(() => expect(queryByRole("alert")).toBeNull())`
  - 2.1.3 Add comment: onChanged precedes the entangled transition commit of `setActionError(null)`; absence wait is non-vacuous because presence proven by earlier findByText
  - 2.1.4 No per-call `{ timeout }` (RTL asyncUtilTimeout 10s set globally in test/setup-dom.ts)

## Phase 3: Verify

- 3.1 Isolated file: 18/18 pass
- 3.2 Scratch mutation (remove setActionError(null) in component) makes the test fail; revert; component diff empty (AC3, gating)
- 3.3 Load harness post-fix: 0 failures over >= 20 runs (non-gating evidence E1; kill captured burner PIDs individually)

## Phase 4: Learning

- 4.1 Append Insight 7 to knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md
- 4.2 PR body: `Closes #9126`
