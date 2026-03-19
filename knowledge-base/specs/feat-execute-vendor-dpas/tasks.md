# Tasks: Execute Vendor DPAs Before Beta

**Plan:** `knowledge-base/plans/2026-03-19-legal-execute-vendor-dpas-plan.md`
**Issue:** #702

## Phase 1: Hetzner DPA Execution

- [ ] 1.1 Navigate to Hetzner Cloud Console (console.hetzner.cloud) and sign the DPA (AVV)
  - [ ] 1.1.1 Use Playwright MCP to automate if credentials available
  - [ ] 1.1.2 Capture screenshot of signed DPA confirmation
- [ ] 1.2 Run Art. 28(3) compliance matrix against the Hetzner DPA content
- [ ] 1.3 Update DPA verification memo with Hetzner execution date and findings

## Phase 2: Supabase DPA Execution (HIGH RISK)

- [ ] 2.1 Check Supabase project region via dashboard (us-east-1 or EU?)
- [ ] 2.2 Check if PandaDoc DPA signing is available for free-tier project
  - [ ] 2.2.1 If NOT available: document gap, plan Pro upgrade ($25/mo), update expense ledger
- [ ] 2.3 Review Supabase DPA PDF against Art. 28(3) compliance matrix
  - [ ] 2.3.1 Verify SCC incorporation (Module 2, C2P, Decision 2021/914)
  - [ ] 2.3.2 Check DPA Annex for processing details
  - [ ] 2.3.3 Verify sub-processor provisions
- [ ] 2.4 Verify GDPR Chapter V transfer safeguards
  - [ ] 2.4.1 Confirm SCCs Module 2 incorporated
  - [ ] 2.4.2 Evaluate Transfer Impact Assessment (TIA) need
  - [ ] 2.4.3 Document analysis in DPA verification memo
- [ ] 2.5 Execute DPA via PandaDoc (Playwright MCP, founder for signature if needed)
- [ ] 2.6 Update DPA verification memo with Supabase execution date and transfer analysis

## Phase 3: Stripe DPA Verification

- [ ] 3.1 Confirm DPA auto-incorporation in Stripe Services Agreement
- [ ] 3.2 Record verification date in DPA verification memo

## Phase 4: Cloudflare DPA Verification

- [ ] 4.1 Verify Self-Serve Agreement constitutes Main Agreement for free-tier
- [ ] 4.2 Check Cloudflare dashboard for DPA acceptance status (Playwright MCP)
- [ ] 4.3 Record verification date in DPA verification memo

## Phase 5: Documentation Updates

- [ ] 5.1 Update DPA verification memo with all execution/verification dates
- [ ] 5.2 Update legal documents with DPA execution status
  - [ ] 5.2.1 `docs/legal/data-protection-disclosure.md` -- Section 4.2 DPA dates
  - [ ] 5.2.2 `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- same
  - [ ] 5.2.3 `docs/legal/privacy-policy.md` -- DPA execution status
  - [ ] 5.2.4 `plugins/soleur/docs/pages/legal/privacy-policy.md` -- same
  - [ ] 5.2.5 `docs/legal/gdpr-policy.md` -- DPA references
  - [ ] 5.2.6 `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- same
- [ ] 5.3 Update "Last Updated" dates on all modified legal documents
- [ ] 5.4 Run legal-compliance-auditor post-edit
- [ ] 5.5 Fix all P1/P2 findings from auditor

## Phase 6: Expense Ledger (Conditional)

- [ ] 6.1 If Supabase free-tier does not support DPA: update `knowledge-base/operations/expenses.md` with Pro tier ($25/mo)
