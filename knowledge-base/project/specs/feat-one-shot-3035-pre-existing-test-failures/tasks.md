# Tasks — fix(test): pre-existing chat-page + kb-chat-sidebar test failures on main

Issue: #3035
Plan: `knowledge-base/project/plans/2026-05-09-fix-pre-existing-test-failures-plan.md`
Type: verify-and-close (issue already resolved by intermediate PRs)

## Phase 1 — Verification

- [ ] 1.1 Run the 8 affected test files on worktree HEAD; expect 8 files / 74 tests pass
  - Command: `cd apps/web-platform && npx vitest run test/chat-page.test.tsx test/chat-page-resume.test.tsx test/chat-surface-sidebar.test.tsx test/chat-surface-sidebar-wrap.test.tsx test/kb-chat-sidebar.test.tsx test/kb-chat-sidebar-a11y.test.tsx test/kb-chat-sidebar-banner-dismiss.test.tsx test/kb-chat-sidebar-quote.test.tsx`
- [ ] 1.2 Run the full vitest suite; expect 0 failures
  - Command: `cd apps/web-platform && npx vitest run --reporter=basic`
- [ ] 1.3 Capture pass/fail/skip summary for the PR body and the issue close-comment

## Phase 2 — Fixer-PR triage

- [ ] 2.1 Generate the merge log between baseline `62581167` and current HEAD scoped to chat surface and the 8 test files
- [ ] 2.2 Identify the PR(s) that fixed the duplicate-text symptom (likely candidates: #3240, #3237, #3276)
- [ ] 2.3 Record fixing PR(s) and one-line rationale in plan + PR body

## Phase 3 — Regression-guard scan

- [ ] 3.1 Grep `apps/web-platform/test/` for unscoped bare-filename `getByText` patterns
  - Patterns: `getByText\(['"]roadmap\.md['"]`, `getByText\(['"]readme\.md['"]`, `getByText\(['"]constitution\.md['"]`
- [ ] 3.2 If matches found in non-skipped tests, scope each match (`getAllByText` + index OR `within(container)`); upgrade plan tier to MINIMAL+1
- [ ] 3.3 If zero matches, record grep output as regression-guard evidence in PR body

## Phase 4 — PR + issue close

- [ ] 4.1 Commit plan + tasks artifacts; push branch
- [ ] 4.2 Create PR with `Closes #3035` on its own body line, citing fixing PR(s) and verification logs
- [ ] 4.3 Verify GitHub recognized the close-link via `gh pr view <N> --json closingIssuesReferences`
- [ ] 4.4 Post-merge: confirm #3035 auto-closed; fall back to `gh issue close 3035 -c "..."` if needed
