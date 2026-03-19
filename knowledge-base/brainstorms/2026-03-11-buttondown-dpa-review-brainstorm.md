# Buttondown DPA Review Brainstorm

**Date:** 2026-03-11 (updated 2026-03-17, 2026-03-19)
**Status:** Complete — All blocking gaps resolved. DPA ready to sign.
**Related Issue:** #501 (Newsletter — closed, DPA verification outstanding)

## What We're Doing

Reviewing Buttondown's standard legal documents (DPA, GDPR compliance page, privacy policy) to determine whether they adequately support the controller-processor relationship needed for Jikigai's GDPR compliance as a French company processing EU subscriber data through a US-based newsletter platform.

## Why This Matters

Newsletter signup forms are live on soleur.ai collecting EU subscriber email addresses. Our Privacy Policy (Section 5.3), GDPR Policy (Section 10), and Data Protection Disclosure (Section 2.3(e)) already reference Buttondown as a processor and claim SCCs are in place — but the actual DPA has never been verified or signed. This is a compliance gap.

## Key Findings

### Buttondown's DPA — What Works

- Processing only on documented instructions (Art. 28(3)(a)) — Section 3.1
- Confidentiality obligations — Section 3.2
- Data subject rights assistance — Section 6
- Deletion/return after termination — Section 11.2
- Audit rights — Section 9
- Breach notification — Section 7 ("without undue delay")

### Buttondown's DPA — Critical Gaps

1. **No EU-US transfer mechanism.** DPA Section 8 acknowledges Chapter V compliance but specifies no mechanism (no SCCs, no DPF certification, no adequacy decision). This is the most significant gap.

2. **Missing mandatory Annex.** Article 28(3) requires the DPA to set out subject matter, duration, nature/purpose of processing, data types, and data subject categories. None present.

3. **US governing law (Section 12).** Problematic for a French controller — GDPR Art. 28(4) requires the DPA to be governed by EU/Member State law.

4. **No formal sub-processor list.** GDPR compliance page mentions Mailgun, Postmark, Stripe informally. Not incorporated into the DPA.

5. **Breach notification lacks 72-hour commitment.** "Without undue delay" does not guarantee the controller can meet the Art. 33 72-hour supervisory authority notification deadline.

6. **Privacy policy contradictions.** The 2019 privacy policy mentions third-party advertising; the GDPR compliance page claims no advertising use. Inconsistency.

### Our Own Documents — Exposure

Our Privacy Policy Section 5.3 asserts "International data transfers are covered by Standard Contractual Clauses (SCCs)." This claim is currently unsupported by Buttondown's documents. If CNIL investigated, Jikigai could not substantiate it.

## Decision

**Do NOT sign the standard DPA as-is.** Contact Buttondown's DPO to request:
1. SCCs (Module 2) or DPF certification confirmation
2. DPA Annex with processing details
3. Formal sub-processor list
4. GDPR supremacy clause for governing law
5. Clarification on advertising contradiction

## Draft Reply Email

See verification memo: `knowledge-base/specs/feat-buttondown-dpa-review/dpa-verification-memo.md`

## Open Questions

1. Does Buttondown's free tier include DPA coverage? (GitHub DPA precedent: only paid plans)
2. Will Buttondown agree to SCCs execution or are they DPF-certified?
3. Are tracking pixels embedded in emails? (Would require additional privacy disclosure)
4. What is the actual data retention period for backups after account termination?

## March 16 Update — Buttondown Legal Docs Refresh

[Updated 2026-03-17]

On 2026-03-16, Buttondown published a [legal docs refresh](https://buttondown.com/blog/2026-03-16-legal-docs-refresh) addressing most of our identified gaps. The blog states changes came from "customer feedback during their own GDPR compliance review" — that's us.

### What Changed

| Document | Changes |
|----------|---------|
| DPA | Added Annex 1 (processing details), sub-processor list reference in Section 5, GDPR precedence clause in Section 12, updated Section 8 referencing SCCs |
| Privacy Policy | First update since October 2019. Removed misleading advertising references. Contact email → support@buttondown.com |
| Sub-Processor List | Now a dedicated page at `/legal/subprocessors` with 12 vendors (was 3 informally listed). Added: AWS, Betterstack, Cloudflare, Google Workspace, Heroku, Plain, Seline, Sentry, Slack |
| Cookie Policy | New document categorizing cookies as essential, functional, or analytics. No advertising cookies. |
| GDPR Compliance Page | Updated language, linked to sub-processor list and DPA |

### Gap Re-Assessment

| Gap | March 11 Status | March 16 Status | Verdict |
|-----|-----------------|-----------------|---------|
| 1. EU-US Transfer Mechanism | CRITICAL — no mechanism | Section 8 references SCCs generically | **RESOLVED (March 19)** — SCCs (Decision 2021/914, Module 2) incorporated by reference with clause-by-clause completion. Annex B completes SCC annexes. |
| 2. Missing DPA Annex | HIGH — no Art. 28(3) details | Annex 1 added (subject matter, duration, data types, data subjects) | **RESOLVED** |
| 3. US Governing Law | MEDIUM — no GDPR supremacy | Section 12 GDPR/UK/Swiss precedence clause | **RESOLVED** |
| 4. Privacy Policy Contradictions | MEDIUM — advertising references | Advertising references removed, policy updated | **RESOLVED** |
| 5. Free Tier Scope | UNKNOWN | Not addressed | **RESOLVED (March 19)** — Steph confirmed DPA applies to all plans (free and paid). Paid plans expose additional Stripe data. |

### New Finding

**Art. 28(3) instruction-infringement notification:** The DPA does not require Buttondown to notify us if they believe a processing instruction infringes GDPR (second subparagraph of Art. 28(3)). Minor gap, but worth flagging.

### Revised Decision (March 19)

**All blocking gaps resolved. DPA ready to sign.**

1. ~~Update confirmed facts (sub-processors, data types)~~ — DONE (March 17)
2. ~~Send follow-up email requesting SCCs + free-tier confirmation~~ — DONE (sent; Steph replied March 19)
3. Update SCCs/transfer mechanism claims in our legal docs — now substantiated by DPA Section 8 (Decision 2021/914, Module 2)
4. Update free-tier DPA confirmation in our legal docs
5. Run legal-compliance-auditor for cross-document consistency
6. Sign DPA and close #501

## Next Steps

1. ~~Send reply email to Buttondown~~ — DONE
2. ~~Update legal docs with confirmed facts (sub-processors, data types)~~ — DONE (March 17)
3. ~~Wait for Buttondown response on SCCs and free-tier scope~~ — DONE (Steph replied March 19)
4. Update transfer-related claims in our docs — IN PROGRESS (March 19)
5. Run legal-compliance-auditor for cross-document consistency
6. Sign DPA — all blocking gaps resolved
7. Close #501
