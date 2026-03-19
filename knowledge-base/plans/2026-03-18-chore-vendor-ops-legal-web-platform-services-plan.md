---
title: "chore: record new services from web platform deployment"
type: chore
date: 2026-03-18
issue: "#670"
priority: p1-high
deepened: 2026-03-18
---

# chore: Record New Services from Web Platform Deployment

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 6 phases + risks + acceptance criteria
**Research conducted:** DPA verification (5 vendors via WebFetch), Stripe integration audit (code review), Resend integration audit (code review), 8 institutional learnings applied, PR template review

### Key Improvements

1. **Resend scoped out**: No Resend integration exists in the codebase (grep across `apps/web-platform/` returned zero matches). Issue #670 lists it but it was never deployed. Reduced scope from 5 to 4 vendors, with Resend tracked as a future item.
2. **Hetzner DPA requires explicit action**: Hetzner ToS Section 6.2 confirms DPA is NOT automatically included -- customer must affirmatively conclude a DPA via their account dashboard. This is an immediate action item.
3. **Stripe PCI scope confirmed as SAQ-A**: Code review of `apps/web-platform/app/api/checkout/route.ts` confirms Stripe Checkout (server-side session, client-side redirect). Card data never touches Jikigai servers -- SAQ-A eligible.
4. **Resend DPA is DPF-certified**: Unlike Buttondown (SCCs only), Resend is certified under EU-US DPF. All 21 sub-processors are US-based. Relevant when Resend is eventually integrated.
5. **DPD has a second copy**: The DPD exists at `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy) but the root source copy at `docs/legal/data-processing-agreement.md` may be out of sync (per learning `dpd-processor-table-dual-file-sync`). Verify and update both.

### New Considerations Discovered

- Supabase DPA requires PandaDoc signing through the dashboard (not automatic via ToS)
- Supabase region is configured via env var `NEXT_PUBLIC_SUPABASE_URL` -- must verify which region the project was created in (EU vs US)
- Cloudflare DPA applicability for free-tier is ambiguous (tied to "Main Agreement" which may not exist for free plans)
- Legal documents contain blanket "does not collect personal data" statements that become contradictions (per learning `first-pii-collection-legal-update-pattern`) -- grep verification required after all edits
- Constitution references `knowledge-base/ops/expenses.md` but actual path is `knowledge-base/operations/expenses.md`

---

## Overview

PR #637 (feat/web-platform-ux) provisioned four new external services for the Soleur web platform (app.soleur.ai) without updating the expense ledger, verifying DPA coverage, or triggering legal review. This issue tracks the ops and legal follow-up required to bring the project back into compliance.

The web platform represents a fundamental architectural shift: Jikigai now operates cloud infrastructure that processes user PII (email addresses, auth tokens, API keys, payment data). The existing legal documents are predicated on Soleur being a "local-only plugin" with no Jikigai-operated cloud services. The DPD (Section 8) anticipated this transition and committed to specific disclosure updates before cloud processing begins.

## Problem Statement

Four services were deployed without the corresponding ops and legal hygiene (Resend was listed in #670 but has no code integration -- tracked separately):

| Service | Type | Est. Cost | Data Processed | DPA Status |
|---------|------|-----------|----------------|------------|
| Hetzner CX33 (Helsinki, `hel1`) | Server + volume hosting | ~EUR 15.37/mo (CX33) + EUR 0.88/mo (20GB volume) | User workspaces, Docker containers, API keys (encrypted) | **NOT signed** -- requires explicit action via account dashboard (ToS 6.2) |
| Supabase (free tier) | Auth + PostgreSQL | $0 (free tier, 500MB DB, 50K MAU) | User PII: email, hashed passwords, auth tokens, session data | Available via PandaDoc on dashboard -- verify free-tier coverage |
| Stripe (test mode) | Payment processing | $0 test + 2.9%+30c per txn live | Customer email (via Checkout redirect), subscription metadata | DPA is part of Stripe Agreement -- automatic. PCI: SAQ-A (Checkout) |
| Cloudflare (existing zone) | DNS + CDN/proxy for `app.soleur.ai` | $0 (free tier) | IP addresses, request headers via CDN proxy | DPA available but may require "Main Agreement" -- verify free-tier |

### Research Insights: Resend Status

Resend was listed in issue #670 but grep across `apps/web-platform/` for `resend`, `Resend`, `RESEND`, `email.*api`, and `transactional.*email` returned zero matches. No Resend dependency in `package.json`, no integration code. Resend should be:

- Removed from scope of THIS issue
- Added to the expense ledger as a placeholder ("PLANNED" status) when it is integrated
- Given its own DPA/legal review when the integration PR is opened (exactly the kind of gate Phase 6 creates)

## Proposed Solution

### Phase 1: Ops -- Expense Ledger Updates

Update `knowledge-base/operations/expenses.md` (verified correct path -- constitution references stale `knowledge-base/ops/expenses.md`, fix the constitution reference too):

**1.1 New recurring entries:**

- **Hetzner CX33**: ~EUR 15.37/mo, 4 vCPU, 8 GB RAM, 160 GB SSD, `hel1` (Helsinki). Determine if CX22 (EUR 5.83/mo, telegram-bridge) is still running or decommissioned -- check Hetzner console or Terraform state for `apps/telegram-bridge/infra/`.
- **Hetzner Volume**: ~EUR 0.88/mo, 20 GB, `hel1`. Persistent storage for `/workspaces`.
- **Supabase**: $0 (free tier). Note upgrade thresholds: 500MB DB, 50K MAU, 1GB file storage, 2GB bandwidth. Pro tier: $25/mo.
- **Stripe**: $0 (test mode). Note per-transaction costs when live: 2.9% + $0.30/charge (EU: 1.5% + EUR 0.25 for EU cards). No monthly minimum.

**1.2 Update existing entries:**

- **Cloudflare**: Add note that `app.soleur.ai` subdomain now uses Cloudflare proxy (A record pointing to Hetzner CX33). No additional cost on free tier.

### Research Insights: Expense Ledger

**Best Practices:**
- Add a "Status" column to distinguish `active`, `test-mode`, `free-tier`, `deferred`, and `decommissioned` services
- Include "Upgrade Trigger" notes (e.g., "Supabase: upgrade at 500MB DB or 50K MAU") so cost increases are predictable
- For Stripe, note that EU card pricing differs significantly from US (1.5% + EUR 0.25 vs 2.9% + $0.30) since the user base is likely EU-heavy given French company

### Phase 2: Legal -- DPA Verification

For each vendor, verify that a Data Processing Agreement covers the data Jikigai processes. This is a GDPR Article 28 obligation.

**Key learning**: GitHub's DPA only covers paid plans. Hetzner's DPA is not automatic. Always verify tier-gating AND acceptance mechanism.

**2.1 Hetzner DPA** -- ACTION REQUIRED

- **Finding**: Hetzner ToS Section 6.2 states: "We only process personal data as a processor of orders pursuant to Art. 28 GDPR if the Customer concludes a contract for processing orders with us. This contract for processing orders is not concluded automatically."
- **Action**: Log into Hetzner Cloud Console, navigate to account settings, and execute the DPA (Auftragsverarbeitungsvertrag / AVV). This is a click-to-sign process.
- Hetzner is EU-based (Germany). The Helsinki datacenter (`hel1`) is in Finland (EU). No international transfer concerns.
- Data processed: server compute, volume storage (user workspaces, Docker containers, encrypted API keys).
- **Use Playwright** to automate the DPA signing via the Hetzner Console if credentials are available. If not, document as a manual step for the founder.

**2.2 Supabase DPA** -- VERIFY FREE-TIER COVERAGE

- **Finding**: Supabase has a DPA available as a PDF, with a legally binding version obtainable through PandaDoc via the project dashboard's "Legal Documents" section.
- **Action**: Access the Supabase dashboard, check if the DPA is available for free-tier projects, and execute it if so. If not, document the gap and plan for Pro tier upgrade ($25/mo).
- **Region check**: The Supabase project URL (stored in `NEXT_PUBLIC_SUPABASE_URL` env var) determines the hosting region. Check whether the project was created in `us-east-1` (default) or an EU region. If US, document the transfer mechanism (SCCs).
- Data processed: user email addresses, hashed passwords, auth tokens, session metadata.

**2.3 Stripe DPA** -- CONFIRMED AUTOMATIC

- **Finding**: Stripe's DPA is incorporated into the Stripe Services Agreement automatically ("is subject to and forms part of the Agreement"). No separate execution required.
- **PCI Scope**: Code review confirms the integration uses `stripe.checkout.sessions.create()` with client-side redirect (`window.location.href = data.url`). Card data never touches Jikigai servers. This is SAQ-A eligible (simplest PCI self-assessment).
- **Transfer mechanism**: Stripe uses both EU-US DPF and SCCs (EEA SCCs Module 2). No EU data residency is offered -- data is transferred to Stripe, LLC in the US.
- Data processed: customer email (passed via `customer_email: user.email`), subscription metadata, Stripe-managed payment data.
- **Source files reviewed**: `apps/web-platform/lib/stripe.ts`, `apps/web-platform/app/api/checkout/route.ts`, `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`

**2.4 Cloudflare DPA** -- VERIFY FREE-TIER APPLICABILITY

- **Finding**: Cloudflare's DPA applies "where Cloudflare processes Personal Data as a Processor... on behalf of Customer to provide the Services" and is tied to the "Main Agreement" (Enterprise, Self-Serve, or written agreements). Free-tier customers may not have a formal Main Agreement.
- **Action**: Check Cloudflare dashboard for DPA acceptance status. Cloudflare's Self-Serve Subscription Agreement likely constitutes the Main Agreement for free-tier users, but this needs verification.
- **Transfer mechanism**: Cloudflare uses DPF, SCCs (Module 2 and Module 3), and Global CBPR certification.
- Data processed: IP addresses, request headers, TLS termination for `app.soleur.ai`.
- The existing `soleur.ai` zone relationship likely already covers this -- the `app` subdomain extends the same processing, not a new controller-processor relationship.

### Research Insights: DPA Verification

**Institutional Learnings Applied:**
- `github-dpa-free-plan-scope-limitation`: Always verify DPA tier-gating. The Hetzner finding confirms this pattern repeats across vendors.
- `buttondown-gdpr-transfer-mechanism-sccs-only`: Do not assume all US vendors use DPF. Verify each vendor individually. Stripe uses both DPF + SCCs. Resend (when integrated) uses DPF.
- `dogfood-legal-agents-cross-document-consistency`: Budget for a generate-audit-fix-reaudit cycle. Run `legal-compliance-auditor` after all edits.

**Edge Cases:**
- If Supabase DPA is not available for free tier, the remediation is upgrading to Pro ($25/mo) -- document this cost contingency in the expense ledger.
- If Cloudflare's free-tier DPA coverage is ambiguous, the Self-Serve Subscription Agreement likely suffices, but document the analysis in the DPA verification memo.

**Deliverable**: Write findings to `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md` with a row per vendor: DPA URL, tier coverage, acceptance mechanism, transfer mechanism, data categories.

### Phase 3: Legal -- Privacy Policy Updates

Update the Privacy Policy in BOTH locations (per learning `gdpr-article-30-compliance-audit-pattern`):

- `docs/legal/privacy-policy.md` (source markdown)
- `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy template)

