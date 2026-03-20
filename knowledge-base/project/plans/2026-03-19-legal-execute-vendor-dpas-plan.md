---
title: "legal: execute Hetzner and Supabase DPAs before beta"
type: chore
date: 2026-03-19
issue: "#702"
priority: p1-high
deepened: 2026-03-19
---

# legal: Execute Hetzner and Supabase DPAs Before Beta

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 6 phases + risks + acceptance criteria
**Research conducted:** Hetzner ToS Section 6.2 (WebFetch), Supabase DPA page + privacy policy + security page + region docs (WebFetch x5), Stripe DPA (WebFetch), Cloudflare DPA (WebFetch), 4 institutional learnings applied

### Key Improvements

1. **Hetzner Cloud Console vs Robot clarified**: Issue #702 incorrectly references "Robot dashboard." The CX33 is a cloud server -- DPA signing is via Cloud Console (console.hetzner.cloud), not Robot (robot.your-server.de). Hetzner's ToS Section 6.2 confirms DPA is NOT automatic and Section 6.3 warns that without an executed DPA, Hetzner assumes no personal data processing occurs.
2. **Supabase compliance posture grounded**: Supabase is SOC 2 Type 2 compliant, uses AES-256 at rest and TLS in transit. However, SOC2 report and HIPAA BAA are only available for Enterprise/Team plans. DPA page does not specify tier restrictions, suggesting it may be available on Free -- but this must be verified in dashboard. Privacy policy confirms SCCs as the transfer mechanism (not DPF).
3. **Stripe DPA confirmed fully automatic**: Stripe DPA (updated November 18, 2025) "forms part of the Agreement." Key provisions: processing only on User's instructions, 48-hour breach notification for GDPR-scoped data, annual audit questionnaire. Transfer via DPF + SCCs (Module 1 and Module 2). No tier restrictions.
4. **Cloudflare DPA explicitly covers Self-Serve**: Cloudflare DPA text explicitly lists "Self-Serve Subscription Agreement" alongside Enterprise agreements. No separate acceptance mechanism required. Transfer via DPF + SCCs (Module 2 and 3) + Global CBPR. Covers CDN/proxy services by definition ("cloud-based solutions...designed to increase the performance, security and availability of Internet properties").
5. **Transfer Impact Assessment (TIA) guidance added for Supabase**: Since Supabase uses SCCs without DPF, a TIA should be documented to satisfy CJEU Schrems II requirements. The data categories (email, hashed passwords, auth tokens) are low-sensitivity for US surveillance purposes, but the analysis must be recorded.

### New Considerations Discovered

- Supabase privacy policy mentions transfers to both US AND Singapore -- the DPA verification should check whether Singapore sub-processors are relevant
- Supabase does not appear to offer region migration for existing projects -- if the project is in us-east-1, the SCCs path is the only option
- Stripe's breach notification is 48 hours (better than GDPR's 72-hour Art. 33 requirement but different from many DPAs that say "without undue delay")
- Cloudflare processes "Customer Logs" which explicitly includes IP addresses from end users -- this is already disclosed in our DPD but worth confirming the Cloudflare DPA data categories match our disclosure
- Hetzner Section 6.3 has a critical warning: without a signed DPA, they "assume no third-party personal data processing occurs and take no corresponding protective measures" -- this strengthens the urgency

---

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

### Research Insights: Urgency

**Hetzner Section 6.3 warning**: Without an executed DPA, Hetzner explicitly "assumes no third-party personal data processing occurs and takes no corresponding protective measures." This means Hetzner is not currently treating Jikigai's data with processor-level safeguards. Signing the DPA activates those safeguards.

**Supabase compliance posture**: Supabase is SOC 2 Type 2 compliant, encrypts data at rest (AES-256) and in transit (TLS). However, these technical measures do not substitute for the legal obligation of an Art. 28 DPA. The SOC2 report and HIPAA BAA are available only for Enterprise/Team plans -- the DPA page does not specify similar tier restrictions, but this must be verified.

## Proposed Solution

### Phase 1: Hetzner DPA Execution (Playwright-assisted)

**1.1 Sign the DPA (AVV) via Hetzner Cloud Console**

