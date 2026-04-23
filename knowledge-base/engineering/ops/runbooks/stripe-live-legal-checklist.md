---
category: legal
tags: [stripe, billing, legal, eu-consumer-rights, saas-opt-out, tos, refund-policy, dpa]
date: 2026-04-23
owner: CLO
---

# Stripe Live-Mode Activation — Legal Pre-Flight Brief

This is the pre-activation legal brief for the Stripe live-mode flip (issue `#1444`).
Activation cannot proceed until the CLO has reviewed and signed off on all six
sections below. The vendor DPA for Stripe as a sub-processor is already closed
(issue `#670`), so no new sub-processor disclosure is expected from this flip —
section 4 is a confirmation task, not a drafting task. Everything below is a
**brief for the CLO to refine into reviewed legal text**; nothing here is final
customer-facing copy.

---

## Section 1 — EU 14-day cooling-off + SaaS digital-services opt-out

### Summary

Directive 2011/83/EU (the EU Consumer Rights Directive) grants EU consumers a
14-day right of withdrawal on distance-sold services. For digital services /
digital content supplied immediately upon conclusion of the contract, the
directive permits the consumer to **waive** that right — but only with explicit
prior consent and acknowledgment that the waiver causes loss of the withdrawal
right once performance begins.

The relevant waiver provision is Article 16 of Directive 2011/83/EU
(the digital-content / immediate-performance exception — CLO should confirm
the exact sub-paragraph citation in the final ToS text).

### Why this matters for Soleur

Soleur provisions account access immediately on successful Stripe checkout. If
an EU consumer signs up, uses the product for 13 days, then invokes the 14-day
right of withdrawal, they are entitled to a full refund **unless** the checkout
flow captured a valid, explicit, prior waiver of that right.

Without the waiver checkbox, the default EU position is: full refund on demand
within 14 days, regardless of usage. This is a direct revenue-leak risk and a
policy-drafting gap that must be closed before live-mode flip.

### Proposed checkout consent wording (DRAFT — for CLO selection)

The consent must be a separate, un-pre-checked checkbox adjacent to the
"Subscribe" / "Pay" button. Three candidate copy variants follow for CLO to
pick or refine:

- **Variant A (plain-language, consumer-friendly):**
  "I want immediate access to Soleur and I understand this means I waive my
  14-day right to withdraw from this contract once my access begins."

- **Variant B (closer to directive phrasing):**
  "I give my express consent to begin the service immediately and I acknowledge
  that I will lose my right of withdrawal once the service has been fully
  performed."

- **Variant C (shortest, recommended for mobile):**
  "I confirm I want immediate access to Soleur and waive my 14-day right of
  withdrawal for this digital service."

CLO should pick one (or blend), confirm it in the final ToS, and ensure the
same wording appears on the checkbox label and in the ToS section it
references.

### Implementation requirements (for engineering, surfaced here so CLO can scope)

- Checkbox is **explicit opt-in** (not pre-checked) — directive compliance
  requirement.
- Consent is **captured per subscription** (per checkout session), timestamped,
  and persisted alongside the Stripe `customer` / `subscription` record so it is
  retrievable for audit or dispute.
- Consent wording shown at checkout must match the ToS verbatim — if the text
  drifts, consent is arguably invalid.

### Scope note — EU-only vs. uniform

Stripe Tax location detection can distinguish EU from non-EU customers, which
would allow the checkbox to be shown only to EU customers. **Recommendation for
MVP: show the checkbox uniformly to all customers.** Rationale: (a) avoids
conditional-UX bugs where the gate silently fails to appear for an EU customer
whose IP geolocates outside the EU, (b) the wording is benign for non-EU
customers and does not create new US obligations, (c) single code path is
simpler for single-founder support. CLO should confirm the uniform-display
approach is acceptable.

---

## Section 2 — Refund / cancellation policy

### Proposed default

**Cancel-at-period-end.** When a customer cancels, their subscription remains
active through the end of the current paid period; no new charge occurs at
renewal. This matches the retention-modal UX in
`knowledge-base/product/design/billing/screenshots/04-retention-modal.png`,
which frames cancellation as "you'll keep access until [date]" rather than
immediate termination.

### Proposed refund default

**No pro-rata refunds for the current period** in the MVP policy. Reasoning:

1. Simplicity — a single founder cannot operate a pro-rata refund desk.
2. Peer-practice alignment — most B2B SaaS at similar stage (Basecamp, Linear,
   and comparable micro-SaaS) offer cancel-at-period-end without pro-rata.
3. The EU 14-day waiver in section 1 is the primary consumer protection; beyond
   that window, the paid period completes.

### Legitimate-refund escalation path

Refunds outside the default policy are handled **manually in the Stripe
Dashboard by the founder**. The CLO should codify which conditions qualify as
"legitimate" so the founder's discretion is bounded. Proposed criteria (CLO to
confirm / edit):

- **(a) Accidental duplicate charge** — Stripe-side retry or customer
  double-clicked; straightforward refund.
- **(b) Service unavailability greater than 48 hours** in the paid period
  attributable to Soleur (not a third-party outage the customer could route
  around).
- **(c) Jurisdiction-required refund** — e.g., the EU 14-day withdrawal where
  the waiver was not validly captured, or a consumer-protection authority order.

Anything outside these three categories is at founder discretion and not a
policy commitment.

### Scope note — chargebacks

Chargeback handling (customer disputes through their card network) is a Stripe
Dashboard workflow, not customer-facing policy. It does not belong in the
public refund policy. CLO: no action needed here beyond confirming the ToS
does not promise anything inconsistent with Stripe's chargeback process.

