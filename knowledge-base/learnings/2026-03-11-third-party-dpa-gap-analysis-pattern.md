---
date: 2026-03-11
category: integration-issues
module: legal-agents
problem_type: compliance-review
severity: high
---

# Learning: Third-Party DPA Gap Analysis Pattern

## Problem

When a third-party processor provides a "standard DPA," it may appear GDPR-compliant at first glance but contain structural gaps that create compliance exposure -- especially for EU controllers engaging US-based processors. Our own legal documents may already make assertions (e.g., "SCCs in place") that are unsupported by the processor's actual documents.

## Solution

Use a structured Art. 28(3) compliance matrix to systematically evaluate each mandatory requirement:

1. **Processing on documented instructions** (Art. 28(3)(a))
2. **Confidentiality obligations** (Art. 28(3)(b))
3. **Technical/organizational measures** (Art. 28(3)(c)) -- look for specifics, not just generic claims
4. **Sub-processor provisions** (Art. 28(3)(d)) -- must include actual list, not just general authorization
5. **Data subject rights assistance** (Art. 28(3)(e))
6. **Deletion/return after termination** (Art. 28(3)(f))
7. **Audit rights** (Art. 28(3)(h))
8. **Breach notification** -- must enable controller's 72-hour obligation under Art. 33
9. **International transfers** (Chapter V) -- specific mechanism required (SCCs, DPF, adequacy)
10. **DPA Annex** -- processing details mandatory (subject matter, duration, data types, data subject categories)

Also check: governing law (should be EU/Member State), plan tier applicability, and cross-reference claims in the processor's marketing pages against their actual contractual documents and privacy policy.

## Re-Verification Pattern (Added 2026-03-17)

When a processor updates their docs in response to your gap analysis:

1. **Fetch the actual updated documents** — don't rely on the blog post or changelog alone
2. **Re-run the Art. 28(3) matrix** against the updated documents, noting which gaps changed status
3. **Distinguish reference from execution** — a DPA that "references" SCCs generically is NOT the same as incorporating or executing SCCs. CNIL and other supervisory authorities require the actual instrument (Implementing Decision 2021/914 with Module specification)
4. **Update confirmed facts, hold unconfirmed claims** — update your own docs with data you can verify (sub-processor list, data types, contact info) but do NOT update claims about transfer mechanisms until the actual instrument is executed
5. **Check for new findings** — updated docs may introduce new gaps (e.g., missing Art. 28(3) second subparagraph notification duty)

## Key Insight

A processor's DPA can score well on individual Art. 28 requirements while having critical structural gaps (missing transfer mechanism, missing Annex). Always audit the DPA as a whole document, not just individual clauses. And critically: verify your OWN legal documents don't make unsupported claims about the processor's compliance posture before the DPA is actually signed.

**Re-verification insight:** When a vendor updates their docs after your feedback, the natural response is to treat everything as "fixed." Resist that. Re-verify against the actual documents, not the announcement. The Buttondown case showed that 3/5 gaps were genuinely resolved, but the critical one (SCCs) was only referenced, not executed — a distinction that matters legally.

## Session Errors

None -- clean sessions (both initial analysis 2026-03-11 and re-verification 2026-03-17).

## Tags

category: integration-issues
module: legal-agents, gdpr