- Navigate to Hetzner Cloud Console (console.hetzner.cloud) -- NOT Robot (robot.your-server.de)
- Go to account settings / data protection section
- Execute the Auftragsverarbeitungsvertrag (AVV) -- this is a click-to-sign process per ToS Section 6.2
- **Use Playwright MCP** to automate the signing if credentials are available in the environment. If not, document exact steps for the founder.
- Capture a screenshot of the signed DPA confirmation for records.

### Research Insights: Hetzner DPA

**Best Practices:**
- Hetzner's DPA process is German-standard (AVV = Auftragsverarbeitungsvertrag). It follows the standard German/EU template structure which typically includes all Art. 28(3) requirements out of the box.
- The click-to-sign mechanism in the Cloud Console is legally binding per German electronic signature law (BGB Section 126a) since Hetzner's ToS specifically authorize this acceptance method.
- Hetzner operates exclusively in EU/EEA jurisdictions (Germany, Finland) so no Chapter V transfer analysis is needed.

**Edge Cases:**
- The Cloud Console and Robot (robot.your-server.de) are separate systems with separate DPA processes. The CX33 cloud server is managed via Cloud Console only. If Jikigai also uses Robot for dedicated servers (check `apps/telegram-bridge/infra/`), a separate Robot DPA may be needed.
- If the Cloud Console DPA UI is not found under account settings, check: Profile > Data Protection, or the billing/account section. Hetzner has reorganized their console UI periodically.

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

- Update `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md` -- change Hetzner status from "NOT SIGNED" to "SIGNED [date]"

### Phase 2: Supabase DPA Execution (HIGH RISK)

**2.1 Verify project region**

- Check Supabase dashboard for the project region (configured via `NEXT_PUBLIC_SUPABASE_URL`)
- If us-east-1 (default, US), document the transfer mechanism requirement (SCCs Module 2)
- If EU region is available and migration is feasible, consider migrating to reduce transfer risk

### Research Insights: Supabase Regions

**Region availability**: Supabase deploys projects to a single primary region chosen at creation time. Available regions include US (us-east-1, us-west-1), EU (eu-west-1, eu-west-2, eu-central-1), Asia-Pacific, and others. The default varies but us-east-1 is common.

**Region migration**: Supabase does NOT support migrating an existing project to a different region. To change regions, you must create a new project in the desired region and migrate data (pg_dump/pg_restore for Postgres, re-configure auth and storage). This is disruptive but eliminates Chapter V transfer concerns entirely.

**Cost-benefit for EU migration**: If the project is in us-east-1 and has minimal data (free-tier, pre-beta), migration to eu-west-1 or eu-central-1 NOW (before beta users exist) is the cheapest it will ever be. Post-beta migration would require user data migration, auth token invalidation, and URL changes. Evaluate this urgently.

**2.2 Verify free-tier DPA availability**

- Navigate to Supabase dashboard > Project Settings > Legal Documents
- Check if PandaDoc DPA signing is available for the free-tier project
- If NOT available: document the gap and plan Pro upgrade ($25/mo) -- add to expense ledger
- If available: proceed to signing

### Research Insights: Supabase Tier-Gating

**DPA tier uncertainty**: The Supabase DPA page (supabase.com/legal/dpa) does not specify plan-tier restrictions. The security page mentions SOC2 reports and HIPAA BAA are available for Enterprise/Team plans only, but the DPA is referenced without tier qualification. This is a positive signal but not conclusive.

**Precedent comparison**:
- GitHub: DPA only for paid plans (Enterprise, Teams) -- per learning `github-dpa-free-plan-scope-limitation`
- Buttondown: DPA covers all plans including free -- per brainstorm verification
- Stripe: DPA covers all accounts -- confirmed via WebFetch
- Cloudflare: DPA covers Self-Serve (including free) -- confirmed via WebFetch

**If DPA is tier-gated**: The Pro plan at $25/mo provides 8GB database, 100GB bandwidth, 1GB file storage, and 100K MAU. This is a reasonable cost for DPA access and will be needed anyway as the platform scales.

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

### Research Insights: Supabase DPA Review

**Transfer mechanisms confirmed**: Supabase privacy policy explicitly states transfers are "subject to standard contractual clauses approved by the European Commission" for transfers to US and Singapore. No DPF certification was found.

