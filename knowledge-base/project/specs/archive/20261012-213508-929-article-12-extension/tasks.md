# Tasks: Article 12(3) Two-Month Extension Provision

## Phase 1: Preparation

- [ ] 1.1 Check if PR #916 has merged (`gh pr view 916 --json state`); if merged, merge origin/main into this branch
- [ ] 1.2 Identify whether GDPR Policy Section 5.3 (from PR #916) exists; if so, add it to the edit list

## Phase 2: Source File Edits (`docs/legal/`)

- [ ] 2.1 Edit `docs/legal/gdpr-policy.md` Section 14 -- append extension sentence after Article 12(3) reference
- [ ] 2.2 Edit `docs/legal/data-protection-disclosure.md` Section 5.3 -- insert extension sentence between Article 12(3) reference and "For full details" cross-reference
- [ ] 2.3 Edit `docs/legal/terms-and-conditions.md` Section 17 -- append extension sentence after Article 12(3) reference
- [ ] 2.4 Edit `docs/legal/privacy-policy.md` Section 14 -- append extension sentence after Article 12(3) reference
- [ ] 2.5 Update "Last Updated" header in each source file

## Phase 3: Mirror File Edits (`plugins/soleur/docs/pages/legal/`)

- [ ] 3.1 Edit `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- mirror changes from 2.1
- [ ] 3.2 Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- mirror changes from 2.2 (preserve Eleventy link format)
- [ ] 3.3 Edit `plugins/soleur/docs/pages/legal/terms-and-conditions.md` -- mirror changes from 2.3
- [ ] 3.4 Edit `plugins/soleur/docs/pages/legal/privacy-policy.md` -- mirror changes from 2.4
- [ ] 3.5 Update "Last Updated" header in each mirror file

## Phase 4: Conditional -- GDPR Policy Section 5.3 (if PR #916 merged)

- [ ] 4.1 Edit `docs/legal/gdpr-policy.md` new Section 5.3 -- append extension sentence
- [ ] 4.2 Edit `plugins/soleur/docs/pages/legal/gdpr-policy.md` new Section 5.3 -- mirror

## Phase 5: Validation

- [ ] 5.1 Grep all 8 (or 10) files for "two further months" to confirm extension language is present
- [ ] 5.2 Grep to verify no remaining "one month" sentences lack the extension provision
- [ ] 5.3 Diff source vs mirror copies to confirm consistency (modulo Eleventy link format)
- [ ] 5.4 Run markdownlint on all modified files
- [ ] 5.5 If PR #916 is still open, post an advisory comment noting it should include extension language

## Phase 6: Ship

- [ ] 6.1 Run compound
- [ ] 6.2 Commit and push
- [ ] 6.3 Create PR with `Closes #929` in body
