# Tasks: Legal Cross-Document Audit Findings (#890)

## Phase 1: Privacy Policy Fixes

- [ ] 1.1 Update Privacy Policy Section 1 intro to include Web Platform in scope (Finding 1)
- [ ] 1.2 Add Web Platform security measures paragraph to Privacy Policy Section 11 (Finding 2)
- [ ] 1.3 Update Privacy Policy "Last Updated" date and change description

## Phase 2: Data Protection Disclosure Fixes

- [ ] 2.1 Rename DPD Section 3.1 heading from "Local-Only Architecture" to "Plugin Architecture (Local-Only)" (Finding 3)
- [ ] 2.2 Remove Buttondown row from DPD Section 4.3 table (Finding 5)
- [ ] 2.3 Update Cloudflare legal basis in DPD Section 4.2 to dual basis (Finding 6)
- [ ] 2.4 Add DPD Section 10.3 for Web Platform account deletion with T&C 13.1b cross-reference (Finding 7)
- [ ] 2.5 Update DPD "Last Updated" date and change description

## Phase 3: GDPR Policy Fix

- [ ] 3.1 Add "Web Platform (app.soleur.ai)" to GDPR Policy Section 1 scope enumeration (Finding 4)
- [ ] 3.2 Update GDPR Policy "Last Updated" date and change description

## Phase 4: Mirror Files and Validation

- [ ] 4.1 Check if `plugins/soleur/docs/pages/legal/` mirror files differ from `docs/legal/` source files
- [ ] 4.2 Sync mirror files if they are separate copies (not symlinks)
- [ ] 4.3 Verify no cross-document references are broken
- [ ] 4.4 Verify acceptance criteria pass (all 7 findings resolved)