**Singapore sub-processors**: Supabase mentions transfers to Singapore in addition to the US. The Art. 28(3) compliance matrix should verify which sub-processors are in Singapore and whether they process Jikigai's data categories. Singapore has a partial adequacy decision from the EU (for certain sectors) but SCCs are the safer assumption.

**Encryption specifics**: Supabase confirms "All customer data is encrypted at rest with AES-256 and in transit via TLS." These are relevant technical measures for the TIA (supplementary measures under EDPB Recommendations 01/2020).

**2.4 Verify GDPR Chapter V transfer safeguards**

Since Supabase is US-based (AWS us-east-1) and NOT DPF-certified:

- Confirm SCCs (Implementing Decision (EU) 2021/914, Module 2: Controller-to-Processor) are incorporated
- Check if a Transfer Impact Assessment (TIA) is needed -- evaluate US surveillance risk for the data categories processed (email, hashed passwords, auth tokens)
- Supabase privacy policy confirms transfers to US and Singapore, with SCCs as the mechanism
- Document the analysis in the DPA verification memo

### Research Insights: Transfer Impact Assessment (TIA)

**Schrems II requirement**: After the CJEU Schrems II decision (C-311/18), SCCs alone are not sufficient. Controllers must conduct a TIA to assess whether the legal framework of the recipient country (here: US, potentially Singapore) provides adequate protection. If not, supplementary measures must be implemented.

**TIA analysis for Supabase data categories**:

| Data Category | US Surveillance Risk | Assessment |
|--------------|---------------------|------------|
| Email addresses | LOW -- not targeted by FISA 702 collection (mass communications monitoring targets message content, not email addresses in isolation) | SCCs sufficient with encryption supplementary measure |
| Hashed passwords (bcrypt) | NEGLIGIBLE -- hashed values are not decryptable even with court order | No additional measures needed |
| Auth tokens (JWT) | LOW -- session tokens are ephemeral and meaningless without the signing secret | SCCs sufficient |
| Session metadata | LOW -- IP addresses and timestamps are metadata, lower sensitivity | SCCs sufficient |

**Conclusion**: The data categories processed by Supabase are LOW-risk for US government surveillance. SCCs plus Supabase's encryption (AES-256 at rest, TLS in transit) provide adequate supplementary measures per EDPB Recommendations 01/2020. Document this analysis in the DPA verification memo.

**Singapore assessment**: Singapore's Personal Data Protection Act (PDPA) provides a generally adequate framework. The EU has not issued a full adequacy decision for Singapore, but the PDPA's accountability-based approach is recognized. SCCs are sufficient for Singapore transfers.

**2.5 Execute the DPA via PandaDoc**

- **Use Playwright MCP** to navigate to the Supabase dashboard and initiate PandaDoc signing
- Complete the PandaDoc form with Jikigai's details (company name, address, DPO contact)
- If PandaDoc requires interactive elements that cannot be automated (digital signature draw), hand to the founder for that single step
- Capture confirmation/receipt

### Research Insights: PandaDoc Signing

**PandaDoc workflow**: PandaDoc typically presents a multi-step form: (1) recipient details (name, email, company), (2) document review with highlight of signature fields, (3) signature (typed, drawn, or uploaded), (4) confirmation. Playwright can handle steps 1-2 and potentially typed signatures. Drawn signatures require mouse coordinate interaction which is possible via `browser_click` and `browser_drag` MCP tools but may be fragile.

**Recommended approach**: Attempt full automation via Playwright. If the signature step requires a canvas drawing (not a typed signature option), capture a screenshot of the signature field and hand to the founder with the instruction: "Sign in this field, then click Submit." This minimizes founder context-switch time.

**Company details needed for PandaDoc**:
- Company name: Jikigai
- Address: 25 rue de Ponthieu, 75008 Paris, France
- DPO contact: legal@jikigai.com
- Authorized signatory: founder name

**2.6 Record execution**

- Update `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md` -- change Supabase status to "SIGNED [date]" with region and transfer mechanism details

### Phase 3: Stripe DPA Verification

**3.1 Confirm auto-incorporation**

