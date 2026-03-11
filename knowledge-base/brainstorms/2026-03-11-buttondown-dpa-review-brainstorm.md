# Buttondown DPA Review Brainstorm

**Date:** 2026-03-11
**Status:** Complete
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

## Next Steps

1. Send reply email to Buttondown (draft in verification memo)
2. Wait for Buttondown's response on transfer mechanism and DPA amendments
3. Based on response: either sign amended DPA, or evaluate Loops as backup platform
4. Update our 3 legal docs × 2 locations to reflect actual (not aspirational) terms
5. Run legal-compliance-auditor for cross-document consistency after updates
