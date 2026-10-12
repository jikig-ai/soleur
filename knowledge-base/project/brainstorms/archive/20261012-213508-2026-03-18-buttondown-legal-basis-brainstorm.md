# Brainstorm: Clarify Legal Basis for Buttondown Data (#666)

**Date:** 2026-03-18
**Status:** Complete
**Issue:** #666

## What We're Building

Correcting the legal basis and data disclosure for Buttondown newsletter subscription data across all three legal document types (Privacy Policy, GDPR Policy, Data Protection Disclosure).

Currently, all documents claim consent (Art 6(1)(a)) as the sole lawful basis and state "email address only" as the data collected. Both claims are incomplete or incorrect:

1. **Undisclosed data types.** Buttondown automatically collects IP address, referrer URL, subscription timestamp, and browser/device metadata during the subscription HTTP request. The "email address only" disclosure is factually incomplete (transparency violation, Articles 13-14).

2. **Incorrect legal basis for automatic data.** Consent may not be the correct basis for data the user does not actively provide. The docs already use legitimate interest (Art 6(1)(f)) for identical data types elsewhere (Plausible analytics, GitHub Pages, CLA timestamps).

## Why This Approach

**Split basis** is the recommended approach:

- **Consent (Art 6(1)(a))** for email address — actively provided via double opt-in
- **Legitimate interest (Art 6(1)(f))** for HTTP metadata (IP address, referrer URL, subscription timestamp, browser/device info) — automatically collected by Buttondown during subscription

Rationale:

- Mirrors existing legitimate interest patterns in the docs (Plausible Section 4.3, CLA Section 4.5)
- Eliminates internal inconsistency: same data types should have same legal basis across sections
- CNIL requires consent to be specific and informed — bundling technical metadata into newsletter consent is the pattern regulators push back on (EDPB Guidelines 05/2020)
- Consent withdrawal (unsubscribe) cleanly stops email processing without ambiguity about IP log retention
- Balancing test for legitimate interest is straightforward: minimal data, necessary for service operation and abuse prevention, within reasonable expectations

**Rejected approach:** Consent covers everything. Weaker under CNIL specificity standards, creates withdrawal ambiguity, retroactively broadens consent scope.

## Key Decisions

- **Split legal basis:** Consent for email, legitimate interest for HTTP metadata
- **Scope to 4 core categories:** Email, IP, referrer, timestamp + browser/device metadata
- **No open/click tracking:** Buttondown's feature page confirms analytics tracking is opt-in by default. We haven't enabled it. Not in scope for this fix.
- **Add Art 21 right to object:** Explicitly mention in Privacy Policy Section 8.1 that right to object applies to newsletter metadata processed under legitimate interest
- **5 files across 3 document types:** Privacy Policy (x2), GDPR Policy (x2), DPA (x1)
- **Balancing test required:** Add three-part balancing test for legitimate interest on newsletter metadata (mirrors existing CLA/Plausible pattern)

## Open Questions

None — all questions resolved during brainstorming.

## References

- Buttondown privacy policy: <https://buttondown.com/legal/privacy>
- Buttondown features page confirms opt-in tracking: "We don't collect any data about you or your subscribers by default"
- Existing learnings: `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`
- CLO assessment completed 2026-03-18 (recommended split basis)
