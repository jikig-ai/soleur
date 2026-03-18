---
title: "chore: record new services from web platform deployment"
type: chore
date: 2026-03-18
issue: "#670"
priority: p1-high
---

# chore: Record New Services from Web Platform Deployment

## Overview

PR #637 (feat/web-platform-ux) provisioned five new external services for the Soleur web platform (app.soleur.ai) without updating the expense ledger, verifying DPA coverage, or triggering legal review. This issue tracks the ops and legal follow-up required to bring the project back into compliance.

The web platform represents a fundamental architectural shift: Jikigai now operates cloud infrastructure that processes user PII (email addresses, auth tokens, API keys, payment data). The existing legal documents are predicated on Soleur being a "local-only plugin" with no Jikigai-operated cloud services. The DPD (Section 8) anticipated this transition and committed to specific disclosure updates before cloud processing begins.

## Problem Statement

Five services were deployed without the corresponding ops and legal hygiene:

| Service | Type | Est. Cost | Data Processed | DPA Status |
|---------|------|-----------|----------------|------------|
| Hetzner CX33 (Helsinki, `hel1`) | Server + volume hosting | ~EUR 15.37/mo (CX33) + EUR 0.88/mo (20GB volume) | User workspaces, Docker containers, API keys (encrypted) | Needs verification -- existing CX22 entry only |
| Supabase (free tier) | Auth + PostgreSQL | $0 (free tier, 500MB DB, 50K MAU) | User PII: email, hashed passwords, auth tokens, session data | Needs verification |
| Stripe (test mode) | Payment processing | $0 test + 2.9%+30c per txn live | Payment card data (PCI scope), customer email/name, billing address | Needs verification -- PCI DSS scope |
| Cloudflare (existing zone) | DNS + CDN/proxy for `app.soleur.ai` | $0 (free tier) | IP addresses, request headers via CDN proxy | Existing zone but new subdomain/purpose needs ledger update |
| Resend (free tier) | Transactional email API | $0 (free tier, 3K emails/mo) | Recipient email addresses, email content | Needs verification |

## Proposed Solution

### Phase 1: Ops -- Expense Ledger Updates

Update `knowledge-base/operations/expenses.md` (`knowledge-base/ops/expenses.md` path referenced in constitution may be stale -- verify actual path):

**1.1 New recurring entries:**

- **Hetzner CX33**: ~EUR 15.37/mo, 4 vCPU, 8 GB RAM, 160 GB SSD, `hel1` (Helsinki). Replace or supplement existing CX22 entry (EUR 5.83/mo) -- determine if CX22 is decommissioned or both run in parallel.
- **Hetzner Volume**: ~EUR 0.88/mo, 20 GB, `hel1`. Persistent storage for `/workspaces`.
- **Supabase**: $0 (free tier). Note upgrade thresholds: 500MB DB, 50K MAU, 1GB file storage, 2GB bandwidth. Estimated Pro tier cost: $25/mo.
- **Stripe**: $0 (test mode). Note per-transaction costs when live: 2.9% + $0.30 per successful charge (EU cards lower). Monthly minimum: none.
- **Resend**: $0 (free tier). Note upgrade threshold: 3,000 emails/mo, 100 emails/day. Pro tier: $20/mo for 50K emails.

**1.2 Update existing entries:**

- **Cloudflare**: Add note that `app.soleur.ai` subdomain now uses Cloudflare proxy (A record pointing to Hetzner CX33). No additional cost on free tier.

### Phase 2: Legal -- DPA Verification

For each vendor, verify that a Data Processing Agreement (or equivalent) covers the data Jikigai processes through the service. This is a GDPR Article 28 obligation for any processor handling personal data on Jikigai's behalf.

**Key learning from prior work**: GitHub's formal DPA only covers paid plans (see `knowledge-base/project/learnings/2026-02-21-github-dpa-free-plan-scope-limitation.md`). Similar tier-gating may apply to Supabase and Stripe free tiers.

**2.1 Hetzner DPA:**

