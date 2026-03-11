# Buttondown DPA Verification Memo

**Date:** 2026-03-11
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

## 2. Documents Reviewed

| Document | URL | Last Updated |
|----------|-----|-------------|
| GDPR & EU Compliance | https://buttondown.com/legal/gdpr-eu-compliance | Unknown |
| Data Processing Agreement | https://buttondown.com/legal/data-processing-agreement | Unknown |
| Privacy Policy | https://buttondown.com/legal/privacy | October 20, 2019 |

## 3. Article 28(3) Compliance Matrix

| GDPR Art. 28 Requirement | DPA Coverage | Assessment |
|--------------------------|-------------|------------|
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

## 4. Critical Gaps

### Gap 1: No EU-US Transfer Mechanism (CRITICAL)

The DPA acknowledges international transfers must comply with GDPR Chapter V but does not incorporate or reference:
- Standard Contractual Clauses (2021 Decision, Module 2)
- EU-US Data Privacy Framework certification
- Any adequacy decision

**Impact:** Without a valid transfer mechanism, every EU subscriber's data transfer to Buttondown's US infrastructure lacks legal basis under Chapter V. This is a blocking compliance issue.

**Our exposure:** Jikigai's Privacy Policy (Section 5.3) currently asserts "International data transfers are covered by Standard Contractual Clauses (SCCs)." This assertion is unsupported.

### Gap 2: Missing DPA Annex (HIGH)

Article 28(3) requires the DPA to specify:
- Subject matter and duration of processing
- Nature and purpose of processing
- Type of personal data
- Categories of data subjects

None of these are documented in the DPA.

### Gap 3: US Governing Law (MEDIUM)

DPA Section 12 specifies US governing law and US court jurisdiction. GDPR Art. 28(4) requires the DPA to be governed by EU/Member State law. A GDPR supremacy clause would mitigate this.

### Gap 4: Privacy Policy Contradictions (MEDIUM)

Buttondown's 2019 privacy policy (Section 3) mentions "third-party advertising companies" and tracking technologies. The GDPR compliance page states "no data is ever used for advertising purposes." This inconsistency needs clarification.

### Gap 5: Plan Tier Scope (UNKNOWN)

Per our GitHub DPA precedent (learnings: `2026-02-21-github-dpa-free-plan-scope-limitation.md`), DPAs sometimes only cover paid plans. Buttondown's DPA does not specify tier applicability. Must confirm the free tier is covered.

## 5. Sub-processor Inventory

From the GDPR compliance page (NOT from the DPA):

| Sub-processor | Purpose | Location |
|---------------|---------|----------|
| Mailgun | Email delivery | US |
| Postmark | Email delivery | US |
| Stripe | Payment processing | US |

The DPA itself contains no sub-processor list or reference URL.

## 6. Data Categories Comparison

| Category | Our Docs Claim | Buttondown Actually Collects |
|----------|---------------|------------------------------|
| Email address | Yes | Yes |
| IP address | No | Yes (per GDPR compliance page) |
| Referrer metadata | No | Yes (per GDPR compliance page) |
| Subscription timestamp | Yes (implied) | Not explicitly stated |

**Action needed:** Our Privacy Policy (Section 4.6) and GDPR Policy (Section 4.2) list only email addresses. IP addresses and referrer metadata should be added once confirmed.

## 7. Recommended Actions

### Immediate (before signing)

| # | Action | Owner |
|---|--------|-------|
| 1 | Email Buttondown DPO requesting SCCs or DPF status | Jean |
| 2 | Request DPA Annex template | Jean |
| 3 | Request formal sub-processor list | Jean |
| 4 | Request GDPR supremacy clause | Jean |
| 5 | Clarify advertising contradiction | Jean |
| 6 | Confirm free-tier DPA applicability | Jean |

### After Buttondown responds

| # | Action | Owner |
|---|--------|-------|
| 7 | If SCCs available: execute SCCs, sign amended DPA | Jean |
| 8 | If no SCCs/DPF: evaluate Loops as backup platform | CLO |
| 9 | Update Privacy Policy Section 4.6 and 5.3 | Legal agents |
| 10 | Update GDPR Policy Section 4.2 and 10 | Legal agents |
| 11 | Update Data Protection Disclosure Section 2.3(e) and 4.2 | Legal agents |
| 12 | Run legal-compliance-auditor for cross-document consistency | Legal agents |
| 13 | Update Article 30 private register | Jean |

## 8. Draft Reply Email to Buttondown

**Subject:** Re: Buttondown GDPR/DPA — Follow-up questions

Hi Steph,

Thanks for the quick response and the links — we've reviewed all three documents thoroughly.

Buttondown's DPA covers many of the Article 28 requirements well (instructions-bound processing, confidentiality, data subject rights assistance, audit rights, breach notification). However, we've identified a few gaps we'd need addressed before we can formalize the controller-processor relationship:

**1. EU-US Data Transfer Mechanism**
The DPA (Section 8) acknowledges that international transfers must comply with GDPR Chapter V, but doesn't specify a mechanism. As a French company with EU-based subscribers, we need one of:
- Confirmation that Buttondown is certified under the **EU-US Data Privacy Framework (DPF)**, or
- Execution of the **EU Commission Standard Contractual Clauses** (2021 Decision, Module 2: Controller-to-Processor)

Could you confirm which transfer mechanism Buttondown supports?

**2. DPA Annex (Processing Details)**
Article 28(3) requires the DPA to specify the subject matter, duration, nature/purpose of processing, types of personal data, and categories of data subjects. The current DPA doesn't include this annex. For our use case, this would be straightforward:
- **Data subjects:** Newsletter subscribers (EU-based)
- **Personal data:** Email addresses, IP addresses, referrer metadata, subscription timestamps
- **Purpose:** Newsletter delivery and subscription management
- **Duration:** Duration of the service agreement

Is there a template annex we can populate, or can this be added?

**3. Sub-processor List**
The GDPR compliance page mentions Mailgun, Postmark, and Stripe as sub-processors, but the DPA itself (Section 5) doesn't reference or incorporate this list. Could you provide a formal, maintained sub-processor list — ideally at a stable URL — that we can reference in our records?

**4. Governing Law**
The DPA (Section 12) specifies US governing law. Given that GDPR obligations are at stake, would it be possible to add a clause providing that GDPR takes precedence to the extent of any conflict with US law?

**5. Minor Clarification**
Your GDPR compliance page states that subscriber data is never used for advertising. However, the privacy policy (last updated October 2019) references third-party advertising companies and tracking technologies. Could you confirm the current position — specifically that newsletter subscriber email data is not shared with advertising networks?

We're very happy with Buttondown as a platform and keen to get this formalized. If you have an updated DPA template that addresses these points, we're happy to review and sign. Otherwise, we can work from the existing document with amendments.

Thanks again for the help — looking forward to your response.

Best regards,
Jean
Jikigai — soleur.ai

## 9. Precedent Reference

This review follows the pattern established by the GitHub DPA verification (`knowledge-base/specs/archive/2026-02-22-165750-feat-github-dpa-verify/dpa-verification-memo.md`):
- Verify DPA scope for actual plan tier
- Document findings in structured memo
- Update legal docs to reflect reality, not aspirations

## 10. Disclaimer

This memo is AI-assisted draft analysis, not legal advice. All findings and recommendations should be reviewed by a qualified legal professional before acting on them.