**3.1 New Section: Web Platform Data Collection (Section 4.7)**

The privacy policy currently describes Soleur as a local-only plugin. The web platform introduces server-side data processing. Add a new Section 4.7:

- **What data is collected**: email address (registration), hashed password (Supabase-managed), auth tokens, session cookies, subscription status, encrypted API keys (BYOK).
- **Purpose**: providing the web platform service (account management, workspace provisioning, subscription billing).
- **Legal basis**: contract performance (Article 6(1)(b)) for service delivery.
- **Retention**: account data retained while account active; deleted on account deletion request. Payment records retained per French tax law (10 years, Code de commerce Art. L123-22).

**Note**: Exclude Resend/transactional email from this section since the integration does not exist yet. Add it when the integration PR is merged.

**3.2 New Third-Party Service Sections (Section 5.5-5.8)**

Add new subsections to Section 5:

- **5.5 Supabase** (auth + database): Supabase Inc, processor relationship, data categories, DPA reference, region disclosure.
- **5.6 Stripe** (payments): Stripe Inc, processor relationship, Checkout integration (no direct card handling), PCI Level 1, DPA reference.
- **5.7 Hetzner** (hosting): Hetzner Online GmbH, processor relationship, Helsinki datacenter, EU-only processing, DPA reference.
- **5.8 Cloudflare** (CDN/proxy): Update existing Section 5 or add new subsection noting `app.soleur.ai` uses Cloudflare proxy in addition to `soleur.ai`.

