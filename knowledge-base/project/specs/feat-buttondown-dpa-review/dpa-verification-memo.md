# Buttondown DPA Verification Memo

**Date:** 2026-03-11 (re-verified 2026-03-17, 2026-03-19)
**Author:** CLO Assessment (AI-assisted — requires legal review)
**Controller:** Jikigai (France)
**Processor:** Buttondown, LLC (United States)
**Processing Activity:** Newsletter subscription management for soleur.ai
**Personal Data:** Email addresses, IP addresses, referrer metadata, subscription timestamps
**Data Subjects:** EU-based newsletter subscribers
**Related Issue:** #501 (Newsletter)

---

## 1. Background

Jikigai operates soleur.ai and uses Buttondown (free tier) for newsletter email capture. Signup forms went live on 2026-03-10. On 2026-03-10, Jean emailed Buttondown requesting a DPA with SCCs. Buttondown responded on 2026-03-11 pointing to three standard documents.

On 2026-03-16, Buttondown published a [legal docs refresh](https://buttondown.com/blog/2026-03-16-legal-docs-refresh) addressing most gaps identified in the original review. The blog credits "customer feedback during their own GDPR compliance review." This memo has been re-verified against the updated documents.

## 2. Documents Reviewed

| Document | URL | Last Updated |
|----------|-----|-------------|
| GDPR & EU Compliance | https://buttondown.com/legal/gdpr-eu-compliance | March 16, 2026 |
| Data Processing Agreement | https://buttondown.com/legal/data-processing-agreement | March 16, 2026 |
| Privacy Policy | https://buttondown.com/legal/privacy | March 16, 2026 |
| Sub-Processor List | https://buttondown.com/legal/subprocessors | March 16, 2026 |
| Cookie Policy | https://buttondown.com/legal/cookies | March 16, 2026 (new) |

## 3. Article 28(3) Compliance Matrix

### Original Assessment (2026-03-11)

| GDPR Art. 28 Requirement | DPA Coverage | March 11 Assessment |
|--------------------------|-------------|---------------------|
| Processing on documented instructions (a) | Section 3.1 | ADEQUATE |
| Confidentiality obligations (b) | Section 3.2 | ADEQUATE |
| Technical/organizational measures (c) | Section 4 | PARTIAL — generic measures, no certifications or standards cited |
| Sub-processor provisions (d) | Section 5 | PARTIAL — general authorization, no list, no change notification URL |
| Data subject rights assistance (e) | Section 6 | ADEQUATE |
| Deletion/return after termination (f) | Section 11.2 | ADEQUATE — but no backup deletion timeline |
| Audit rights (h) | Section 9 | ADEQUATE — reasonable notice required |
| Breach notification | Section 7 | PARTIAL — "without undue delay," no 72-hour commitment |
| International transfers (Chapter V) | Section 8 | INADEQUATE — acknowledges obligation but specifies no mechanism |
| DPA Annex (processing details) | Not present | INADEQUATE — mandatory under Art. 28(3) |

### Re-Assessment (2026-03-17)

| GDPR Art. 28 Requirement | DPA Coverage | March 17 Assessment | Change |
|--------------------------|-------------|---------------------|--------|
| Processing on documented instructions (a) | Section 3.1 | ADEQUATE | No change |
| Confidentiality obligations (b) | Section 3.2 | ADEQUATE | No change |
| Technical/organizational measures (c) | Section 4 | PARTIAL — generic measures, no certifications or standards cited | No change |
| Sub-processor provisions (d) | Section 5 + /legal/subprocessors | ADEQUATE — list now at stable URL, referenced in DPA | **Upgraded** |
| Data subject rights assistance (e) | Section 6 | ADEQUATE | No change |
| Deletion/return after termination (f) | Section 11.2 | ADEQUATE — but no backup deletion timeline | No change |
| Audit rights (h) | Section 9 | ADEQUATE — reasonable notice required | No change |
| Breach notification | Section 7 | PARTIAL — "without undue delay," no 72-hour commitment | No change |
| International transfers (Chapter V) | Section 8 + Annex B | ADEQUATE — SCCs (Decision 2021/914, Module 2) incorporated by reference with clause-by-clause completion | **Resolved (March 19 re-verification)** |
| DPA Annex (processing details) | Annex 1 | ADEQUATE — subject matter, duration, data types, data subjects | **Upgraded from INADEQUATE** |
| Instruction-infringement notification | Not present | MISSING — Art. 28(3) second subparagraph requires processor to notify controller if instruction infringes GDPR | **New finding** |
| GDPR precedence over governing law | Section 12 | ADEQUATE — EU/UK/Swiss data protection law takes precedence | **New (resolved Gap 3)** |

## 4. Critical Gaps

### Gap 1: EU-US Transfer Mechanism — RESOLVED

~~The DPA acknowledges international transfers must comply with GDPR Chapter V but does not incorporate or reference any mechanism.~~

**March 17 update:** Section 8 referenced SCCs generically ("EU Standard Contractual Clauses where applicable") but lacked specifics.

**March 19 update (Steph's response + DPA re-verification):** Section 8 now fully incorporates SCCs:

- **Section 8.2:** Transfers governed by "Standard Contractual Clauses issued by the European Commission pursuant to Implementing Decision (EU) 2021/914," **Module 2 (Controller to Processor)**. SCCs are "incorporated by reference into this DPA."
- **Section 8.3:** Clause-by-clause SCC completion:
  - Clause 7 (Docking clause): shall apply
  - Clause 9(a) (Sub-processors): Option 2 (General written authorization)
  - Clause 11 (Redress): shall not apply
  - Clause 17 (Governing law): Option 1
  - Clause 18(b) (Forum): EU Member State courts
- **Section 8.4:** SCC annexes completed in **Annex B** (party details, transfer description, supervisory authority, technical/organizational measures, sub-processor list)
- **Section 8.5:** SCCs prevail over any conflicting DPA provision
- **Section 8.6:** UK Addendum and Swiss modifications referenced

**Assessment:** This is proper SCCs incorporation by reference — the standard approach accepted by CNIL and other DPAs. The DPA cites the correct Decision (2021/914), specifies the correct Module (2: Controller-to-Processor), and completes clause-by-clause options as required. Annex B provides the required transfer-specific details.

**Our exposure: RESOLVED.** Jikigai's Privacy Policy Section 5.3 claim that "International data transfers are covered by Standard Contractual Clauses (SCCs)" is now substantiated.

### Gap 2: Missing DPA Annex — RESOLVED

~~Article 28(3) requires the DPA to specify processing details. None were documented.~~

**March 17 update:** Annex 1 now covers subject matter (newsletter delivery, subscription management, engagement analytics), duration (length of service agreement), data types (email addresses, IP addresses, referrer metadata, subscription timestamps, billing information for paid tiers), and data subject categories (newsletter subscribers including EU residents, newsletter authors).

### Gap 3: US Governing Law — RESOLVED

~~DPA Section 12 specifies US governing law with no GDPR supremacy clause.~~

**March 17 update:** Section 12 now includes: "To the extent that the GDPR or other applicable data protection laws of the European Economic Area, the United Kingdom, or Switzerland impose obligations...those obligations shall take precedence over any conflicting provision."

### Gap 4: Privacy Policy Contradictions — RESOLVED

~~2019 privacy policy mentions third-party advertising, contradicting GDPR compliance page.~~

**March 17 update:** Privacy policy updated March 16, 2026. Advertising references removed. Contact email changed to support@buttondown.com. Explicit statement: "Buttondown doesn't do anything weird with your data."

### Gap 5: Plan Tier Scope — RESOLVED

~~Per our GitHub DPA precedent (learnings: `2026-02-21-github-dpa-free-plan-scope-limitation.md`), DPAs sometimes only cover paid plans. Buttondown's updated DPA still does not specify tier applicability.~~

**March 19 update (Steph's email):** Confirmed that the DPA applies to **all plans — both free and paid**. Steph noted that paid plans expose additional data via Stripe (billing contact name, billing address), documented at [buttondown.com/legal/gdpr-eu-compliance](https://buttondown.com/legal/gdpr-eu-compliance).

**Data by tier (from GDPR compliance page):**
- Free authors: email address, subscriber emails, newsletter content
- Paid authors: + billing contact name, billing address (via Stripe)
- Free readers/subscribers: email address, IP address, referrer metadata
- Paid subscribers: + billing contact name, billing address (via Stripe)

This is the opposite of the GitHub precedent — Buttondown covers all tiers, while GitHub limits DPA to paid plans only.

### Gap 6: Instruction-Infringement Notification — NEW

Art. 28(3) second subparagraph requires the processor to "immediately inform the controller if, in its opinion, an instruction infringes this Regulation or other Union or Member State data protection provisions." The DPA contains no such clause. **Severity: LOW** — unlikely to be a blocking issue for CNIL, but a compliance gap worth flagging.

## 5. Sub-processor Inventory

### March 11 (from GDPR compliance page, informal)

| Sub-processor | Purpose | Location |
|---------------|---------|----------|
| Mailgun | Email delivery | US |
| Postmark | Email delivery | US |
| Stripe | Payment processing | US |

### March 17 (from dedicated sub-processor page at /legal/subprocessors, referenced in DPA Section 5)

| Sub-processor | Purpose |
|---------------|---------|
| Amazon Web Services (AWS) | Cloud infrastructure and hosting services |
| Betterstack | Error monitoring and performance tracking |
| Cloudflare | Content delivery network and security services |
| Google Workspace | Business productivity and collaboration tools |
| Heroku | Application hosting and deployment platform |
| Mailgun | Email delivery and transactional email services |
| Plain | Customer support and help desk software |
| Postmark | Email delivery and transactional email services |
| Seline | Privacy-focused website analytics |
| Sentry | Error monitoring and performance tracking |
| Slack | Internal communication and support tools |
| Stripe | Payment processing and billing |

**Note:** Individual sub-processor locations not specified on the page. Buttondown is based in Richmond, Virginia, USA. All sub-processors bound by contractual obligations requiring appropriate technical/organizational security measures.

## 6. Data Categories Comparison

| Category | Our Docs Claim | Buttondown Actually Collects |
|----------|---------------|------------------------------|
| Email address | Yes | Yes |
| IP address | No | Yes (per GDPR compliance page) |
| Referrer metadata | No | Yes (per GDPR compliance page) |
| Subscription timestamp | Yes (implied) | Not explicitly stated |

**Action needed:** Our Privacy Policy (Section 4.6) and GDPR Policy (Section 4.2) list only email addresses. IP addresses and referrer metadata should be added once confirmed.

## 7. Recommended Actions

### Completed (from March 11 requests — addressed by Buttondown March 16)

| # | Action | Status |
|---|--------|--------|
| ~~2~~ | ~~Request DPA Annex template~~ | DONE — Annex 1 added |
| ~~3~~ | ~~Request formal sub-processor list~~ | DONE — /legal/subprocessors created |
| ~~4~~ | ~~Request GDPR supremacy clause~~ | DONE — Section 12 updated |
| ~~5~~ | ~~Clarify advertising contradiction~~ | DONE — Privacy policy updated |

### Immediate (now — March 19)

| # | Action | Owner | Status |
|---|--------|-------|--------|
| 1 | ~~Send follow-up email requesting SCCs execution + free-tier confirmation~~ | Jean | DONE (sent; Steph replied March 19) |
| 2 | ~~Update our legal docs with confirmed facts: sub-processor list, data types, contact email~~ | Legal agents | DONE (March 17 commit) |
| 3 | Update SCCs/transfer mechanism claims — now substantiated by DPA Section 8 (Decision 2021/914, Module 2) | Legal agents | IN PROGRESS |
| 4 | Update legal docs with free-tier DPA confirmation | Legal agents | IN PROGRESS |
| 5 | Run legal-compliance-auditor for cross-document consistency | Legal agents | PENDING |
| 6 | Sign DPA (all blocking gaps resolved) | Jean | PENDING |
| 7 | Close #501 | — | PENDING (after DPA signed) |
| 8 | Update Article 30 private register | Jean | PENDING |

## 8a. Original Draft Reply Email (March 11 — SUPERSEDED)

~~See git history for the original 5-point email requesting DPA Annex, sub-processor list, GDPR supremacy clause, advertising clarification, and SCCs.~~

**Status:** Superseded by Section 8b. Buttondown addressed items 2-5 in their March 16 legal docs refresh before this email was sent.

## 8b. Follow-Up Email (March 17)

**Subject:** Re: Buttondown GDPR/DPA — Great updates, two remaining items

Hi Steph,

I saw the legal docs refresh you published on March 16 — really impressive work. The DPA Annex, sub-processor list at a stable URL, GDPR precedence clause, and updated privacy policy address exactly the points we'd been reviewing. Thank you for taking the feedback seriously and acting on it so quickly.

We've re-reviewed everything and are nearly ready to formalize the DPA. Two items remain:

**1. Standard Contractual Clauses (SCCs)**

The updated DPA Section 8 references "EU Standard Contractual Clauses where applicable," which is the right direction. However, for CNIL (our French supervisory authority), a generic reference to SCCs typically isn't sufficient — we'd need the SCCs formally incorporated or executed. Specifically:

- The **EU Commission Standard Contractual Clauses** (Implementing Decision 2021/914, Module 2: Controller-to-Processor) either attached as a DPA annex or executed as a standalone agreement
- Alternatively, confirmation that Buttondown is certified under the **EU-US Data Privacy Framework (DPF)**, which would provide an adequacy-based transfer mechanism

Could you let us know which approach Buttondown supports? If SCCs, we're happy to help populate the controller-specific annexes to make it straightforward.

**2. Free Tier DPA Applicability**

We're currently on Buttondown's free tier. The DPA and Annex 1 don't explicitly state which plan tiers are covered. We've seen other platforms (e.g., GitHub) limit DPA applicability to paid plans. Could you confirm that the DPA applies to free-tier users as well?

Everything else looks solid. Once these two items are resolved, we're ready to sign.

Thanks again — really appreciate how responsive you've been on this.

Best regards,
Jean
Jikigai — soleur.ai

## 8c. Buttondown Response (March 19)

**From:** Steph (Buttondown support)
**Date:** 2026-03-19
**Subject:** Re: Buttondown GDPR/DPA — Great updates, two remaining items

> **#1 (SCCs):** "We've updated our DPA to reflect this information. This is under Section 8, with more details in Annex B." — [buttondown.com/legal/data-processing-agreement](https://buttondown.com/legal/data-processing-agreement)
>
> **#2 (Free tier):** "Our DPA is applicable to all plans—both free and paid." Notes that paid plans expose additional Stripe data (billing contact name, billing address). Details at [buttondown.com/legal/gdpr-eu-compliance](https://buttondown.com/legal/gdpr-eu-compliance).

**Verification (March 19):** DPA Section 8 confirmed to incorporate SCCs (Implementing Decision 2021/914, Module 2: Controller-to-Processor) by reference with clause-by-clause completion. Annex B completes the SCC annexes. See Gap 1 update in Section 4.

**Outcome:** Both blocking gaps resolved. DPA is ready to sign.

## 9. Precedent Reference

This review follows the pattern established by the GitHub DPA verification (`knowledge-base/project/specs/archive/2026-02-22-165750-feat-github-dpa-verify/dpa-verification-memo.md`):
- Verify DPA scope for actual plan tier
- Document findings in structured memo
- Update legal docs to reflect reality, not aspirations

## 10. Disclaimer

This memo is AI-assisted draft analysis, not legal advice. All findings and recommendations should be reviewed by a qualified legal professional before acting on them.
