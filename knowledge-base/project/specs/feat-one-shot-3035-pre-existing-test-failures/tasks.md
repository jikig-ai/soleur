# Tasks — fix(test): pre-existing chat-page + kb-chat-sidebar test failures on main

Issue: #3035
Plan: `knowledge-base/project/plans/2026-05-09-fix-pre-existing-test-failures-plan.md`
Type: verify-and-close (issue already resolved by intermediate PRs)

**Deepen-pass (2026-05-09) collapsed Phases 1, 2, 3 into evidence captured directly in the plan.** Remaining work is mechanical: re-verify on `/work` HEAD, draft PR body citing the deepen-time evidence, ship.

## Phase 0 — Re-verify on /work HEAD (mechanical)

- [x] 0.1 Run the 8 affected test files; expect 8/8 + 74/74 pass — DONE at worktree commit `09f68a0d`: 8 files / 74 tests / 0 fail
  - Command: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-page.test.tsx test/chat-page-resume.test.tsx test/chat-surface-sidebar.test.tsx test/chat-surface-sidebar-wrap.test.tsx test/kb-chat-sidebar.test.tsx test/kb-chat-sidebar-a11y.test.tsx test/kb-chat-sidebar-banner-dismiss.test.tsx test/kb-chat-sidebar-quote.test.tsx`
- [x] 0.2 Run the full vitest suite; expect 0 failures — DONE at worktree commit `09f68a0d`: 363 files / 3956 tests / 0 fail
  - Command: `cd apps/web-platform && ./node_modules/.bin/vitest run --reporter=basic`
- [x] 0.3 Capture pass/fail/skip summary for the PR body — captured in plan AC line 67

## Phase 1 — PR + close (mechanical)

- [ ] 1.1 Draft PR body using deepen-pass evidence:
  - Phase 0 verification logs (8/8 + 363/363)
  - Fixing-PR table (PR #3240 primary; #3237, #3308, #3315, #3469 cumulative)
  - Regression-guard grep results (4 surviving bare-filename matches; ACKNOWLEDGE disposition)
  - `Closes #3035` on its own body line
- [ ] 1.2 Push branch (already pushed at plan-time); confirm `gh pr view` once PR is created
- [ ] 1.3 Verify GitHub recognized the close-link via `gh pr view <N> --json closingIssuesReferences`
- [ ] 1.4 Mark PR ready, queue auto-merge: `gh pr merge <N> --squash --auto`
- [ ] 1.5 Poll `gh pr view <N> --json state --jq .state` until MERGED

## Phase 2 — Post-merge (operator)

- [ ] 2.1 Verify #3035 auto-closed; fall back to `gh issue close 3035 -c "..."` if not
- [ ] 2.2 File follow-up tracking issue for dormant-fragility class:
  ```bash
  gh issue create \
    --title "test(chat-sidebar, file-tree): scope bare-filename getByText via within(...)" \
    --label priority/p3-low,type/chore,domain/engineering \
    --body "4 surviving bare-filename getByText matches in apps/web-platform/test/{kb-chat-sidebar,file-tree-rename,file-tree-delete}.test.tsx pass today only because the rendered DOM has exactly one match per component. Future component refactor adding a sibling render site re-triggers the #3035 class. Harden via within(container) scoping. Surfaced during #3035 deepen-pass.

  Ref #3035."
  ```
- [ ] 2.3 Run `cleanup-merged` to remove worktree and merged branch