**3.3 Update International Data Transfers (Section 10)**

Add transfer disclosures for:

- Supabase: US-based (AWS), transfer via SCCs. Note if EU region is configured.
- Stripe: US-based (Stripe, LLC), transfer via DPF + SCCs (Module 2).
- Hetzner: EU-only (Germany/Finland), no international transfer.

### Research Insights: Privacy Policy

**Institutional Learnings Applied:**
- `first-pii-collection-legal-update-pattern`: After all targeted edits, run grep verification for blanket "does not collect" statements. The privacy policy currently says "does not collect, transmit, or store any personal data on external servers" (Section 4.1) and "The Plugin does not have its own backend, database, or cloud infrastructure" (Section 4.1). Both become contradictions with the web platform. **The Section 4.1 title "Data Collected by the Plugin: None" must be scoped to the plugin only, with a new section for the web platform.**
- `split-legal-basis-cross-section-consistency`: A change to Section 4 propagates to Sections 5, 6, 7, and 10. Use this checklist: data category (4.x), processor description (5.x), legal basis summary (6), retention (7), international transfers (10).

**Grep patterns to run after edits:**
```bash
grep -rn "does not collect" docs/legal/ plugins/soleur/docs/pages/legal/
grep -rn "no personal data" docs/legal/ plugins/soleur/docs/pages/legal/
grep -rn "no.*backend\|no.*database\|no.*cloud" docs/legal/ plugins/soleur/docs/pages/legal/
grep -rn "local.only\|locally.installed\|local machine" docs/legal/ plugins/soleur/docs/pages/legal/
```