- Hetzner has a [Data Processing Agreement](https://www.hetzner.com/legal/privacy-policy/) available for all customers.
- Verify: Does it cover the Helsinki datacenter (`hel1`)? Is it automatically accepted via ToS, or does it require explicit signing?
- Hetzner is EU-based (Germany), so no international transfer concerns.
- Data processed: server compute, volume storage (user workspaces, Docker containers, encrypted API keys).

**2.2 Supabase DPA:**

- Supabase provides a [DPA](https://supabase.com/legal/dpa) but verify free-tier coverage.
- Supabase uses AWS `us-east-1` by default -- international transfer from EU requires SCCs or adequacy decision.
- Data processed: user email addresses, hashed passwords, auth tokens, session metadata.
- Check: Can the Supabase project be configured to use an EU region? If not, document transfer mechanism.

**2.3 Stripe DPA:**

- Stripe provides a [DPA](https://stripe.com/legal/dpa) that applies to all accounts.
- Stripe is PCI DSS Level 1 certified -- verify that Jikigai's integration (likely Stripe Checkout or Elements) keeps Jikigai out of PCI scope (SAQ-A or SAQ-A-EP).
- Data processed: customer payment data, email, name, billing address.
- Stripe processes data globally but offers EU data residency options -- verify configuration.

**2.4 Cloudflare DPA:**

- Cloudflare provides a [DPA](https://www.cloudflare.com/cloudflare-customer-dpa/) for all customers.
- Already in use for DNS/CDN on `soleur.ai` -- the `app.soleur.ai` subdomain extends existing processing, not a new relationship.
- Data processed: IP addresses, request headers, TLS termination.
- Cloudflare is US-based but maintains EU presence and SCCs.

**2.5 Resend DPA:**

- Resend provides a [DPA](https://resend.com/legal/dpa) -- verify free-tier coverage.
- Data processed: recipient email addresses, email content (transactional emails like password resets, signup confirmations).
- Check: Where is Resend's infrastructure hosted? Transfer mechanism?

### Phase 3: Legal -- Privacy Policy Updates

Update the Privacy Policy in BOTH locations (per learning `2026-02-21-gdpr-article-30-compliance-audit-pattern.md`):

- `docs/legal/privacy-policy.md` (source markdown)
- `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy template)

**3.1 New Section: Web Platform Data Collection**

The privacy policy currently describes Soleur as a local-only plugin. The web platform introduces server-side data processing. A new section (e.g., Section 4.7 or a restructured Section 4) must disclose:

- **What data is collected**: email, auth tokens, session data, payment information (via Stripe), transactional email addresses (via Resend).
- **Purpose**: providing the web platform service (auth, payments, workspace provisioning, transactional notifications).
- **Legal basis**: contract performance (Article 6(1)(b)) for service delivery; consent where applicable (payment processing).
- **Retention**: account data retained while account active; payment records per tax law requirements.

**3.2 New Third-Party Service Sections**

Add new subsections to Section 5 for:

- Supabase (auth + database)
- Stripe (payments)
- Hetzner (hosting)
- Resend (transactional email)
- Cloudflare (already partially covered -- update to note app.soleur.ai)

**3.3 Update International Data Transfers (Section 10)**

Add transfer disclosures for:

- Supabase (US, AWS `us-east-1` -- SCCs)
- Stripe (global, EU data residency option)
- Resend (verify hosting location)

### Phase 4: Legal -- Data Protection Disclosure Updates

Update the DPD in:

- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`

**4.1 Trigger Section 8 ("Future Cloud Features")**

The DPD Section 8.1 committed to updating the DPD with full Article 28 terms when cloud features are introduced. The web platform IS that transition. Update:

- Section 2.1 ("Soleur Is Not a Data Processor"): This is now partially incorrect. The plugin remains local-only, but the web platform IS Jikigai-operated infrastructure. The DPD needs to distinguish between plugin (local) and web platform (cloud).
- Section 2.3 ("Limited Processing by Soleur"): Add web platform processing activities.
- Section 4.2 ("Docs Site Processors"): Add web platform processors (Supabase, Stripe, Hetzner, Resend).

**4.2 New Processing Activities for Article 30 Register**

The GDPR policy and internal register need new processing activities:

7. **Web platform authentication** (app.soleur.ai via Supabase) -- email addresses, auth tokens, session data
8. **Web platform payment processing** (app.soleur.ai via Stripe) -- payment card data, customer email/name, billing address
9. **Web platform hosting** (app.soleur.ai via Hetzner) -- user workspaces, encrypted API keys
10. **Web platform transactional email** (app.soleur.ai via Resend) -- recipient email addresses, email content

### Phase 5: Legal -- GDPR Policy Updates

Update the GDPR policy in BOTH locations:

- `docs/legal/gdpr-policy.md`
- `plugins/soleur/docs/pages/legal/gdpr-policy.md`

**5.1 Update Section 2.2 (Third-Party Services)**

Add Supabase, Stripe, Hetzner, Resend to the third-party services section with their controller/processor roles.

**5.2 Update Section 3 (Lawful Basis)**

Add lawful basis for web platform processing:

- Account creation: contract performance (Article 6(1)(b))
- Payment processing: contract performance (Article 6(1)(b))
- Transactional email: legitimate interest (Article 6(1)(f)) -- service operation

**5.3 Update Section 4.2 (Data Categories)**

Add web platform data categories to the third-party processing table.

**5.4 Update Section 6 (International Transfers)**

Add Supabase, Stripe, Resend transfer disclosures.

**5.5 Update Section 10 (Article 30 Register)**

Add processing activities 7-10 to the register.

### Phase 6: Process Improvement -- Vendor Checklist Gate

**6.1 Add vendor checklist to constitution**

Strengthen the existing vendor-management rule in `knowledge-base/project/constitution.md` (line 109) from a self-check reminder to a formal gate with concrete steps:

```
### New Vendor Checklist (required before merging PRs that add external services)

- [ ] Expense ledger updated (`knowledge-base/operations/expenses.md`)
- [ ] DPA verified and documented (link to vendor DPA page)
- [ ] Privacy policy updated with new processor (both `docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- [ ] Data protection disclosure updated with new sub-processor
- [ ] GDPR policy updated (third-party services, lawful basis, Article 30 register)
- [ ] International transfer mechanism documented (SCCs, adequacy decision, or EU-only)
```

**6.2 Add PreToolUse or PR template gate**

Consider adding the checklist to the PR template (`.github/PULL_REQUEST_TEMPLATE.md`) as a conditional section that appears when infra files are modified. This is less aggressive than a PreToolUse hook but ensures visibility.

## Acceptance Criteria

- [ ] `knowledge-base/operations/expenses.md` has entries for all five services with costs, tiers, and upgrade thresholds
- [ ] DPA verification documented for each vendor (Hetzner, Supabase, Stripe, Cloudflare, Resend) -- either confirmed coverage or gap identified with remediation plan
- [ ] Privacy policy updated in both locations with web platform data collection disclosures
- [ ] Data protection disclosure updated with web platform processors and Section 8 transition language
- [ ] GDPR policy updated in both locations with new processing activities, lawful bases, and Article 30 register entries
- [ ] Vendor checklist gate added to constitution and/or PR template
- [ ] All legal document "Last Updated" dates reflect the change
- [ ] Cross-references between documents are consistent (privacy policy <-> DPD <-> GDPR policy)

## Test Scenarios

- Given a new developer reads the expense ledger, when they look up Hetzner costs, then they find both CX22 and CX33 entries (or only CX33 if CX22 was decommissioned) with accurate monthly costs.
- Given a user visits the privacy policy, when they read about data collection, then they find clear disclosures about the web platform's use of Supabase, Stripe, Hetzner, and Resend.
- Given a GDPR auditor reviews the Article 30 register, when they check processing activities, then they find entries for all web platform services with lawful bases and retention periods.
- Given an engineer opens a PR that adds a `terraform apply` or new API key, when the PR template renders, then the vendor checklist section is visible.
- Given a DPA is not available for a vendor's free tier, when the implementation team encounters this, then the plan includes a remediation path (upgrade tier, alternative vendor, or documented risk acceptance).

## Dependencies & Risks

**Dependencies:**

- Accurate Hetzner CX33 pricing from Hetzner's current price list (EUR ~15.37/mo as of March 2026 for `hel1`)
- Vendor DPA availability for free tiers -- this is the highest-risk unknown (see GitHub DPA learning)
- Determination of whether CX22 is decommissioned or running in parallel with CX33

**Risks:**

- **Supabase free-tier DPA gap**: If Supabase's DPA only covers paid plans, Jikigai may need to upgrade or document the risk. Supabase stores user PII (email, auth tokens) making this the highest-priority DPA to verify.
- **PCI scope creep**: If Stripe integration uses direct card handling instead of Stripe Elements/Checkout, Jikigai enters PCI DSS scope, requiring SAQ-D instead of SAQ-A. Verify the integration pattern.
- **Legal document inflation**: Adding five new services to the privacy policy/DPD/GDPR policy in one go creates a large diff. Consider whether the web platform warrants its own privacy policy addendum vs. inline expansion.
- **Resend data residency**: Resend is newer and may not have EU data residency options. If all email content transits through US infrastructure, this needs SCCs documentation.

## References

### Internal References

- Issue: #670
- PR that provisioned services: #637
- Expense ledger: `knowledge-base/operations/expenses.md`
- Privacy policy (source): `docs/legal/privacy-policy.md`
- Privacy policy (docs site): `plugins/soleur/docs/pages/legal/privacy-policy.md`
- Data protection disclosure: `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- GDPR policy (source): `docs/legal/gdpr-policy.md`
- GDPR policy (docs site): `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- Constitution vendor rule: `knowledge-base/project/constitution.md:109`
- DPA scope learning: `knowledge-base/project/learnings/2026-02-21-github-dpa-free-plan-scope-limitation.md`
- Dual-location learning: `knowledge-base/project/learnings/2026-02-21-gdpr-article-30-compliance-audit-pattern.md`
- Terraform infra: `apps/web-platform/infra/` (main.tf, server.tf, dns.tf, variables.tf)

### External References

- Hetzner DPA: https://www.hetzner.com/legal/privacy-policy/
- Hetzner pricing: https://www.hetzner.com/cloud/
- Supabase DPA: https://supabase.com/legal/dpa
- Supabase pricing: https://supabase.com/pricing
- Stripe DPA: https://stripe.com/legal/dpa
- Stripe PCI guidance: https://stripe.com/docs/security/guide
- Cloudflare DPA: https://www.cloudflare.com/cloudflare-customer-dpa/
- Resend DPA: https://resend.com/legal/dpa
- Resend pricing: https://resend.com/pricing
