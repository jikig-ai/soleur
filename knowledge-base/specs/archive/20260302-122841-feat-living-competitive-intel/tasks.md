# Tasks: Persist Competitive Intelligence Report

## Phase 1: Core Implementation

- [x] 1.1 Update workflow permissions (`contents: write`, remove `read`)
- [x] 1.2 Add "Persist competitive intelligence report" step after Claude step
  - [x] 1.2.1 File existence check with `::warning::` on missing
  - [x] 1.2.2 Git identity configuration (`github-actions[bot]`)
  - [x] 1.2.3 `git add` + no-change detection (`git diff --cached --quiet`)
  - [x] 1.2.4 Commit with `docs: update competitive intelligence report`
  - [x] 1.2.5 Push to main with rebase retry on divergence

## Phase 2: Validation

- [x] 2.1 Manual workflow dispatch test (`gh workflow run`)
- [x] 2.2 Verify commit appears on main with correct author
- [x] 2.3 Verify `competitive-intelligence.md` exists on main after push
- [x] 2.4 Verify GitHub Issue is still created (existing behavior preserved)
