# Tasks: Harmonize Cloudflare Dual Legal Basis

## Phase 1: Source File Edits

- [ ] 1.1 Edit DPD Section 2.1b(d) (`docs/legal/data-protection-disclosure.md:72`) -- add Cloudflare unauthenticated traffic qualifier with Section 4.2 cross-reference
- [ ] 1.2 Edit GDPR Policy Section 3.7 (`docs/legal/gdpr-policy.md:87`) -- add fourth bullet for CDN/proxy processing with dual legal basis and Recital 49 citation
- [ ] 1.2.1 Update GDPR Policy Section 3.7 closing sentence (`docs/legal/gdpr-policy.md:89`) -- scope "no balancing test" to contract performance bullets, add inline balancing test for legitimate interest (consistent with Sections 3.3, 3.4, 3.6 pattern)
- [ ] 1.3 Edit Privacy Policy Section 6 (`docs/legal/privacy-policy.md:186`) -- add Cloudflare technical data sentence with dual basis and Section 5.8 cross-reference
- [ ] 1.4 Update "Last Updated" lines on all three source documents (DPD line 12, GDPR Policy line 13, Privacy Policy line 11)

## Phase 2: Mirror File Sync

- [ ] 2.1 Sync DPD body edit + "Last Updated" to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 2.2 Sync GDPR Policy body edit + closing sentence + "Last Updated" to `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] 2.3 Sync Privacy Policy body edit + "Last Updated" to `plugins/soleur/docs/pages/legal/privacy-policy.md`

## Phase 3: Verification

- [ ] 3.1 Grep verification -- confirm "legitimate interest" count increased in each of the 6 files
- [ ] 3.2 Grep for conflict markers in all edited files
- [ ] 3.3 Cross-reference check -- verify DPD Section 4.2 wording is consistent with all three new additions
- [ ] 3.4 Diff source vs. mirror body content (excluding frontmatter) for each pair to confirm identical bodies
- [ ] 3.5 Verify GDPR Policy CDN/proxy balancing test follows the same (a), (b), (c), (d) pattern as Sections 3.3, 3.4, 3.6
- [ ] 3.6 Run compound before commit