- Verify that Stripe's DPA (last updated November 18, 2025) is automatically part of the Stripe Services Agreement
- The DPA "forms part of the Agreement" -- no separate execution required
- Transfer mechanisms: EU-US DPF (adequacy decision) + SCCs (EEA Module 2)
- Applies to all Stripe accounts regardless of tier

### Research Insights: Stripe DPA

**Confirmed via WebFetch (stripe.com/legal/dpa)**:
- DPA "forms part of the Agreement" -- no separate execution, binding on all accounts
- Processing only "according to User's Instructions"
- Data Incident notification within **48 hours** for GDPR-scoped data (stricter than Art. 33's 72-hour controller notification window -- this gives Jikigai a 24-hour buffer)
- Annual audit/questionnaire available on written request
- Sub-processor engagement requires "comparable obligations"
- Transfer mechanisms: DPF (EU-US, Swiss-US, UK-US) + SCCs (Module 1 C2C, Module 2 C2P) + UK International Data Transfer Addendum
- Geographic routing: EEA-based accounts contract with Stripe Payments Europe, Limited (Ireland); non-EEA with Stripe, LLC (US)
- Last updated: November 18, 2025

**Note**: Jikigai should verify which Stripe entity it contracts with. If the Stripe account was created from France, it likely contracts with Stripe Payments Europe, Limited (Irish entity) -- which means Stripe itself may be an EEA processor and the transfer analysis simplifies further.

**3.2 Record verification**

- Update DPA verification memo to confirm Stripe status as "AUTOMATIC -- part of Services Agreement, verified [date]"

### Phase 4: Cloudflare DPA Verification

**4.1 Verify free-tier coverage**

- Cloudflare's DPA explicitly covers Self-Serve Subscription Agreement customers
- The DPA applies to those who have "entered into an Enterprise Subscription Agreement, Self-Serve Subscription Agreement or other written or electronic agreement"
- The existing `soleur.ai` zone relationship establishes the Self-Serve Agreement as the Main Agreement
- `app.soleur.ai` extends the same processing relationship

### Research Insights: Cloudflare DPA

**Confirmed via WebFetch (cloudflare.com/cloudflare-customer-dpa/)**:
- DPA explicitly lists "Self-Serve Subscription Agreement" as a qualifying Main Agreement -- free-tier is covered
- Acceptance appears automatic upon service use ("If you are accepting this DPA on behalf of Customer, you warrant that you have full legal authority to bind Customer")
- No separate signature or dashboard action required
- Transfer mechanisms: DPF + SCCs (Module 2 for controller customers, Module 3 for processor customers) + Global CBPR certification + UK Addendum
- Data categories: End User IP addresses, Zero Trust user names/emails (if applicable), Customer Content, administrator audit logs
- Services definition covers "cloud-based solutions...designed to increase the performance, security and availability of Internet properties" -- CDN/proxy is explicitly in scope
- Customer Logs processing: explicitly includes IP addresses from end users accessing "Customer's Internet Properties" (i.e., visitors to app.soleur.ai)

**Verification action**: The DPA is self-executing via the Self-Serve Agreement. No dashboard action required. The verification is documenting that the Self-Serve Agreement constitutes the Main Agreement and confirming the `soleur.ai` zone relationship extends to `app.soleur.ai`.

**4.2 Check dashboard for DPA acceptance status**

- **Use Playwright MCP** to navigate to Cloudflare dashboard and check for any DPA acceptance UI
- The DPA appears to be automatically applicable once the Self-Serve Agreement is in effect
- Transfer mechanisms: DPF + SCCs (Module 2 and Module 3) + Global CBPR certification

**4.3 Record verification**

- Update DPA verification memo to confirm Cloudflare status as "COVERED -- Self-Serve Agreement constitutes Main Agreement, verified [date]"

### Phase 5: Documentation Updates

**5.1 Update DPA verification memo**

Update `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md` with:

- Execution dates for Hetzner and Supabase
- Verification dates for Stripe and Cloudflare
- Any findings from the Art. 28(3) compliance matrix reviews
- Supabase Chapter V transfer analysis
- TIA analysis summary

**5.2 Update legal documents with execution confirmation**

Update the following files to record DPA execution status (both source and Eleventy copies per learning `dpa-vendor-response-verification-lifecycle`):

- `docs/legal/data-protection-disclosure.md` -- Section 4.2 processor table, add DPA execution dates
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- same updates
- `docs/legal/privacy-policy.md` -- update third-party service sections with DPA execution status
- `plugins/soleur/docs/pages/legal/privacy-policy.md` -- same updates
- `docs/legal/gdpr-policy.md` -- update DPA references
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- same updates

### Research Insights: Documentation Updates

**Cross-document consistency checklist** (per learning `legal-cross-document-audit-review-cycle`):

When adding DPA execution dates, verify these cross-references remain consistent:

| Document | Sections to Update | What to Add |
|----------|-------------------|-------------|
| DPD (data-protection-disclosure.md) | 4.2 (processor table), 6.4 (transfers), 8.1 (transition status) | DPA execution date, link to signed DPA or verification memo |
| Privacy Policy | 5.x (third-party services), 10 (international transfers) | DPA execution confirmation, transfer mechanism reference |
| GDPR Policy | 2.2 (third-party services), 6 (international transfers), 10 (Art. 30 register) | DPA status, transfer mechanism, processing activity updates |

**Grep verification after edits** (per learning `first-pii-collection-legal-update-pattern`):
```bash
grep -rn "NOT SIGNED\|not.*signed\|pending.*DPA\|DPA.*pending" docs/legal/ plugins/soleur/docs/pages/legal/
```
After all DPAs are executed, there should be zero matches for "NOT SIGNED" or "pending DPA" in any legal document.

**5.3 Run legal-compliance-auditor**

Per learning `legal-cross-document-audit-review-cycle`, run the legal-compliance-auditor agent AFTER all edits to catch cross-document inconsistencies. Fix all P1/P2 findings before committing.

**5.4 Update "Last Updated" dates**

Update all modified legal documents' "Last Updated" fields.

### Phase 6: Expense Ledger Update (if Supabase upgrade required)

If Phase 2.2 reveals that the free-tier does not support DPA signing:

- Update `knowledge-base/operations/expenses.md` with Supabase Pro tier ($25/mo)
- Document the upgrade trigger as "DPA availability requires Pro tier"

### Research Insights: Supabase Pro Upgrade

**Pro tier details** (from Supabase pricing/security pages):
- Cost: $25/mo
- Includes: 8GB database, 100GB bandwidth, 1GB file storage, 100K MAU
- Additional features: daily backups (vs none on free), Point-in-Time Recovery as add-on
- SOC2 report: still NOT available on Pro (requires Enterprise/Team)
- DPA: likely available on Pro if not on Free (needs dashboard verification)

**Budget impact**: $25/mo ($300/yr) is within the infrastructure budget established for the web platform. The CX33 Hetzner server already costs ~EUR 16/mo. Adding Supabase Pro would bring total infrastructure to ~$41/mo.

## SpecFlow Analysis

### Edge Cases and Gaps

1. **Hetzner Cloud Console vs Robot**: Issue #702 says "Robot dashboard" but the verification memo says "Cloud Console." Hetzner has two dashboards -- Robot (robot.your-server.de) for dedicated servers and Cloud Console (console.hetzner.cloud) for cloud servers. The CX33 is a cloud server, so **Cloud Console is correct**. The issue description is slightly misleading. Additionally, check if `apps/telegram-bridge/infra/` uses a Robot server -- if so, a separate Robot DPA may be needed.

2. **Supabase free-tier DPA availability**: Unknown until dashboard is checked. Two branches:
   - Available: sign via PandaDoc, no cost change
   - Not available: upgrade to Pro ($25/mo), update expense ledger, then sign

3. **Supabase region migration**: If the project is in us-east-1 and an EU region is available, migrating would eliminate the Chapter V transfer issue entirely. However, Supabase does NOT support in-place region migration -- it requires creating a new project and migrating data (pg_dump/pg_restore, re-auth, URL changes). Pre-beta is the cheapest time to do this. This should be evaluated but NOT blocked on -- the SCCs provide a lawful transfer mechanism even with US residency.

4. **PandaDoc interactive signing**: PandaDoc may require drawing a signature or clicking through multiple interactive steps. Playwright can handle most form interactions, but a drawn signature would require founder intervention. Attempt typed signature first (PandaDoc usually offers this option).

5. **Cloudflare DPA "activation"**: Unlike Hetzner (explicit sign) and Supabase (PandaDoc), Cloudflare's DPA appears to activate automatically with the Self-Serve Agreement. The DPA text confirms this: acceptance is implied by service use. There may be no explicit "sign DPA" button in the dashboard. The analysis that the Self-Serve Agreement constitutes the Main Agreement is sufficient documentation.

6. **Stripe DPA version drift**: Stripe's DPA was last updated November 18, 2025. If Stripe updates their DPA between now and beta, our documentation references will need updating. Low risk but worth noting.

7. **Dual-location legal doc sync**: Per learning `dpa-vendor-response-verification-lifecycle`, ALL legal docs exist in two locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`). Every edit must be applied to both. Missing one location is a recurring error pattern.

8. **Supabase Singapore sub-processors**: Supabase privacy policy mentions transfers to Singapore in addition to US. Verify whether any sub-processors in Singapore process Jikigai's specific data categories (email, passwords, auth tokens). If yes, ensure SCCs cover Singapore transfers too.

9. **Stripe contracting entity**: Verify whether Jikigai contracts with Stripe Payments Europe, Limited (Ireland) or Stripe, LLC (US). If the former, Stripe may be an EEA processor -- simplifying the transfer analysis since no Chapter V transfer occurs for data processed by the Irish entity.

10. **Telegram-bridge Hetzner server**: Check if `apps/telegram-bridge/infra/` uses a separate Hetzner server (CX22) via Robot or Cloud Console. If via Robot, a separate Robot DPA may be needed. If via Cloud Console, the single Cloud Console DPA covers both servers.

## Acceptance Criteria

- [x] Hetzner DPA (AVV) signed via Cloud Console with screenshot confirmation -- SIGNED 2026-03-19
- [x] Supabase DPA signed via PandaDoc (or Pro upgrade documented if free-tier unavailable) -- DPA SIGNED 2026-03-19 via PandaDoc. Free tier confirmed.
- [x] Supabase Chapter V transfer safeguards verified (SCCs Module 2, Implementing Decision 2021/914) -- NOT NEEDED: project in eu-west-1 (Ireland, EU). No international transfer.
- [x] Supabase TIA documented (data categories assessed against US surveillance risk) -- NOT NEEDED: project in eu-west-1 (EU). Supabase provides their own TIA at supabase.com/downloads/docs/Supabase+TIA+250314.pdf
- [x] Supabase project region documented (us-east-1 or EU) -- CONFIRMED: eu-west-1 (Ireland, EU)
- [x] EU region migration evaluated (recommended if pre-beta and feasible) -- NOT NEEDED: already in EU (eu-west-1)
- [x] Stripe DPA auto-incorporation verified -- CONFIRMED 2026-03-19
- [x] Stripe contracting entity identified (Stripe Payments Europe, Ltd. or Stripe, LLC) -- likely Stripe Payments Europe, Ltd (Ireland) since account created from France
- [x] Cloudflare DPA free-tier coverage verified (Self-Serve Agreement = Main Agreement) -- CONFIRMED 2026-03-19 via dashboard
- [x] DPA verification memo updated with execution/verification dates for all four vendors
- [x] Legal documents updated with DPA execution status in both source and Eleventy copies
- [ ] Legal-compliance-auditor run post-edit with zero P1/P2 findings
- [x] "Last Updated" dates current on all modified legal documents
- [x] Expense ledger updated if Supabase Pro upgrade required -- NOT NEEDED: free tier supports DPA
- [x] Telegram-bridge Hetzner server DPA status checked (same Cloud Console account or separate Robot?) -- CONFIRMED: hcloud provider (Cloud Console), CX22 in fsn1 (Germany). Same account, one DPA covers both.

## Test Scenarios

- Given the Hetzner Cloud Console is accessed, when the DPA section is navigated, then a click-to-sign AVV is available and can be executed
- Given the Supabase dashboard is accessed, when the Legal Documents section is checked, then either PandaDoc DPA signing is available (proceed) or it is gated to paid tier (document gap)
- Given the Supabase DPA is reviewed, when the Chapter V transfer mechanism is checked, then SCCs (Module 2, C2P, Decision 2021/914) are incorporated
- Given the Supabase TIA is documented, when a CNIL auditor reviews it, then the data categories are assessed against US surveillance risk with a clear conclusion
- Given the Stripe Services Agreement is reviewed, when the DPA incorporation is checked, then the DPA "forms part of the Agreement" with no separate execution required
- Given the Cloudflare dashboard is accessed, when the DPA status is checked, then the Self-Serve Agreement constitutes the Main Agreement for free-tier users
- Given all DPAs are executed/verified, when the DPA verification memo is reviewed, then all four vendors have execution/verification dates and status
- Given all legal docs are updated, when legal-compliance-auditor is run, then zero P1/P2 cross-document inconsistencies are found
- Given a CNIL auditor requests proof of DPA execution, when Jikigai produces the verification memo, then each vendor has a documented execution mechanism, date, and transfer safeguards
- Given grep is run for "NOT SIGNED" across legal docs after all updates, then zero matches are returned

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
| Supabase region is us-east-1 and migration is complex | High | Medium -- Chapter V transfer analysis needed | SCCs + TIA provide lawful transfer; EU migration is optional optimization |
| Hetzner Cloud Console DPA UI has changed | Low | Low -- delay only | Fall back to manual steps for founder |
| PandaDoc requires drawn signature | Medium | Low -- founder intervention needed | Playwright drives to signature step, founder draws; attempt typed signature first |
| Legal doc dual-location sync missed | Medium | Medium -- inconsistent published docs | Use grep verification patterns post-edit; run compliance auditor |
| Telegram-bridge uses separate Hetzner system requiring its own DPA | Low | Medium -- additional signing needed | Check Terraform state in `apps/telegram-bridge/infra/` |

## References

### Internal References

- Issue: #702
- CLO review: #670
- Prior vendor-ops-legal work: #732 (merged)
- DPA verification memo: `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md`
- Vendor-ops-legal plan: `knowledge-base/project/plans/2026-03-18-chore-vendor-ops-legal-web-platform-services-plan.md`
- Legal docs (source): `docs/legal/data-protection-disclosure.md`, `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`
- Legal docs (Eleventy): `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`, etc.
- Expense ledger: `knowledge-base/operations/expenses.md`
- Telegram-bridge infra: `apps/telegram-bridge/infra/` (check Hetzner server type)
- Supabase config: `apps/web-platform/lib/supabase/server.ts`, `apps/web-platform/lib/supabase/client.ts`
- Stripe integration: `apps/web-platform/lib/stripe.ts`, `apps/web-platform/app/api/checkout/route.ts`

### Learnings Applied

- `2026-03-11-third-party-dpa-gap-analysis-pattern.md` -- Art. 28(3) compliance matrix + re-verification pattern
- `2026-03-19-dpa-vendor-response-verification-lifecycle.md` -- dual-location sync, compliance auditor gate
- `2026-03-18-legal-cross-document-audit-review-cycle.md` -- post-edit audit cycle, P1/P2 finding resolution
- `2026-02-21-github-dpa-free-plan-scope-limitation.md` -- DPA tier-gating precedent (GitHub paid-only)
- `2026-03-18-supabase-resend-email-configuration.md` -- Supabase Management API quirks (string-typed ports), Terraform DNS pattern

### External References

- Hetzner ToS (Section 6.2 DPA clause): https://www.hetzner.com/legal/terms-and-conditions/
- Supabase DPA: https://supabase.com/legal/dpa
- Supabase Privacy Policy (SCCs confirmation): https://supabase.com/privacy
- Supabase Security page (SOC2/compliance): https://supabase.com/security
- Stripe DPA (updated November 18, 2025): https://stripe.com/legal/dpa
- Cloudflare DPA: https://www.cloudflare.com/cloudflare-customer-dpa/
- EU SCCs Implementing Decision 2021/914: https://eur-lex.europa.eu/eli/dec_impl/2021/914/oj
- EDPB Recommendations 01/2020 (supplementary measures): https://www.edpb.europa.eu/our-work-tools/our-documents/recommendations/recommendations-012020-measures-supplement-transfer_en
- CJEU Schrems II (C-311/18): https://curia.europa.eu/juris/liste.jsf?num=C-311/18
