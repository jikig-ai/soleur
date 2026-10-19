# Tasks: fix content publisher git push rejection

## Phase 1: Fix stale content status

- [x] 1.1 Update `02-operations-management.md` status from `scheduled` to `published`
- [x] 1.2 Update `2026-03-17-soleur-vs-notion-custom-agents.md` status from `scheduled` to `published`
- [x] 1.3 Update `03-competitive-intelligence.md` status from `scheduled` to `published`
- [x] 1.4 Update `2026-03-19-soleur-vs-cursor.md` status from `scheduled` to `published`
- [x] 1.5 Update `2026-03-16-soleur-vs-anthropic-cowork.md` status from `scheduled` to `published`

## Phase 2: Rewrite workflow commit step

- [x] 2.1 Update workflow permissions to add `pull-requests: write` and `statuses: write`
- [x] 2.2 Rewrite "Commit status updates" step to use PR-based approach
  - [x] 2.2.1 Create timestamped branch
  - [x] 2.2.2 Commit status changes to branch
  - [x] 2.2.3 Push branch to origin
  - [x] 2.2.4 Set synthetic `cla-check` status via Statuses API
  - [x] 2.2.5 Create PR targeting main
  - [x] 2.2.6 Queue auto-merge with `gh pr merge --squash --auto`
- [x] 2.3 `if` condition already correct — `success()` covers exit code 2 (mapped to 0 by wrapper)

## Phase 3: Testing

- [ ] 3.1 Run compound checks
- [ ] 3.2 Commit and push to feature branch
- [ ] 3.3 Create PR
- [ ] 3.4 After merge, trigger manual workflow dispatch to verify end-to-end
- [ ] 3.5 Confirm PR auto-merges with status updates
