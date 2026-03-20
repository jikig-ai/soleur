# Tasks: GDPR Policy Web Platform Rights Subsection

## Phase 1: Implementation

- [ ] 1.1 Read `docs/legal/gdpr-policy.md` Section 5 in full
- [ ] 1.2 Add Section 5.3 "Rights Exercisable Against Jikigai (Web Platform)" after Section 5.2
  - [ ] 1.2.1 Insert six GDPR rights enumeration (Articles 15-18, 20-21)
  - [ ] 1.2.2 Include Right to Erasure French tax law qualification (cross-ref Section 8.4)
  - [ ] 1.2.3 Include Right to Object contract-performance qualification
  - [ ] 1.2.4 Include 5-business-day acknowledgment and one-month response timeline
- [ ] 1.3 Renumber Section 5.3 (Supervisory Authority) to Section 5.4
- [ ] 1.4 Update "Last Updated" date and changelog note in frontmatter/header

## Phase 2: Eleventy Mirror Sync

- [ ] 2.1 Read `plugins/soleur/docs/pages/legal/gdpr-policy.md` Section 5
- [ ] 2.2 Apply identical Section 5.3 content (adjusting link format if needed)
- [ ] 2.3 Renumber Section 5.3 to 5.4
- [ ] 2.4 Update "Last Updated" date in the hero section

## Phase 3: Cross-Reference Verification

- [ ] 3.1 Grep all legal docs for "Section 5.3" to verify no broken cross-references after renumbering
- [ ] 3.2 Verify T&C Section 8.4 cross-reference to "GDPR Policy Section 5" still resolves correctly
- [ ] 3.3 Verify DPD Section 5.3 cross-reference to "companion GDPR Policy Section 5" still resolves correctly
- [ ] 3.4 Verify response timelines match: GDPR Policy Section 14, T&C Section 17, DPD Section 5.3

## Phase 4: Validation

- [ ] 4.1 Diff both GDPR Policy copies to confirm legal content is identical (only link format and HTML wrapper differ)
- [ ] 4.2 Run compound checks
- [ ] 4.3 Commit and push
