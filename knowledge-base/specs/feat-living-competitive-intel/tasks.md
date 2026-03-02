# Tasks: Persist Competitive Intelligence Report

## Phase 1: Core Implementation

- [ ] 1.1 Update workflow permissions (`contents: write`, remove `read`)
- [ ] 1.2 Add "Persist competitive intelligence report" step after Claude step
  - [ ] 1.2.1 File existence check with `::warning::` on missing
  - [ ] 1.2.2 Git identity configuration (`github-actions[bot]`)
  - [ ] 1.2.3 `git add` + no-change detection (`git diff --cached --quiet`)
  - [ ] 1.2.4 Commit with `docs: update competitive intelligence report`
  - [ ] 1.2.5 Push to main with rebase retry on divergence

## Phase 2: Validation

- [ ] 2.1 Manual workflow dispatch test (`gh workflow run`)
- [ ] 2.2 Verify commit appears on main with correct author
- [ ] 2.3 Verify `competitive-intelligence.md` exists on main after push
- [ ] 2.4 Verify GitHub Issue is still created (existing behavior preserved)
