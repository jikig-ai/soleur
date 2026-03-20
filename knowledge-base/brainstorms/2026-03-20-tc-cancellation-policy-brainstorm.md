# Brainstorm: T&C Subscription Cancellation and EU Withdrawal Policy

**Date:** 2026-03-20
**Issue:** #893
**Branch:** feat-tc-cancellation-policy
**Status:** Decided

## What We're Building

Add subscription lifecycle clauses to the Terms & Conditions covering cancellation, refunds, account deletion with active subscriptions, and EU 14-day withdrawal right compliance. This is pre-launch legal infrastructure — no paid subscription product exists yet, but these clauses must be in place before billing goes live.

## Why This Approach

A new standalone Section 5 ("Subscriptions, Cancellation, and Refunds") consolidates all subscription lifecycle rules in one place. This is preferable to scattering changes across existing Sections 2, 4.3, and 13.1b because:

- Users can find all their subscription rights in one place
- Future subscription changes only touch one section
- Cross-references to payment processing (Section 4.3) and termination (Section 13) keep those sections focused

## Key Decisions

1. **Cancellation timing:** Cancel takes effect at end of current billing period. User retains access through the paid period. No refund for remaining time.

2. **Account deletion with active subscription:** Triggers the same cancellation flow — subscription cancels at period end, account data is deleted per privacy policy. No refund.

3. **EU 14-day withdrawal right:** Art. 16(m) waiver — user explicitly consents to waive the 14-day withdrawal right when starting immediate access to the digital service. If they do not consent, access is delayed 14 days. Requires explicit consent UX at Stripe Checkout.

4. **General refund policy:** Discretionary — refunds may be issued at company discretion. No automatic entitlement beyond EU withdrawal right.

5. **Document structure:** New standalone Section 5 in the T&C. Requires renumbering subsequent sections (current 5-16 become 6-17).

## Implementation Notes

- T&C must be updated in two locations kept in sync:
  - `docs/legal/terms-and-conditions.md` (source, markdown links)
  - `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy copy, absolute HTML links)
- Sections 4.3 and 13.1b should cross-reference the new Section 5
- EU withdrawal waiver needs a corresponding checkout UX (out of scope for this issue — track separately)

## Open Questions

None — all product decisions resolved during brainstorm.

## Domain Leader Assessments

### CLO Assessment
- EU Consumer Rights Directive 2011/83/EU Art. 16(m) waiver is the standard approach for digital services
- Must use explicit opt-in language at point of purchase for the waiver to be valid
- Privacy Policy and DPA may need review if payment data handling changes

### CPO Assessment
- No paid product exists yet — this is correctly sequenced as pre-launch infrastructure
- Refund policy is a product decision (now resolved: discretionary refunds)
- Aligns with PIVOT validation verdict: legal infrastructure, not feature development
