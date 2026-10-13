---
title: "Tasks — de-flake live-repo-badge J5 re-arm transition (#5297)"
date: 2026-06-18
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-18-fix-flaky-live-repo-badge-j5-rearm-transition-plan.md
---

# Tasks — de-flake live-repo-badge J5 re-arm transition (#5297)

Derived from `2026-06-18-fix-flaky-live-repo-badge-j5-rearm-transition-plan.md`. Test-only change; one file edited.

## Phase 0 — Preconditions (verify before editing)
- [ ] 0.1 Confirm the residual race: re-read `apps/web-platform/test/live-repo-badge.test.tsx:122-142` (regain gate on `regainCommitted` only) and `components/dashboard/live-repo-badge.tsx:23-25` (boolean-dep re-arm effect). Confirm the `false`-commit-between-two-`true`s mechanism in the plan Root Cause.
- [ ] 0.2 Confirm runner: `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx` runs (vitest 4.1.0, NOT `bun test` / NOT `npm run -w`).

## Phase 1 — Re-anchor the regain gate (the only change)
- [ ] 1.1 In `apps/web-platform/test/live-repo-badge.test.tsx`, replace the `regainCommitted`-only gate before the third `fireEvent.focus` with `await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2), { timeout: 10_000 })` (proves the regain `poll()`/`setData(team)` continuation ran — strictly downstream of `regainCommitted`), then `await act(async () => {})` to drain the `false` render + boolean-dep effect. (plan Phase 1 prescribed fix.)
- [ ] 1.2 Add AC2b proof: `expect(fetchMock).toHaveBeenCalledTimes(2)` BEFORE Focus #3 (regain provably committed before re-revoke — mount-`solo` == re-revoke-`solo`, so the terminal assertion alone is not enough).
- [ ] 1.3 ORDERING is load-bearing: `regain-commit-proof → act flush → __resetActiveRepoCoalesceForTests() → fireEvent.focus`. The latch reset MUST come AFTER the `act` flush (interleave guard). Keep the terminal re-arm assertion `getByTestId("revocation-interstitial").toBeInTheDocument()`. Remove/convert the bare synchronous `queryByTestId(...).toBeNull()` at current line 131 (proves nothing).
- [ ] 1.4 Import `act` from `@testing-library/react`. Flush idiom is `await act(async () => {})` ONLY — do NOT use `setTimeout`/`vi.advanceTimers*` (pumps the hook's real interval). Do NOT switch to `rerender` (plan Research Reconciliation row 2). Do NOT touch product code.
- [ ] 1.5 Every `vi.waitFor` site (including the new call-count gate) carries `{ timeout: 10_000 }` with the `#5113`-style comment. (Insight 6 — new sites inherit vitest's 1000 ms default.)

## Phase 2 — Verify (Acceptance Criteria)
- [ ] 2.1 AC1 scope: `git diff --name-only origin/main...HEAD` lists exactly `apps/web-platform/test/live-repo-badge.test.tsx`.
- [ ] 2.2 AC4 budget parity: `grep -c "timeout: 10_000" <file>` == `grep -c "vi.waitFor(" <file>`.
- [ ] 2.3 AC5 typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] 2.4 AC6 isolation ≥10×: `cd apps/web-platform && for i in $(seq 1 10); do ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx || break; done` all green.
- [ ] 2.5 AC7 parallel-load repro ≥3×: `TEST_GROUP=webplat bash scripts/test-all.sh` green on at least 3 runs (default forks pool). Record run count in PR body. If still flaky → escalate to plan Phase 1 Option B.

## Phase 3 — Ship
- [ ] 3.1 Commit (test-only), push, open PR with `Closes #5297`, record AC6/AC7 run counts in PR body.
- [ ] 3.2 QA/review per workflow gates, then `gh pr merge --squash --auto`. No post-merge operator step.
