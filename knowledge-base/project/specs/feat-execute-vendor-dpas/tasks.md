# Tasks: Execute Vendor DPAs Before Beta

**Plan:** `knowledge-base/project/plans/2026-03-19-legal-execute-vendor-dpas-plan.md`
**Issue:** #702
**Deepened:** 2026-03-19

## Phase 1: Hetzner DPA Execution

- [ ] 1.1 Navigate to Hetzner Cloud Console (console.hetzner.cloud) and sign the DPA (AVV)
  - [ ] 1.1.1 Use Playwright MCP to automate if credentials available
  - [ ] 1.1.2 Capture screenshot of signed DPA confirmation
  - [ ] 1.1.3 Check if telegram-bridge uses same Cloud Console account or separate Robot server
- [ ] 1.2 Run Art. 28(3) compliance matrix against the Hetzner DPA content
- [ ] 1.3 Update DPA verification memo with Hetzner execution date and findings

## Phase 2: Supabase DPA Execution (HIGH RISK)

- [ ] 2.1 Check Supabase project region via dashboard (us-east-1 or EU?)
  - [ ] 2.1.1 If us-east-1: evaluate EU region migration feasibility (pre-beta = cheapest time)
- [ ] 2.2 Check if PandaDoc DPA signing is available for free-tier project
  - [ ] 2.2.1 If NOT available: document gap, plan Pro upgrade ($25/mo), update expense ledger
- [ ] 2.3 Review Supabase DPA PDF against Art. 28(3) compliance matrix
  - [ ] 2.3.1 Verify SCC incorporation (Module 2, C2P, Decision 2021/914)
  - [ ] 2.3.2 Check DPA Annex for processing details
  - [ ] 2.3.3 Verify sub-processor provisions (check Singapore sub-processors)
- [ ] 2.4 Verify GDPR Chapter V transfer safeguards
  - [ ] 2.4.1 Confirm SCCs Module 2 incorporated
  - [ ] 2.4.2 Document Transfer Impact Assessment (TIA) for US data categories
  - [ ] 2.4.3 Assess Singapore transfer risk if sub-processors are located there
  - [ ] 2.4.4 Document analysis in DPA verification memo
- [ ] 2.5 Execute DPA via PandaDoc (Playwright MCP, founder for signature if needed)
  - [ ] 2.5.1 Provide company details: Jikigai, 25 rue de Ponthieu, 75008 Paris, France
  - [ ] 2.5.2 Try typed signature first; fall back to founder for drawn signature
- [ ] 2.6 Update DPA verification memo with Supabase execution date and transfer analysis

## Phase 3: Stripe DPA Verification

- [ ] 3.1 Confirm DPA auto-incorporation in Stripe Services Agreement
- [ ] 3.2 Identify Stripe contracting entity (Stripe Payments Europe, Ltd. or Stripe, LLC)
- [ ] 3.3 Record verification date in DPA verification memo

## Phase 4: Cloudflare DPA Verification

- [ ] 4.1 Verify Self-Serve Agreement constitutes Main Agreement for free-tier
- [ ] 4.2 Check Cloudflare dashboard for DPA acceptance status (Playwright MCP)
- [ ] 4.3 Verify data categories in Cloudflare DPA match our DPD disclosure (IP addresses, request headers)
- [ ] 4.4 Record verification date in DPA verification memo

## Phase 5: Documentation Updates

- [ ] 5.1 Update DPA verification memo with all execution/verification dates and TIA summary
- [ ] 5.2 Update legal documents with DPA execution status
  - [ ] 5.2.1 `docs/legal/data-protection-disclosure.md` -- Section 4.2 DPA dates
  - [ ] 5.2.2 `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- same
  - [ ] 5.2.3 `docs/legal/privacy-policy.md` -- DPA execution status
  - [ ] 5.2.4 `plugins/soleur/docs/pages/legal/privacy-policy.md` -- same
  - [ ] 5.2.5 `docs/legal/gdpr-policy.md` -- DPA references
  - [ ] 5.2.6 `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- same
- [ ] 5.3 Update "Last Updated" dates on all modified legal documents
- [ ] 5.4 Run grep verification: `grep -rn "NOT SIGNED\|pending.*DPA" docs/legal/ plugins/soleur/docs/pages/legal/`
- [ ] 5.5 Run legal-compliance-auditor post-edit
- [ ] 5.6 Fix all P1/P2 findings from auditor

## Phase 6: Expense Ledger (Conditional)

- [ ] 6.1 If Supabase free-tier does not support DPA: update `knowledge-base/operations/expenses.md` with Pro tier ($25/mo)