### Phase 4: Legal -- Data Protection Disclosure Updates

Update the DPD in BOTH locations (per learning `dpd-processor-table-dual-file-sync`):

- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy template)
- `docs/legal/data-processing-agreement.md` (root source -- **verify this file exists and check sync status**)

**4.1 Restructure Section 2 ("Data Processing Relationship")**

The DPD Section 2.1 ("Soleur Is Not a Data Processor") is now partially incorrect. Restructure:

- **2.1 Plugin**: Retitle to "The Soleur Plugin Is Not a Data Processor" -- scope the local-only claims to the CLI plugin only.
- **2.1b (new)**: "Web Platform Data Processing" -- Jikigai operates the web platform (app.soleur.ai) as a cloud service. For the web platform, Jikigai acts as data controller AND engages processors (Supabase, Stripe, Hetzner, Cloudflare). This section fulfills the DPD's Section 8 commitment to update terms when cloud features are introduced.

**4.2 Update Section 2.3 ("Limited Processing by Soleur")**

Add web platform processing activities alongside existing items (a)-(e):

- **(f)** Web platform account management (app.soleur.ai via Supabase) -- email addresses, auth tokens, session data.
- **(g)** Web platform payment processing (app.soleur.ai via Stripe) -- subscription metadata, customer email. Card data handled exclusively by Stripe (PCI SAQ-A).
- **(h)** Web platform infrastructure hosting (app.soleur.ai via Hetzner) -- user workspaces, encrypted API keys, Docker containers. EU-only (Helsinki).

**4.3 Update Section 4.2 ("Docs Site Processors") -- Restructure as "Service Processors"**

Rename section to encompass both docs site and web platform processors. Add:

