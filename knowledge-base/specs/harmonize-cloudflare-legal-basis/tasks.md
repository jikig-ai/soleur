# Tasks: Harmonize Cloudflare Dual Legal Basis

## Phase 1: Source File Edits

- [ ] 1.1 Edit DPD Section 2.1b(d) (`docs/legal/data-protection-disclosure.md:72`) -- add Cloudflare unauthenticated traffic qualifier with Section 4.2 cross-reference
- [ ] 1.2 Edit GDPR Policy Section 3.7 (`docs/legal/gdpr-policy.md:87`) -- add fourth bullet for CDN/proxy processing with dual legal basis
- [ ] 1.3 Edit Privacy Policy Section 6 (`docs/legal/privacy-policy.md:186`) -- add Cloudflare technical data sentence with dual basis and Section 5.8 cross-reference
- [ ] 1.4 Update "Last Updated" date in DPD frontmatter if applicable

## Phase 2: Mirror File Sync

- [ ] 2.1 Sync DPD edit to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 2.2 Sync GDPR Policy edit to `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] 2.3 Sync Privacy Policy edit to `plugins/soleur/docs/pages/legal/privacy-policy.md`

## Phase 3: Verification

- [ ] 3.1 Grep verification -- confirm "legitimate interest" count increased by 1 in each of the 6 files
- [ ] 3.2 Grep for conflict markers in all edited files
- [ ] 3.3 Cross-reference check -- verify DPD Section 4.2 wording is consistent with all three new additions
- [ ] 3.4 Run compound before commit
