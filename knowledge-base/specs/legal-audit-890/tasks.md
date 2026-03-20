# Tasks: Legal Cross-Document Audit Findings (#890)

## Phase 0: Pre-Implementation Verification

- [ ] 0.1 Run grep inventory for all references that will change: `Buttondown` in DPD Section 4.3, `Local-Only Architecture` heading, `Cloudflare.*Article 6` across all legal docs
- [ ] 0.2 Read all 6 target files (3 source + 3 Eleventy mirrors) to satisfy Edit tool preconditions

## Phase 1: Privacy Policy Fixes (Source)

- [ ] 1.1 Update Privacy Policy Section 1 intro to include Web Platform in scope (Finding 1)
- [ ] 1.2 Add Web Platform security measures paragraph to Privacy Policy Section 11 (Finding 2)
- [ ] 1.3 Update Privacy Policy "Last Updated" date and change description

## Phase 2: Data Protection Disclosure Fixes (Source)

- [ ] 2.1 Rename DPD Section 3.1 heading from "Local-Only Architecture" to "Plugin Architecture (Local-Only)" (Finding 3)
- [ ] 2.2 Remove Buttondown row from DPD Section 4.3 table (Finding 5)
- [ ] 2.3 Update Cloudflare legal basis in DPD Section 4.2 to dual basis: contract performance for authenticated users, legitimate interest for unauthenticated traffic (Finding 6)
- [ ] 2.4 Add DPD Section 10.3 for Web Platform account deletion with T&C 13.1b cross-reference (Finding 7)
- [ ] 2.5 Update DPD "Last Updated" date and change description

## Phase 3: GDPR Policy Fix (Source)

- [ ] 3.1 Add "Web Platform (app.soleur.ai)" to GDPR Policy Section 1 scope enumeration (Finding 4)
- [ ] 3.2 Update GDPR Policy "Last Updated" date and change description

## Phase 4: Eleventy Mirror File Sync

- [ ] 4.1 Apply Finding 1 fix to `plugins/soleur/docs/pages/legal/privacy-policy.md` (adapt intro)
- [ ] 4.2 Apply Finding 2 fix to `plugins/soleur/docs/pages/legal/privacy-policy.md` (add security paragraph)
- [ ] 4.3 Update Privacy Policy mirror hero section `<p>` tag with new "Last Updated" text
- [ ] 4.4 Apply Findings 3, 5, 6, 7 fixes to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  - [ ] 4.4.1 Rename heading (Finding 3)
  - [ ] 4.4.2 Remove Buttondown row (Finding 5)
  - [ ] 4.4.3 Update Cloudflare legal basis (Finding 6)
  - [ ] 4.4.4 Add Section 10.3 with `/pages/legal/terms-and-conditions.html` link format (Finding 7)
- [ ] 4.5 Apply Finding 4 fix to `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] 4.6 Update "Last Updated" dates/descriptions in all 3 mirror files

## Phase 5: Post-Edit Verification

- [ ] 5.1 Run grep verification: Buttondown removed from DPD 4.3, heading renamed, Cloudflare dual basis present
- [ ] 5.2 Verify cross-reference integrity: all "Section X.Y" references resolve to existing sections
- [ ] 5.3 Verify mirror file body content matches source (allowing for frontmatter and link format differences)
- [ ] 5.4 Run legal-compliance-auditor agent on all 3 source documents
- [ ] 5.5 Fix any P1/P2 findings from compliance auditor (budget for one fix-reverify cycle)
- [ ] 5.6 File GitHub issues for any out-of-scope findings discovered during the audit