| Processor | Processing Activity | Data Processed | Legal Basis | Sub-processor List |
|-----------|-------------------|----------------|-------------|-------------------|
| Supabase Inc ([supabase.com](https://supabase.com)) | Web platform auth + database | Email addresses, hashed passwords, auth tokens, session data | Contract performance (Article 6(1)(b)) | [Supabase DPA](https://supabase.com/legal/dpa) |
| Stripe Inc ([stripe.com](https://stripe.com)) | Web platform payment processing (Stripe Checkout, PCI SAQ-A) | Customer email, subscription metadata (card data handled exclusively by Stripe) | Contract performance (Article 6(1)(b)) | [Stripe Sub-processors](https://stripe.com/legal/service-providers) |
| Hetzner Online GmbH ([hetzner.com](https://hetzner.com)) | Web platform infrastructure hosting (Helsinki, EU-only) | User workspaces, encrypted API keys, Docker containers | Contract performance (Article 6(1)(b)) | [Hetzner DPA](https://www.hetzner.com/legal/terms-and-conditions/) |

Cloudflare is already implicitly covered for DNS -- add a note that `app.soleur.ai` uses the same Cloudflare proxy as `soleur.ai`.

**4.4 Address Section 8 ("Future Cloud Features") -- Mark Transition Active**

Section 8 committed to specific actions. Mark each as fulfilled or in-progress:

- 8.1(a) Updated DPD with Article 28 terms: DONE (this PR)
- 8.1(b) Users notified before cloud processing: IN PROGRESS (privacy policy update)
- 8.1(c) Technical/organizational measures: DONE (encryption at rest, TLS, Helsinki EU hosting)
- 8.1(d) Sub-processor list maintained: DONE (Section 4.2 table)
- 8.1(e) SCCs for international transfers: DONE (Supabase, Stripe sections)
- 8.1(f) DPIA: Evaluate whether required (see Phase 5)

### Research Insights: DPD

**Institutional Learnings Applied:**
- `dpd-processor-table-dual-file-sync`: PR #686 restructured the Eleventy DPD but never propagated to the root copy. **Check `docs/legal/data-processing-agreement.md` sync status BEFORE editing. If out of sync, align first.**
- `dpd-sub-processor-contradiction-fix`: When adding new processors to Section 4.2, audit Section 4.1 ("No Sub-processors") to ensure it's scoped to the plugin. The current Section 4.1 says "there are no Plugin-level Sub-processors" which is correctly scoped.

**GDPR Terminology Precision:**
- Supabase, Stripe, Hetzner are **processors** (Jikigai is controller). They are NOT sub-processors (sub-processors would be processors engaged by Jikigai's processor).
- Supabase's own sub-processors (AWS, etc.) and Stripe's sub-processors are sub-processors from Jikigai's perspective, but Jikigai does not need to list them -- the processor (Supabase/Stripe) is responsible for sub-processor management per their DPA.

### Phase 5: Legal -- GDPR Policy Updates

Update the GDPR policy in BOTH locations:

- `docs/legal/gdpr-policy.md`
- `plugins/soleur/docs/pages/legal/gdpr-policy.md`

**5.1 Update Section 2.2 (Third-Party Services)**

Add web platform services with roles:

- **Supabase**: Processor for web platform auth and database. Supabase Inc, US-based, SCCs.
- **Stripe**: Processor for web platform payments. Stripe Inc, PCI Level 1. Stripe Checkout integration (SAQ-A) -- card data never reaches Jikigai servers.
- **Hetzner**: Processor for web platform hosting. Hetzner Online GmbH, EU-based (Germany/Finland). DPA concluded via account dashboard.
- **Cloudflare**: Update existing mention to note `app.soleur.ai` in addition to docs site.

**5.2 Add Section 3.7 (Web Platform Service Delivery)**

Add lawful basis for web platform processing:

- **Account creation and management**: contract performance (Article 6(1)(b)) -- processing is necessary to provide the web platform service the user signed up for.
- **Payment processing**: contract performance (Article 6(1)(b)) -- processing is necessary to fulfill the subscription agreement. Card data handled exclusively by Stripe.
- Balancing test not required for contract performance basis.

**5.3 Update Section 4.2 (Data Categories)**

Add web platform data categories to the third-party processing table:

| Category | Third Party | Purpose |
|---|---|---|
| Email address, hashed password, auth tokens, session data | Supabase (via web platform) | Account management and authentication |
| Customer email, subscription metadata | Stripe (via web platform Checkout) | Payment processing (card data handled by Stripe, never reaches Jikigai) |
| User workspaces, encrypted API keys | Hetzner (via web platform hosting) | Infrastructure hosting for workspace environments |
| IP addresses, request headers | Cloudflare (via `app.soleur.ai` proxy) | CDN/proxy and DDoS protection |

**5.4 Update Section 6 (International Transfers)**

Add:

- **Supabase**: US-based (AWS). Transfer via SCCs (Module 2, Controller to Processor). [Note EU region if configured.]
- **Stripe**: US-based (Stripe, LLC). Transfer via EU-US DPF (adequacy decision) and SCCs (EEA Module 2) as supplementary safeguard.
- **Hetzner**: EU-based (Germany, datacenter in Helsinki, Finland). No international transfer.

**5.5 Update Section 10 (Article 30 Register)**

Add processing activities 7-9 to the register:

7. **Web platform account management** (app.soleur.ai via Supabase) -- email addresses, hashed passwords, auth tokens, session data. Legal basis: contract performance (Article 6(1)(b)). Retention: while account active; deleted on account deletion. Supabase (US-based, SCCs).
8. **Web platform payment processing** (app.soleur.ai via Stripe Checkout) -- customer email, subscription metadata. Card data processed exclusively by Stripe (PCI SAQ-A). Legal basis: contract performance (Article 6(1)(b)). Retention: subscription records per French tax law (10 years). Stripe (US-based, DPF + SCCs).
9. **Web platform infrastructure hosting** (app.soleur.ai via Hetzner CX33, Helsinki) -- user workspaces, encrypted API keys, Docker containers. Legal basis: contract performance (Article 6(1)(b)). Retention: while account active. Hetzner (EU-based, no international transfer).

**5.6 Evaluate DPIA Requirement (Section 9)**

Section 9 currently states DPIA is not required. Reassess:
- The web platform processes user PII at scale (email, auth tokens, encrypted API keys)
- Payment processing involves financial data
- However: no special categories (Art. 9), no systematic monitoring, no automated decision-making
- **Conclusion**: DPIA likely still not required under Art. 35(3) criteria, but update Section 9 to acknowledge the web platform and explain why the assessment hasn't changed (new processing but below high-risk threshold). Document the analysis.

### Research Insights: GDPR Policy

**File Count**: This phase touches 2 files (same GDPR policy in 2 locations), each needing updates to Sections 2.2, 3, 4.2, 6, 9, and 10. That's 12 section edits across 2 files = high cross-reference risk.

**Institutional Learnings Applied:**
- `split-legal-basis-cross-section-consistency`: Every new processing activity must appear in: lawful basis (Section 3), data categories (Section 4), international transfers (Section 6), and Article 30 register (Section 10). Missing any one creates an inconsistency.
- `stripe-atlas-legal-benchmark-mismatch`: Do not over-commit to obligations. Jikigai is a pre-revenue SaaS -- DPIA is not required, and adding one creates ongoing maintenance obligations. Document the analysis, don't perform an unnecessary DPIA.

### Phase 6: Process Improvement -- Vendor Checklist Gate

**6.1 Add vendor checklist to constitution (`knowledge-base/project/constitution.md`)**

Replace the existing self-check rule (line 109 area) with a formal checklist. The current rule says "engineering workflows have no built-in vendor gate, so the agent must self-check" -- after this PR, the gate exists:

```markdown
### New Vendor Checklist

When a PR adds external services (terraform resources, account signups, API key generation, new SaaS dependencies), the following must be completed before merge:

- [ ] Expense ledger updated (`knowledge-base/operations/expenses.md`) with cost, tier, and upgrade triggers
- [ ] DPA verified -- either auto-accepted (Stripe) or manually signed (Hetzner console) -- with link to vendor DPA page
- [ ] Privacy policy updated with new processor in BOTH `docs/legal/` and `plugins/soleur/docs/pages/legal/`
- [ ] Data protection disclosure updated with new processor in Section 4.2 table
- [ ] GDPR policy updated: third-party services (2.2), lawful basis (3.x), data categories (4.2), transfers (6), Article 30 register (10)
- [ ] International transfer mechanism documented (SCCs, DPF adequacy decision, or EU-only)
- [ ] Grep verification run for contradicting blanket statements across all legal docs
```

Also fix the stale path reference: `knowledge-base/ops/expenses.md` should be `knowledge-base/operations/expenses.md`.

**6.2 Add vendor checklist to PR template**

Update `.github/PULL_REQUEST_TEMPLATE.md` to add a conditional vendor section:

```markdown
## Vendor Compliance (if adding external services)

<!-- Delete this section if your PR does not add new vendors, infrastructure, or SaaS dependencies -->

- [ ] Expense ledger updated
- [ ] DPA verified and signed
- [ ] Privacy policy updated (both locations)
- [ ] Data protection disclosure updated
- [ ] GDPR policy updated (all 5 sections)
- [ ] International transfer mechanism documented
```

### Research Insights: Vendor Gate

**Institutional Learnings Applied:**
- `engineering-workflow-blind-spots`: This learning documents exactly the problem this phase solves -- "Stood up 4 new services without updating the expense ledger or triggering legal/DPA review." The constitution rule added then was prose-based (weakest enforcement). This phase upgrades it to a concrete checklist in both the constitution AND the PR template.
- `plan-review-scope-reduction-and-hook-enforced-annotations`: Prefer PR template over PreToolUse hook for this gate. Hooks fire on every tool use and add latency. A PR template section is visible during review and can be deleted when not applicable.

## Acceptance Criteria

- [x] `knowledge-base/operations/expenses.md` has entries for all four active services (Hetzner CX33, Supabase, Stripe, Cloudflare update) with costs, tiers, and upgrade thresholds
- [ ] Hetzner DPA (AVV) explicitly concluded via account dashboard (requires founder action -- documented in DPA memo)
- [ ] Supabase DPA status verified (free-tier coverage -- requires founder dashboard check, documented in DPA memo)
- [x] Stripe DPA confirmed as automatic (part of Services Agreement)
- [ ] Cloudflare DPA applicability for free-tier verified (requires founder dashboard check, documented in DPA memo)
- [x] DPA verification memo written to `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md`
- [x] Privacy policy updated in both locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`) with web platform data collection
- [x] Section 4.1 scoped to plugin only -- no blanket "does not collect" contradictions
- [x] Data protection disclosure updated in both locations with web platform processors and Section 8 transition
- [x] GDPR policy updated in both locations: Sections 2.2, 3.7, 4.2, 6, 9, 10
- [x] Article 30 register has processing activities 7-9 (auth, payments, hosting)
- [x] Vendor checklist gate added to `knowledge-base/project/constitution.md`
- [x] Vendor checklist added to `.github/PULL_REQUEST_TEMPLATE.md`
- [x] Constitution stale path `knowledge-base/ops/expenses.md` fixed to `knowledge-base/operations/expenses.md`
- [x] All legal document "Last Updated" dates updated
- [x] Cross-references consistent across all documents (grep verified)
- [x] Resend excluded from scope, tracked as future item when integration code is written
- [x] T&C blanket statement contradictions filed as separate issue #736

## Test Scenarios

- Given a new developer reads the expense ledger, when they look up web platform costs, then they find Hetzner CX33, Supabase, and Stripe entries with accurate costs and upgrade triggers.
- Given a user visits the privacy policy, when they read Section 4, then Section 4.1 says "Data Collected by the Plugin: None" and Section 4.7 discloses web platform data collection -- no contradictions.
- Given a GDPR auditor reviews the Article 30 register (Section 10), when they check processing activities, then they find entries 7-9 for web platform services with contract performance (6(1)(b)) as the lawful basis.
- Given an engineer opens a PR that adds a Terraform resource, when the PR template renders, then the "Vendor Compliance" section is visible with the checklist.
- Given grep is run for "does not collect" across all legal docs, when it finds matches, then every match is correctly scoped to the plugin (not blanket).
- Given the DPD is reviewed, when Section 8 is checked, then each commitment (8.1(a)-(f)) is marked as fulfilled or in-progress with cross-references.

## Dependencies & Risks

**Dependencies:**

- Hetzner Cloud Console access to sign the DPA (AVV) -- may require founder action
- Supabase dashboard access to check DPA availability and project region
- Confirmation of whether CX22 (telegram-bridge) is still running -- check `apps/telegram-bridge/infra/` Terraform state

**Risks:**

- **Hetzner DPA not signed**: This is the most urgent risk. Without a signed DPA, Jikigai processes user data on Hetzner servers without a GDPR Article 28 compliant agreement. The web platform should not accept user registrations until this is resolved. **Mitigation**: Sign the DPA immediately via the Hetzner console.
- **Supabase free-tier DPA gap**: If the DPA is not available for free-tier projects, upgrade to Pro ($25/mo) or accept documented risk. **Mitigation**: Check dashboard first; document finding either way.
- **Cloudflare free-tier DPA ambiguity**: The DPA references a "Main Agreement" which may not formally exist for free-tier. **Mitigation**: The Self-Serve Subscription Agreement likely constitutes the Main Agreement -- document this analysis.
- **Legal document inflation**: Adding web platform services creates a large diff across 8+ files. **Mitigation**: Commit in logical chunks (ops first, then DPA memo, then legal docs, then process gate) rather than one monolithic commit.
- **Blanket statement contradictions**: The privacy policy has multiple "does not collect" statements that become false with the web platform. **Mitigation**: Run grep verification (patterns in Phase 3) AFTER all edits, not during.

## References

### Internal References

- Issue: #670
- PR that provisioned services: #637
- Expense ledger: `knowledge-base/operations/expenses.md`
- Privacy policy (source): `docs/legal/privacy-policy.md`
- Privacy policy (docs site): `plugins/soleur/docs/pages/legal/privacy-policy.md`
- Data protection disclosure (docs site): `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- Data protection disclosure (source): `docs/legal/data-processing-agreement.md` (verify exists and sync status)
- GDPR policy (source): `docs/legal/gdpr-policy.md`
- GDPR policy (docs site): `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- Constitution vendor rule: `knowledge-base/project/constitution.md:109`
- PR template: `.github/PULL_REQUEST_TEMPLATE.md`
- Stripe integration: `apps/web-platform/lib/stripe.ts`, `apps/web-platform/app/api/checkout/route.ts`
- Supabase config: `apps/web-platform/lib/supabase/server.ts`, `apps/web-platform/lib/supabase/client.ts`
- Terraform infra: `apps/web-platform/infra/` (main.tf, server.tf, dns.tf, variables.tf)

### Learnings Applied

- `2026-02-21-github-dpa-free-plan-scope-limitation.md` -- DPA tier-gating pattern
- `2026-02-21-gdpr-article-30-compliance-audit-pattern.md` -- Dual-location legal docs
- `2026-03-10-first-pii-collection-legal-update-pattern.md` -- Grep verification for contradictions
- `2026-03-18-dpd-processor-table-dual-file-sync.md` -- DPD dual-file sync gap
- `2026-03-18-dpd-sub-processor-contradiction-fix.md` -- Processor vs sub-processor terminology
- `2026-03-18-split-legal-basis-cross-section-consistency.md` -- Cross-section propagation
- `2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md` -- Verify transfer mechanism per vendor
- `2026-02-25-stripe-atlas-legal-benchmark-mismatch.md` -- Don't over-commit obligations
- `2026-03-17-engineering-workflow-blind-spots.md` -- Root cause of this issue
- `2026-02-20-dogfood-legal-agents-cross-document-consistency.md` -- Post-edit audit cycle

### External References

- Hetzner ToS (Section 6.2 DPA clause): https://www.hetzner.com/legal/terms-and-conditions/
- Supabase DPA: https://supabase.com/legal/dpa
- Stripe DPA: https://stripe.com/legal/dpa
- Stripe PCI guidance: https://stripe.com/docs/security/guide
- Cloudflare DPA: https://www.cloudflare.com/cloudflare-customer-dpa/
- Resend DPA (future): https://resend.com/legal/dpa
- Resend sub-processors (future): https://resend.com/legal/subprocessors
