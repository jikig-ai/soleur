---
title: "fix: clarify legal basis for Buttondown data (#666)"
type: fix
date: 2026-03-18
---

# fix: Clarify legal basis for automatically-collected Buttondown data (#666)

## Overview

Privacy Policy Section 4.6, GDPR Policy Section 3.6, and DPD Section 2.3(e) all claim consent (Art 6(1)(a)) as the sole lawful basis and state "email address only" as the data collected by Buttondown. This is factually incomplete (Buttondown collects HTTP metadata automatically) and uses the wrong legal basis for data the user doesn't actively provide.

## Proposed Solution

Split the lawful basis:
- **Consent (Art 6(1)(a))** for email address — actively provided via double opt-in
- **Legitimate interest (Art 6(1)(f))** for technical metadata (IP address, referrer URL, subscription timestamp, browser/device info) — automatically collected by Buttondown during subscription

Add a balancing test for the legitimate interest claim, mirroring the existing pattern used for Plausible analytics (Section 4.3) and CLA signatures (Section 4.5).

## Acceptance Criteria

- [ ] AC1: Privacy Policy Section 4.6 lists all data types with split lawful basis
- [ ] AC2: Privacy Policy Section 5.3 mentions technical metadata (not just email)
- [ ] AC3: Privacy Policy Section 6 newsletter paragraph reflects split basis
- [ ] AC4: Privacy Policy Section 7 has split retention for email vs. technical metadata
- [ ] AC5: GDPR Policy Section 3.6 updated with split basis and balancing test
- [ ] AC6: GDPR Policy Section 4.2 table Buttondown row lists all data types
- [ ] AC7: GDPR Policy Section 10 processing register activity #6 updated
- [ ] AC8: DPD Section 2.3(e) updated with complete data types and split basis
- [ ] AC9: Last Updated dates changed to 2026-03-18 on all modified files

## Context

### Files to Modify (6 files, 3 document types)

| # | File | Sections to Change |
|---|------|-------------------|
| 1 | `docs/legal/privacy-policy.md` | 4.6, 5.3, 6, 7, Last Updated |
| 2 | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 4.6, 5.3, 6, 7, Last Updated |
| 3 | `docs/legal/gdpr-policy.md` | 3.6, 4.2 table, 10 register, Last Updated |
| 4 | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 3.6, 4.2 table, 10 register, Last Updated |
| 5 | `docs/legal/data-protection-disclosure.md` | 2.3(e), Last Updated |
| 6 | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 2.3(e), Last Updated |

### Replacement Content

**Privacy Policy Section 4.6 — new data and basis lines:**
```
- **Data collected:** Email address (actively provided by you); IP address, referrer URL, subscription timestamp, and browser/device metadata (automatically collected by Buttondown during the subscription request).
- **Purpose:** Sending periodic newsletter emails about Soleur updates, features, and content.
- **Lawful basis (email address):** Consent (Article 6(1)(a) GDPR) -- you actively opt in by submitting the signup form and confirming your subscription via the double opt-in confirmation email.
- **Lawful basis (technical metadata):** Legitimate interest (Article 6(1)(f) GDPR) -- Buttondown automatically collects IP address, referrer URL, subscription timestamp, and browser/device metadata as part of standard service operation. This data is necessary for service delivery, abuse prevention, and maintaining the security of the newsletter infrastructure. The processing is minimal, within the reasonable expectations of a newsletter subscriber, and does not involve profiling or automated decision-making. You may object to this processing under Article 21 by contacting us at legal@jikigai.com.
```

**Privacy Policy Section 5.3 — update Buttondown description:**

Currently says "your email address is transmitted to and stored by Buttondown." Change to mention that Buttondown also automatically collects technical metadata during the subscription request.

**Privacy Policy Section 6 — new newsletter paragraph:**
```
For newsletter subscriptions, the legal basis for processing your email address is **consent** (Article 6(1)(a) GDPR). You provide consent by submitting the signup form and confirming your subscription via the double opt-in email. You may withdraw consent at any time by unsubscribing. For the technical metadata automatically collected by Buttondown during subscription (IP address, referrer URL, subscription timestamp, browser/device metadata), the legal basis is **legitimate interest** (Article 6(1)(f) GDPR) -- service operation and abuse prevention. You may object to this processing under Article 21 (see Section 8).
```

**Privacy Policy Section 7 — update newsletter retention bullet:**

Split retention: email retained until unsubscribe; technical metadata retention governed by Buttondown's data retention practices.

**GDPR Policy Section 3.6 — replacement:**
```
### 3.6 Newsletter Subscription

For processing of **email addresses** when visitors subscribe to the Soleur newsletter via the Docs Site, the lawful basis is **consent** (Article 6(1)(a)). Subscribers actively opt in by submitting the signup form and confirming their subscription via a double opt-in confirmation email sent by Buttondown. Consent may be withdrawn at any time by unsubscribing via the link included in every newsletter email. Upon withdrawal, the email address is removed from the active subscriber list.

For the **technical metadata** automatically collected by Buttondown during the subscription request (IP address, referrer URL, subscription timestamp, browser/device metadata), the lawful basis is **legitimate interest** (Article 6(1)(f)). The balancing test for this interest considers: (a) the data is minimal and limited to standard HTTP request metadata, (b) the processing is necessary for service delivery and abuse prevention, (c) the data is within the reasonable expectations of someone subscribing to a newsletter, and (d) the processing does not involve profiling or automated decision-making. Data subjects may object to this processing under Article 21 by contacting legal@jikigai.com.
```

**GDPR Policy Section 4.2 table — new Buttondown row:**

Update data category from "Email address" to include all data types.

**GDPR Policy Section 10 — new activity #6:**

Split into (a) email with consent basis, (b) technical metadata with legitimate interest basis. Split retention.

**DPD Section 2.3(e) — replacement (both copies):**

Add technical metadata collection, split lawful basis, split retention. Apply same pattern to both `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.

### Verification Steps

```bash
# 1. No remaining "Email address only" in Buttondown context
grep -rn "Email address only" docs/legal/ plugins/soleur/docs/pages/legal/

# 2. All modified files mention legitimate interest for newsletter
grep -rn "legitimate interest" docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md | grep -i "newsletter\|buttondown\|subscription"

# 3. Both privacy policy copies match on modified sections
diff <(grep -A5 "Data collected" docs/legal/privacy-policy.md) <(grep -A5 "Data collected" plugins/soleur/docs/pages/legal/privacy-policy.md)

# 4. Both GDPR policy copies match on Section 3.6
diff <(grep -A15 "3.6 Newsletter" docs/legal/gdpr-policy.md) <(grep -A15 "3.6 Newsletter" plugins/soleur/docs/pages/legal/gdpr-policy.md)

# 5. Both DPD copies match on Section 2.3(e)
diff <(grep -A8 "Newsletter subscription management" docs/legal/data-protection-disclosure.md) <(grep -A8 "Newsletter subscription management" plugins/soleur/docs/pages/legal/data-protection-disclosure.md)

# 6. Last Updated dates
grep -rn "Last Updated" docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md
```

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-18-buttondown-legal-basis-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-gdpr-buttondown-legal-basis-666/spec.md`
- Issue: #666
- Buttondown privacy policy: https://buttondown.com/legal/privacy
- Related PR: #688 (draft)
