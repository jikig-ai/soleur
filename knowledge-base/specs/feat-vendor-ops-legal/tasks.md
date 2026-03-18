# Tasks: vendor-ops-legal

## Phase 1: Ops -- Expense Ledger

- [ ] 1.1 Verify whether Hetzner CX22 is decommissioned or running in parallel with CX33
- [ ] 1.2 Add Hetzner CX33 recurring entry (~EUR 15.37/mo, 4 vCPU, 8 GB RAM, hel1)
- [ ] 1.3 Add Hetzner Volume recurring entry (~EUR 0.88/mo, 20 GB, hel1)
- [ ] 1.4 Add Supabase free tier entry ($0, note upgrade thresholds)
- [ ] 1.5 Add Stripe test mode entry ($0, note per-txn costs when live)
- [ ] 1.6 Add Resend free tier entry ($0, note 3K emails/mo threshold)
- [ ] 1.7 Update Cloudflare entry with `app.soleur.ai` subdomain note
- [ ] 1.8 Update `last_updated` date in expenses.md

## Phase 2: Legal -- DPA Verification

- [ ] 2.1 Research Hetzner DPA -- verify Helsinki coverage, signing mechanism
- [ ] 2.2 Research Supabase DPA -- verify free-tier coverage, US region transfer mechanism
- [ ] 2.3 Research Stripe DPA -- verify all-tier coverage, PCI scope (SAQ-A vs SAQ-D)
- [ ] 2.4 Confirm Cloudflare DPA already applies (existing relationship, new subdomain)
- [ ] 2.5 Research Resend DPA -- verify free-tier coverage, data residency
- [ ] 2.6 Document DPA findings in a vendor DPA memo (`knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md`)

## Phase 3: Privacy Policy Updates

- [ ] 3.1 Draft new Section 4.7 (Web Platform Data Collection) for privacy policy
- [ ] 3.2 Add Supabase, Stripe, Hetzner, Resend to Section 5 (Third-Party Services)
- [ ] 3.3 Update Section 10 (International Data Transfers) with new vendors
- [ ] 3.4 Update "Last Updated" date and change description
- [ ] 3.5 Apply changes to `docs/legal/privacy-policy.md`
- [ ] 3.6 Apply identical changes to `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [ ] 3.7 Verify cross-references to DPD and GDPR policy remain consistent

## Phase 4: Data Protection Disclosure Updates

- [ ] 4.1 Update Section 2 to distinguish plugin (local) vs. web platform (cloud)
- [ ] 4.2 Add web platform processing activities to Section 2.3
- [ ] 4.3 Add Supabase, Stripe, Hetzner, Resend to Section 4.2 processor table
- [ ] 4.4 Address Section 8 ("Future Cloud Features") -- mark transition as active
- [ ] 4.5 Update "Last Updated" date and change description
- [ ] 4.6 Apply changes to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`

## Phase 5: GDPR Policy Updates

- [ ] 5.1 Add web platform services to Section 2.2 (Third-Party Services)
- [ ] 5.2 Add web platform lawful bases to Section 3 (contract performance, legitimate interest)
- [ ] 5.3 Add web platform data categories to Section 4.2 table
- [ ] 5.4 Add web platform transfer disclosures to Section 6
- [ ] 5.5 Add processing activities 7-10 to Section 10 (Article 30 register)
- [ ] 5.6 Update "Last Updated" date and change description
- [ ] 5.7 Apply changes to `docs/legal/gdpr-policy.md`
- [ ] 5.8 Apply identical changes to `plugins/soleur/docs/pages/legal/gdpr-policy.md`

## Phase 6: Vendor Checklist Gate

- [ ] 6.1 Strengthen vendor-management rule in constitution.md (line 109 area)
- [ ] 6.2 Add vendor checklist section to constitution.md with concrete steps
- [ ] 6.3 Add conditional vendor checklist to PR template (`.github/PULL_REQUEST_TEMPLATE.md`) if template exists
- [ ] 6.4 Verify checklist is actionable for future PRs

## Phase 7: Verification & Commit

- [ ] 7.1 Cross-reference all updated documents for consistency (dates, vendor names, section numbers)
- [ ] 7.2 Run compound skill before commit
- [ ] 7.3 Commit and push all changes
