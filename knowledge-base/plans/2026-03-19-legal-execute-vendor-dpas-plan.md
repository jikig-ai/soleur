---
title: "legal: execute Hetzner and Supabase DPAs before beta"
type: chore
date: 2026-03-19
issue: "#702"
priority: p1-high
---

# legal: Execute Hetzner and Supabase DPAs Before Beta

## Overview

Issue #702 (derived from CLO review #670) requires executing DPAs with four web platform vendors before beta launch. Two require active signing (Hetzner, Supabase), one is auto-incorporated (Stripe), and one needs free-tier verification (Cloudflare). This is a GDPR Article 28 compliance gate -- without executed DPAs, processing EU user data through these vendors is unlawful.

The legal document updates for these vendors were already completed in a prior PR (the vendor-ops-legal work from #670/#732). This issue is specifically about the **execution** (signing) of the DPAs themselves plus verification of the auto-incorporated ones, then updating our docs to record execution dates and status.

## Problem Statement

The web platform (app.soleur.ai) is deployed with four external processors, but two DPAs remain unsigned:

| Vendor | DPA Status | Risk Level | Blocking? |
|--------|-----------|------------|-----------|
| Hetzner Online GmbH | **NOT SIGNED** -- requires click-to-sign in account dashboard | LOW (EU-only, Helsinki) | **YES** -- no Art. 28 agreement in place |
| Supabase Inc | **NOT SIGNED** -- requires PandaDoc via dashboard | HIGH (US data residency, us-east-1) | **YES** -- no Art. 28 agreement, plus Chapter V transfer concerns |
| Stripe Inc | Auto-incorporated in Services Agreement | LOW | No -- DPA is automatic |
| Cloudflare Inc | Self-Serve Agreement likely constitutes Main Agreement | LOW | No -- verify only |

**Supabase is the highest-risk item.** Data resides in AWS us-east-1 (US). Supabase uses SCCs (Module 2, C2P) as the Chapter V transfer mechanism -- no DPF certification. The DPA must be executed to activate these SCCs.

## Proposed Solution

### Phase 1: Hetzner DPA Execution (Playwright-assisted)

**1.1 Sign the DPA (AVV) via Hetzner Cloud Console**

- Navigate to Hetzner Cloud Console (console.hetzner.cloud)
- Go to account settings / data protection section
- Execute the Auftragsverarbeitungsvertrag (AVV) -- this is a click-to-sign process per ToS Section 6.2
- **Use Playwright MCP** to automate the signing if credentials are available in the environment. If not, document exact steps for the founder.
- Capture a screenshot of the signed DPA confirmation for records.

**1.2 Verify the DPA content**

Run the Art. 28(3) compliance matrix (per learning `third-party-dpa-gap-analysis-pattern`):

- Processing on documented instructions (Art. 28(3)(a))
- Confidentiality obligations (Art. 28(3)(b))
- Technical/organizational measures (Art. 28(3)(c))
- Sub-processor provisions (Art. 28(3)(d))
- Data subject rights assistance (Art. 28(3)(e))
- Deletion/return after termination (Art. 28(3)(f))
- Audit rights (Art. 28(3)(h))
- Breach notification timeline
- No international transfer concerns (EU-only: Helsinki, Finland)

**1.3 Record execution**

- Update `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md` -- change Hetzner status from "NOT SIGNED" to "SIGNED [date]"

### Phase 2: Supabase DPA Execution (HIGH RISK)

**2.1 Verify project region**

- Check Supabase dashboard for the project region (configured via `NEXT_PUBLIC_SUPABASE_URL`)
- If us-east-1 (default, US), document the transfer mechanism requirement (SCCs Module 2)
- If EU region is available and migration is feasible, consider migrating to reduce transfer risk

**2.2 Verify free-tier DPA availability**

- Navigate to Supabase dashboard > Project Settings > Legal Documents
- Check if PandaDoc DPA signing is available for the free-tier project
- If NOT available: document the gap and plan Pro upgrade ($25/mo) -- add to expense ledger
- If available: proceed to signing

**2.3 Review the Supabase DPA before signing**

Run the Art. 28(3) compliance matrix against the Supabase DPA PDF:

- Processing on documented instructions
- Confidentiality obligations
- Technical/organizational measures
- Sub-processor provisions (check for sub-processor list URL)
- Data subject rights assistance
- Deletion/return after termination
- Audit rights
- Breach notification timeline
- **International transfer mechanism** -- CRITICAL: Supabase uses SCCs (Module 2, C2P) per their privacy policy. Verify the DPA incorporates SCCs with the correct Module and Implementing Decision reference (2021/914)
- DPA Annex with processing details (subject matter, duration, data types, data subject categories)
- Governing law

**2.4 Verify GDPR Chapter V transfer safeguards**

Since Supabase is US-based (AWS us-east-1) and NOT DPF-certified:

- Confirm SCCs (Implementing Decision (EU) 2021/914, Module 2: Controller-to-Processor) are incorporated
- Check if a Transfer Impact Assessment (TIA) is needed -- evaluate US surveillance risk for the data categories processed (email, hashed passwords, auth tokens)
- Supabase privacy policy confirms transfers to US and Singapore, with SCCs as the mechanism
- Document the analysis in the DPA verification memo

**2.5 Execute the DPA via PandaDoc**

- **Use Playwright MCP** to navigate to the Supabase dashboard and initiate PandaDoc signing
- Complete the PandaDoc form with Jikigai's details (company name, address, DPO contact)
- If PandaDoc requires interactive elements that cannot be automated (digital signature draw), hand to the founder for that single step
- Capture confirmation/receipt

**2.6 Record execution**

- Update `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md` -- change Supabase status to "SIGNED [date]" with region and transfer mechanism details

### Phase 3: Stripe DPA Verification

**3.1 Confirm auto-incorporation**

- Verify that Stripe's DPA (last updated November 18, 2025) is automatically part of the Stripe Services Agreement
- The DPA "forms part of the Agreement" -- no separate execution required
- Transfer mechanisms: EU-US DPF (adequacy decision) + SCCs (EEA Module 2)
- Applies to all Stripe accounts regardless of tier

**3.2 Record verification**

- Update DPA verification memo to confirm Stripe status as "AUTOMATIC -- part of Services Agreement, verified [date]"

### Phase 4: Cloudflare DPA Verification

**4.1 Verify free-tier coverage**

- Cloudflare's DPA explicitly covers Self-Serve Subscription Agreement customers
- The DPA applies to those who have "entered into an Enterprise Subscription Agreement, Self-Serve Subscription Agreement or other written or electronic agreement"
- The existing `soleur.ai` zone relationship establishes the Self-Serve Agreement as the Main Agreement
- `app.soleur.ai` extends the same processing relationship

**4.2 Check dashboard for DPA acceptance status**

- **Use Playwright MCP** to navigate to Cloudflare dashboard and check for any DPA acceptance UI
- The DPA appears to be automatically applicable once the Self-Serve Agreement is in effect
- Transfer mechanisms: DPF + SCCs (Module 2 and Module 3) + Global CBPR certification

**4.3 Record verification**

- Update DPA verification memo to confirm Cloudflare status as "COVERED -- Self-Serve Agreement constitutes Main Agreement, verified [date]"

### Phase 5: Documentation Updates

**5.1 Update DPA verification memo**

Update `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md` with:

- Execution dates for Hetzner and Supabase
- Verification dates for Stripe and Cloudflare
- Any findings from the Art. 28(3) compliance matrix reviews
- Supabase Chapter V transfer analysis

**5.2 Update legal documents with execution confirmation**

Update the following files to record DPA execution status (both source and Eleventy copies per learning `dpa-vendor-response-verification-lifecycle`):

- `docs/legal/data-protection-disclosure.md` -- Section 4.2 processor table, add DPA execution dates
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- same updates
- `docs/legal/privacy-policy.md` -- update third-party service sections with DPA execution status
- `plugins/soleur/docs/pages/legal/privacy-policy.md` -- same updates
- `docs/legal/gdpr-policy.md` -- update DPA references
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- same updates

**5.3 Run legal-compliance-auditor**

Per learning `legal-cross-document-audit-review-cycle`, run the legal-compliance-auditor agent AFTER all edits to catch cross-document inconsistencies. Fix all P1/P2 findings before committing.

**5.4 Update "Last Updated" dates**

Update all modified legal documents' "Last Updated" fields.

### Phase 6: Expense Ledger Update (if Supabase upgrade required)

If Phase 2.2 reveals that the free-tier does not support DPA signing:

- Update `knowledge-base/operations/expenses.md` with Supabase Pro tier ($25/mo)
- Document the upgrade trigger as "DPA availability requires Pro tier"

## SpecFlow Analysis

### Edge Cases and Gaps

1. **Hetzner Cloud Console vs Robot**: Issue #702 says "Robot dashboard" but the verification memo says "Cloud Console." Hetzner has two dashboards -- Robot (robot.your-server.de) for dedicated servers and Cloud Console (console.hetzner.cloud) for cloud servers. The CX33 is a cloud server, so **Cloud Console is correct**. The issue description is slightly misleading.

2. **Supabase free-tier DPA availability**: Unknown until dashboard is checked. Two branches:
   - Available: sign via PandaDoc, no cost change
   - Not available: upgrade to Pro ($25/mo), update expense ledger, then sign

3. **Supabase region migration**: If the project is in us-east-1 and an EU region is available, migrating would eliminate the Chapter V transfer issue entirely. However, region migration may require creating a new project and migrating data. This should be evaluated but NOT blocked on -- the SCCs provide a lawful transfer mechanism even with US residency.

4. **PandaDoc interactive signing**: PandaDoc may require drawing a signature or clicking through multiple interactive steps. Playwright can handle most form interactions, but a drawn signature would require founder intervention.

5. **Cloudflare DPA "activation"**: Unlike Hetzner (explicit sign) and Supabase (PandaDoc), Cloudflare's DPA appears to activate automatically with the Self-Serve Agreement. There may be no explicit "sign DPA" button in the dashboard. If so, the analysis that the Self-Serve Agreement constitutes the Main Agreement is sufficient documentation.

6. **Stripe DPA version drift**: Stripe's DPA was last updated November 18, 2025. If Stripe updates their DPA between now and beta, our documentation references will need updating. Low risk but worth noting.

7. **Dual-location legal doc sync**: Per learning `dpa-vendor-response-verification-lifecycle`, ALL legal docs exist in two locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`). Every edit must be applied to both. Missing one location is a recurring error pattern.

## Acceptance Criteria

- [ ] Hetzner DPA (AVV) signed via Cloud Console with screenshot confirmation
- [ ] Supabase DPA signed via PandaDoc (or Pro upgrade documented if free-tier unavailable)
- [ ] Supabase Chapter V transfer safeguards verified (SCCs Module 2, Implementing Decision 2021/914)
- [ ] Supabase project region documented (us-east-1 or EU)
- [ ] Stripe DPA auto-incorporation verified
- [ ] Cloudflare DPA free-tier coverage verified (Self-Serve Agreement = Main Agreement)
- [ ] DPA verification memo updated with execution/verification dates for all four vendors
- [ ] Legal documents updated with DPA execution status in both source and Eleventy copies
- [ ] Legal-compliance-auditor run post-edit with zero P1/P2 findings
- [ ] "Last Updated" dates current on all modified legal documents
- [ ] Expense ledger updated if Supabase Pro upgrade required

## Test Scenarios

- Given the Hetzner Cloud Console is accessed, when the DPA section is navigated, then a click-to-sign AVV is available and can be executed
- Given the Supabase dashboard is accessed, when the Legal Documents section is checked, then either PandaDoc DPA signing is available (proceed) or it is gated to paid tier (document gap)
- Given the Supabase DPA is reviewed, when the Chapter V transfer mechanism is checked, then SCCs (Module 2, C2P, Decision 2021/914) are incorporated
- Given the Stripe Services Agreement is reviewed, when the DPA incorporation is checked, then the DPA "forms part of the Agreement" with no separate execution required
- Given the Cloudflare dashboard is accessed, when the DPA status is checked, then the Self-Serve Agreement constitutes the Main Agreement for free-tier users
- Given all DPAs are executed/verified, when the DPA verification memo is reviewed, then all four vendors have execution/verification dates and status
- Given all legal docs are updated, when legal-compliance-auditor is run, then zero P1/P2 cross-document inconsistencies are found
- Given a CNIL auditor requests proof of DPA execution, when Jikigai produces the verification memo, then each vendor has a documented execution mechanism, date, and transfer safeguards

## Dependencies & Risks

**Dependencies:**

- Hetzner Cloud Console credentials (founder has access)
- Supabase dashboard credentials (founder has access)
- Cloudflare dashboard credentials (founder has access)
- Playwright MCP for browser automation of signing flows

**Risks:**

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Supabase free-tier does not support DPA signing | Medium | High -- blocks compliance | Upgrade to Pro ($25/mo); budget already documented |
| Supabase DPA lacks proper SCC incorporation | Low | Critical -- no lawful transfer basis | Review DPA before signing; if SCCs not properly incorporated, request amendment or document gap |
| Hetzner Cloud Console DPA UI has changed | Low | Low -- delay only | Fall back to manual steps for founder |
| PandaDoc requires drawn signature | Medium | Low -- founder intervention needed | Playwright drives to signature step, founder draws |
| Legal doc dual-location sync missed | Medium | Medium -- inconsistent published docs | Use grep verification patterns post-edit; run compliance auditor |

## References

### Internal References

- Issue: #702
- CLO review: #670
- Prior vendor-ops-legal work: #732 (merged)
- DPA verification memo: `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md`
- Vendor-ops-legal plan: `knowledge-base/plans/2026-03-18-chore-vendor-ops-legal-web-platform-services-plan.md`
- Legal docs (source): `docs/legal/data-protection-disclosure.md`, `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`
- Legal docs (Eleventy): `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`, etc.
- Expense ledger: `knowledge-base/operations/expenses.md`

### Learnings Applied

- `2026-03-11-third-party-dpa-gap-analysis-pattern.md` -- Art. 28(3) compliance matrix
- `2026-03-19-dpa-vendor-response-verification-lifecycle.md` -- dual-location sync, compliance auditor gate
- `2026-03-18-legal-cross-document-audit-review-cycle.md` -- post-edit audit cycle
- `2026-02-21-github-dpa-free-plan-scope-limitation.md` -- DPA tier-gating precedent

### External References

- Hetzner ToS (Section 6.2 DPA clause): https://www.hetzner.com/legal/terms-and-conditions/
- Supabase DPA: https://supabase.com/legal/dpa
- Supabase Privacy Policy (SCCs confirmation): https://supabase.com/privacy
- Stripe DPA (updated November 18, 2025): https://stripe.com/legal/dpa
- Cloudflare DPA: https://www.cloudflare.com/cloudflare-customer-dpa/
- EU SCCs Implementing Decision 2021/914: https://eur-lex.europa.eu/eli/dec_impl/2021/914/oj
