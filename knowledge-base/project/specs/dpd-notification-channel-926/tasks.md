# Tasks: DPD Section 8.2(b) Notification Channel Update

## Phase 1: Setup

- [ ] 1.1 Merge `origin/main` into the feature branch to incorporate PR #919 (Section 7.2 fix) and PR #914 (Cloudflare harmonization)
- [ ] 1.2 Verify Section 7.2(b) now includes Web Platform and email notification after merge
- [ ] 1.3 Verify "Last Updated" header reflects post-merge state (includes PR #919 and #914 entries)

## Phase 2: Core Implementation

- [ ] 2.1 Update DPD Section 8.2(b) in `docs/legal/data-protection-disclosure.md`
  - [ ] 2.1.1 Change to: `Via the Soleur GitHub repository, Docs Site, release notes, and Web Platform (app.soleur.ai) (including email notification for Web Platform users with an account on file);`
- [ ] 2.2 Update DPD Section 8.2(b) in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  - [ ] 2.2.1 Apply identical content change as 2.1
- [ ] 2.3 Update "Last Updated" header in both files -- prepend "added Web Platform email notification to Section 8.2(b)" to existing entries
  - [ ] 2.3.1 Root copy header
  - [ ] 2.3.2 Eleventy copy header (both plain text and HTML `<p>` tag versions)

## Phase 3: Testing

- [ ] 3.1 Run `diff` between root and Eleventy DPD copies to verify no unintended content drift
- [ ] 3.2 Verify Section 8.2(b) text matches expected wording in both copies
- [ ] 3.3 Verify parenthetical uses "Web Platform users with an account on file" (matching PR #919 pattern)
- [ ] 3.4 Run full test suite to confirm no regressions
