# Tasks: Fix DPD Section 4.1 Sub-processor Contradiction

## Phase 1: Setup

- [x] 1.1 Read `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` to confirm current state
- [x] 1.2 Verify no other branches have pending changes to the same file (`git log --all --oneline -- plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)

## Phase 2: Core Implementation

- [x] 2.1 Update "Last Updated" date on lines 12 and 21 to March 18, 2026
- [x] 2.2 Rewrite Section 4.1 heading from "No Sub-processors" to "Plugin Sub-processors"
- [x] 2.3 Rewrite Section 4.1 body to scope the "no sub-processors" statement to the Plugin only, with cross-reference to Section 2.1
- [x] 2.4 Insert new Section 4.2 "Docs Site Processors" with Buttondown disclosure table (processor name, processing activity, data processed, legal basis, sub-processor list link)
- [x] 2.5 Renumber current Section 4.2 to Section 4.3
- [x] 2.6 Remove Buttondown row from the Section 4.3 third-party services table
- [x] 2.7 Update Section 4.3 introductory text to clarify these are user-initiated interactions (not Jikigai-engaged processors)

## Phase 3: Verification

- [x] 3.1 Cross-reference updated Section 4.1/4.2 against Section 2.3(e) to confirm consistency
- [x] 3.2 Cross-reference against Privacy Policy Section 5.3 (Buttondown description)
- [x] 3.3 Cross-reference against GDPR Policy Item 6 (Buttondown description)
- [x] 3.4 Verify no broken internal cross-references within the DPD (section numbers referenced elsewhere in the document)
- [x] 3.5 Run `skill: soleur:compound` before commit