---

## Section 3 — Terms of Service subscription addendum

The existing `/legal/terms-of-service/` page covers general product use but
does not yet have subscription-specific clauses. The CLO should draft an
addendum (or dedicated subscription section) covering the five clauses below.
This section of the brief is a scope list, not draft copy — each clause needs
the CLO's legal language.

1. **Billing cycle.** Subscriptions are billed monthly, in advance, on the
   anniversary date of the initial charge. Renewal is automatic until the
   customer cancels.
2. **Price change notification.** Soleur will give **30 days' advance notice**
   of any price increase. The customer may cancel before the new price applies;
   continued subscription after the notice period constitutes acceptance.
3. **Tax handling.** Stripe Tax is enabled for VAT / sales tax calculation and
   collection. CLO to confirm whether the public price is **tax-inclusive**
   (EU convention) or **tax-exclusive** (US convention) — this decision is
   upstream of the ToS wording and must be settled before the addendum ships.
   Note: Stripe Tax does NOT handle VAT OSS registration; that remains the
   operator's responsibility and is not a customer-facing ToS topic.
4. **Data retention on cancellation.** The existing privacy policy already
   specifies a retention window for account data. The CLO must reconcile the
   subscription addendum's cancellation-data clause with the privacy policy's
   retention clause so the two documents state the same window and the same
   deletion trigger.
5. **Dispute resolution / jurisdiction.** The operator is EU-based. The CLO
   should specify governing law, venue, and any arbitration / small-claims
   carve-outs. This depends on the final entity structure (see section 5).

The addendum should be hosted at the existing `/legal/terms-of-service/` page,
either inline or as a linked sub-page, so there is a single canonical ToS URL.

---

## Section 4 — AUP / Privacy Policy sub-processor confirmation

This section is a **confirmation task**, not a drafting task. The vendor DPA
for Stripe was closed under issue `#670`, so the privacy policy should already
disclose Stripe as a sub-processor. CLO to verify:

1. `/legal/privacy-policy/` lists Stripe in the sub-processor table (or
   equivalent disclosure) with purpose = "payment processing" and data
   categories = billing contact + payment metadata.
2. The data-flow description covers **payment card data handling**: Stripe is
   PCI-DSS compliant; Soleur never stores PAN (primary account number) or CVV.
   The customer's card is entered into a Stripe-hosted element; Soleur
   receives only a tokenized reference and the last-4 / brand for display.

If both (1) and (2) are already present, no new disclosure is needed from
this flip. If the CLO finds a gap during review, flag it in the sign-off line
in section 6 and treat it as a blocker for live-mode activation.

---

## Section 5 — Stripe Atlas alignment note

The entity structure behind Soleur is **not yet confirmed** at the time of this
brief. The operator is EU-based (Jean Deruelle); Stripe Atlas (Delaware C-corp
formation) alignment is **possible but not confirmed**.

- **If the entity is a Delaware C-corp via Stripe Atlas:** the CLO should
  reference the learning at
  `knowledge-base/project/learnings/2026-02-25-stripe-atlas-legal-benchmark-mismatch.md`
  before using any "Atlas-aligned" boilerplate. The key gotcha documented there
  is that Stripe Atlas provides **corporate-formation documents** (bylaws,
  stock purchase agreements, Orrick IP-assignment templates), **not
  customer-facing SaaS ToS / privacy / refund policies**. Do not benchmark
  Soleur's customer-facing legal docs against Stripe's own public policies —
  those are tuned for a publicly traded financial-services company under
  PCI-DSS and money-transmission regimes, which is an apples-to-oranges
  comparison that over-commits obligations.
- **If the entity is NOT Stripe Atlas** (e.g., an EU entity, sole
  proprietorship, or a separate LLC the founder has not routed through
  Atlas): this section is informational only. The CLO should confirm the
  actual entity with the founder before drafting the dispute-resolution /
  jurisdiction clause in section 3.

Either way, the correct benchmarks for Soleur's customer-facing legal docs are
(a) the relevant regulation itself (e.g., GDPR Articles 13 / 14 enumerated
disclosures, Directive 2011/83/EU withdrawal-waiver language) and (b) peer
SaaS policies at similar stage and product category — not Stripe's own
policies.

---

## Section 6 — CLO sign-off

Activation of Stripe live mode (issue `#1444`) is blocked until this line is
filled in. The runbook at `stripe-live-activation.md` references this sign-off
as the Phase A precondition and will refuse to proceed past Phase A until the
checkbox below is ticked with a real date and initials.

- [ ] Reviewed by CLO on YYYY-MM-DD — signature / initials: _____

Sign-off attestation: by ticking the box above, the CLO confirms that sections
1 through 5 have been reviewed, any drafting gaps have been turned into
committed final legal text in the linked ToS / privacy policy / refund policy
documents, and no open blockers remain for the Stripe live-mode flip.

---

## Cross-references

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-23-stripe-live-mode-activation-brainstorm.md`
- Plan: `knowledge-base/project/plans/2026-04-23-feat-stripe-live-activation-plan.md`
- Related learning: `knowledge-base/project/learnings/2026-02-25-stripe-atlas-legal-benchmark-mismatch.md`
- Related closed issue (vendor DPA, Stripe covered): `#670`
- Activation runbook that gates on this sign-off: `stripe-live-activation.md`
- Retention-modal UX reference: `knowledge-base/product/design/billing/screenshots/04-retention-modal.png`
