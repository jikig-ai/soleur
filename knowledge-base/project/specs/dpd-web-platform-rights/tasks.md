# Tasks: DPD Section 5.3 Web Platform Data Subject Rights

**Plan:** `knowledge-base/plans/2026-03-20-legal-dpd-web-platform-data-subject-rights-plan.md`
**Branch:** `dpd-web-platform-rights`
**Issue:** #888

## Phase 1: Implementation

- [ ] 1.1 Add Section 5.3 to `docs/legal/data-protection-disclosure.md`
  - [ ] 1.1.1 Insert new Section 5.3 "Web Platform Data" after Section 5.2, before the `---` separator
  - [ ] 1.1.2 Enumerate all six GDPR rights (Articles 15-18, 20-21) with Web Platform context
  - [ ] 1.1.3 Include contact channel (legal@jikigai.com) and response timeline (Article 12(3))
  - [ ] 1.1.4 Add cross-reference to GDPR Policy Section 5 (relative markdown link)
  - [ ] 1.1.5 Update "Last Updated" date in frontmatter and document header

- [ ] 1.2 Add Section 5.3 to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  - [ ] 1.2.1 Insert identical Section 5.3 content
  - [ ] 1.2.2 Adjust links to HTML paths (`/pages/legal/gdpr-policy.html`)
  - [ ] 1.2.3 Update "Last Updated" date in hero section and document header

## Phase 2: Verification

- [ ] 2.1 Cross-file consistency check: verify both DPD files have identical legal content (differing only in link format)
- [ ] 2.2 Cross-document consistency check: verify Section 5.3 data categories match Section 2.1b
- [ ] 2.3 Verify no section numbering conflicts (Section 6 still follows Section 5)
- [ ] 2.4 Run markdownlint on both files
