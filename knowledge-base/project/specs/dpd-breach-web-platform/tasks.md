# Tasks: DPD Section 7.2 Breach Notification -- Web Platform

## Phase 1: Implementation

- [ ] 1.1 Update "Last Updated" date in `docs/legal/data-protection-disclosure.md`
- [ ] 1.2 Edit Section 7.2 platform list to add "Web Platform (app.soleur.ai)" in `docs/legal/data-protection-disclosure.md` (line 237)
- [ ] 1.3 Edit Section 7.2(b) to specify email notification for Web Platform users in `docs/legal/data-protection-disclosure.md` (line 240)
- [ ] 1.4 Update "Last Updated" date in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 1.5 Edit Section 7.2 platform list to add "Web Platform (app.soleur.ai)" in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (line 246)
- [ ] 1.6 Edit Section 7.2(b) to specify email notification for Web Platform users in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (line 249)

## Phase 2: Verification

- [ ] 2.1 Run `diff` between root and Eleventy copies of Section 7 to confirm identical content
- [ ] 2.2 Grep for "distribution channels" across all legal docs to confirm no other sections need updating
- [ ] 2.3 Grep for breach-related sections missing Web Platform references
- [ ] 2.4 Verify GDPR Policy Section 11 consistency (should already reference Web Platform -- no change expected)
- [ ] 2.5 Run compound checks
