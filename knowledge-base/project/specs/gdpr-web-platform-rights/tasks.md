# Tasks: GDPR Policy Web Platform Rights Subsection

## Phase 1: Implementation (docs/legal/gdpr-policy.md)

- [ ] 1.1 Read `docs/legal/gdpr-policy.md` Section 5 in full
- [ ] 1.2 Update Section 5 intro paragraph: replace "these rights are exercisable directly against Jikigai by contacting <legal@jikigai.com>" with "these rights are exercisable directly against Jikigai (see Section 5.3)"
- [ ] 1.3 Add Section 5.3 "Rights Exercisable Against Jikigai (Web Platform)" after Section 5.2
  - [ ] 1.3.1 Insert six GDPR rights enumeration (Articles 15-18, 20-21)
  - [ ] 1.3.2 Include Right to Erasure with parenthetical "payment records (subscription metadata, invoices)" and cross-ref Section 8.4
  - [ ] 1.3.3 Include Right to Object contract-performance qualification (Article 6(1)(b))
  - [ ] 1.3.4 Include 5-business-day acknowledgment and one-month response timeline (Article 12(3))
- [ ] 1.4 Renumber Section 5.3 (Supervisory Authority) to Section 5.4
- [ ] 1.5 Update "Last Updated" date and changelog note in frontmatter header

## Phase 2: Eleventy Mirror Sync (plugins/soleur/docs/pages/legal/gdpr-policy.md)

- [ ] 2.1 Read `plugins/soleur/docs/pages/legal/gdpr-policy.md` Section 5
- [ ] 2.2 Update Section 5 intro paragraph with same forward reference
- [ ] 2.3 Apply identical Section 5.3 content (no link adjustments needed -- section has no inter-document links)
- [ ] 2.4 Renumber Section 5.3 to 5.4
- [ ] 2.5 Update "Last Updated" date in the hero section paragraph

## Phase 3: Cross-Reference Verification

- [ ] 3.1 Grep all legal docs for "GDPR Policy Section 5.3" to confirm zero hits (renumbering is safe)
- [ ] 3.2 Verify T&C Section 8.4 cross-reference to "GDPR Policy Section 5" still resolves correctly
- [ ] 3.3 Verify DPD Section 5.3 cross-reference to "companion GDPR Policy Section 5" still resolves correctly
- [ ] 3.4 Verify response timelines match across: GDPR Policy Section 14, T&C Section 17, DPD Section 5.3, new Section 5.3

## Phase 4: Validation

- [ ] 4.1 Diff both GDPR Policy copies to confirm legal content is identical (only link format and HTML wrapper differ)
- [ ] 4.2 Verify Article 30 register count in Section 10 still says "nine processing activities"
- [ ] 4.3 Run compound checks
- [ ] 4.4 Commit and push
