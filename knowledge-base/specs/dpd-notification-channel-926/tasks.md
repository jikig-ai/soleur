# Tasks: DPD Section 8.2(b) Notification Channel Update

## Phase 1: Setup

- [ ] 1.1 Merge `origin/main` into the feature branch to incorporate PR #919 (Section 7.2 fix)
- [ ] 1.2 Verify Section 7.2(b) now includes Web Platform and email notification after merge

## Phase 2: Core Implementation

- [ ] 2.1 Update DPD Section 8.2(b) in `docs/legal/data-protection-disclosure.md`
  - [ ] 2.1.1 Add "Web Platform (app.soleur.ai)" and email notification parenthetical
- [ ] 2.2 Update DPD Section 8.2(b) in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  - [ ] 2.2.1 Apply identical content change as 2.1
- [ ] 2.3 Update "Last Updated" header in both files to include this change

## Phase 3: Testing

- [ ] 3.1 Run `diff` between root and Eleventy DPD copies to verify no unintended content drift
- [ ] 3.2 Verify Section 8.2(b) text matches expected wording in both copies
- [ ] 3.3 Run full test suite to confirm no regressions
