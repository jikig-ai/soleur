# Tasks: fix-privacy-policy-buttondown-xref

## Phase 1: Verification

- [ ] 1.1 Read `plugins/soleur/docs/pages/legal/privacy-policy.md` and confirm Section 4.6 references "Section 5.4"
- [ ] 1.2 Read `docs/legal/privacy-policy.md` and confirm Section 4.6 already references "Section 5.3"
- [ ] 1.3 Verify no other stale cross-references exist between Sections 4 and 5 in either file

## Phase 2: Core Implementation

- [ ] 2.1 Edit `plugins/soleur/docs/pages/legal/privacy-policy.md` line 101: change "Section 5.4" to "Section 5.3"

## Phase 3: Testing

- [ ] 3.1 Grep both privacy policy files for "Section 5" references and confirm consistency
- [ ] 3.2 Diff the two files to confirm no other unintended divergences in cross-references
