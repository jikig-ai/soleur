---
title: "feat: implement waitlist signup form and subscriber storage for pricing page"
type: feat
date: 2026-03-25
issue: 1139
parent_issue: 656
---

# feat: implement waitlist signup form and subscriber storage for pricing page

## Overview

The pricing page (`plugins/soleur/docs/pages/pricing.njk`) has a "Hosted Pro" tier with a disabled "Join the Waitlist" button and a "Coming Soon" badge. The button does nothing. This plan converts it into a functional waitlist signup form that captures email addresses and tier interest, stores subscribers via Buttondown with tag-based segmentation, fires Plausible analytics events, and handles GDPR consent.

The existing newsletter form pattern (`_includes/newsletter-form.njk` + inline JS in `base.njk`) provides a proven template. The waitlist form adapts this pattern with pricing-specific messaging, a hidden tier-interest field, and a distinct Buttondown tag (`pricing-waitlist`).

## Problem Statement / Motivation

The pricing page is a high-intent page -- visitors who reach it are evaluating whether to use Soleur. The "Hosted Pro" tier is not yet available, but capturing interest from potential paying users is critical for:

1. **Validating demand** -- knowing how many people want the hosted product helps prioritize development
2. **Segmented outreach** -- when tiers launch, emailing interested users with tier-specific messaging drives conversion
3. **Understanding tier preference** -- capturing which tier sparked interest reveals pricing model viability

Currently the disabled button is a dead end. Every visitor who considers "Hosted Pro" and cannot act on it is a lost signal.

## Proposed Solution

### Approach: Buttondown with tag-based segmentation

Continue with Buttondown (already integrated for newsletter). Use tag-based segmentation to distinguish waitlist from newsletter subscribers:

- **Tag:** `pricing-waitlist` on all waitlist signups
- **Metadata:** `tier_interest` field via Buttondown's metadata API (Solo / Startup / Scale / Enterprise)
- **Separation:** Waitlist subscribers are identifiable via tag filter in Buttondown dashboard

**Why not a dedicated waitlist service or custom backend:**

- Buttondown is already a data processor in the privacy policy and GDPR documentation
- Adding a new service requires a new DPA, sub-processor registration, and legal doc updates
- Tag-based segmentation in Buttondown handles the use case without additional infrastructure
- The metadata API supports arbitrary key-value pairs for tier interest capture

### Implementation

#### 1. Waitlist form component (`plugins/soleur/docs/_includes/waitlist-form.njk`)

Create a new Nunjucks partial for the waitlist form. Structure mirrors `newsletter-form.njk` but with waitlist-specific content:

```text
- Email input with validation and honeypot spam protection
- Hidden field: tag = "pricing-waitlist"
- Hidden field: metadata__tier_interest = (passed via Nunjucks variable from pricing page)
- Submit button: "Join the Waitlist"
- Privacy notice with link to privacy policy
- Status area for success/error messages (aria-live="polite")
```

#### 2. Pricing page updates (`plugins/soleur/docs/pages/pricing.njk`)

Replace the disabled `<button>` on the "Hosted Pro" card with an anchor that scrolls to a waitlist form section at the bottom of the page (before the Final CTA). The form is placed once; the card CTA links to it via `#waitlist`.

If tier interest capture is implemented (enhancement), each card's CTA passes the tier name as a URL fragment or query parameter that the form reads on load.

**Current markup to replace:**

```html
<button class="btn btn-secondary pricing-card-cta" disabled>Join the Waitlist</button>
```

**New markup:**

```html
<a href="#waitlist" class="btn btn-secondary pricing-card-cta">Join the Waitlist</a>
```

**New section before Final CTA:**

```text
<section id="waitlist" class="landing-section">
  {% set location = "pricing-waitlist" %}
  {% include "waitlist-form.njk" %}
</section>
```

#### 3. Form submission JavaScript (inline in `base.njk` or pricing page)

Adapt the existing newsletter form JS pattern. Key differences:

- Selector: `.waitlist-form` instead of `.newsletter-form`
- Plausible event: `Waitlist Signup` with props `{ location: "pricing-waitlist", tier: tierValue }`
- Success message: "You're on the list! We'll email you when Hosted Pro launches."
- Posts to Buttondown embed-subscribe endpoint with the `pricing-waitlist` tag

#### 4. CSS additions (`plugins/soleur/docs/css/style.css`)

Add styles for the waitlist form section. Reuse existing `.newsletter-*` pattern where possible. New classes:

- `.waitlist-section` -- styled like `.newsletter-section` but potentially with accent border to highlight
- `.waitlist-form` -- mirrors `.newsletter-form` layout
- `.waitlist-status`, `.waitlist-success`, `.waitlist-error` -- mirrors newsletter status classes

#### 5. Plausible analytics goal

Create a `Waitlist Signup` custom event goal in Plausible (via API or dashboard). This is distinct from the existing `Newsletter Signup` goal. Properties to track: `location`, `tier`.

#### 6. Legal doc review

The privacy policy already covers Buttondown email collection (Section 4.6). Waitlist signup uses the same mechanism (email submitted to Buttondown with consent). Verify:

- The consent language in the waitlist form matches the privacy policy's description
- The `pricing-waitlist` tag does not constitute a new data category requiring policy update
- If tier interest metadata is stored, confirm it falls under the existing "subscription metadata" category

No new legal documents should be needed -- this is an additional use of an existing data processor for the same data type (email address) under the same legal basis (consent, Art. 6(1)(a)).

## Technical Considerations

### Buttondown API compatibility

The Buttondown embed-subscribe endpoint (`https://buttondown.com/api/emails/embed-subscribe/<username>`) accepts:

- `email` -- subscriber email
- `tag` -- tag to apply (e.g., `pricing-waitlist`)
- `metadata` -- JSON object for custom fields (e.g., `{"tier_interest": "solo"}`)

Verify the embed endpoint accepts `tag` and `metadata` fields via POST. If not, the form may need to use the authenticated API instead (requires a Buttondown API key, which would need to be exposed client-side or handled via a server-side proxy -- undesirable).

**Fallback:** If the embed endpoint does not support tags/metadata, use the embed endpoint for email capture only, and apply tags manually in the Buttondown dashboard or via a post-signup webhook.

### Double opt-in

Buttondown uses double opt-in by default. Waitlist subscribers will receive a confirmation email. The waitlist success message should reflect this: "Check your email to confirm your spot on the waitlist."

### Spam protection

Reuse the honeypot pattern from the newsletter form (hidden `url` field with `tabindex="-1"`).

### Accessibility

- All form inputs have associated labels (visible or `sr-only`)
- Status messages use `aria-live="polite"` for screen reader announcements
- Form is keyboard-navigable
- Color contrast meets WCAG 2.1 AA

### Performance

No additional JS libraries. The form uses vanilla JS and the browser's `fetch` API, matching the newsletter pattern. No measurable performance impact.

## Acceptance Criteria

- [ ] "Join the Waitlist" button on Hosted Pro card scrolls to the waitlist form section
- [ ] Waitlist form captures email and submits to Buttondown with `pricing-waitlist` tag
- [ ] Honeypot spam protection field is present and hidden
- [ ] Successful submission shows confirmation message and clears the input
- [ ] Failed submission shows error message
- [ ] Plausible `Waitlist Signup` event fires on successful submission with `location: pricing-waitlist`
- [ ] Form is accessible: labels, aria attributes, keyboard navigation, color contrast
- [ ] Mobile responsive: form layout works on screens as narrow as 320px
- [ ] Privacy notice with link to privacy policy appears below the form
- [ ] Double opt-in confirmation email is sent by Buttondown
- [ ] Legal docs reviewed -- no updates needed if existing coverage is sufficient

### Enhancement (optional, can be deferred)

- [ ] Tier interest is captured as Buttondown metadata when user clicks a specific tier's CTA
- [ ] Plausible event includes `tier` property

## Test Scenarios

- Given a visitor on the pricing page, when they click "Join the Waitlist" on Hosted Pro card, then the page scrolls to the waitlist form section
- Given a visitor with a valid email, when they submit the waitlist form, then the email is sent to Buttondown with `pricing-waitlist` tag and a success message appears
- Given a visitor with an invalid email, when they submit the form, then browser validation prevents submission
- Given a bot filling the honeypot field, when the form is submitted, then Buttondown rejects the submission
- Given a network error, when the form is submitted, then an error message appears and the button re-enables
- Given a successful submission, when Plausible is loaded, then a `Waitlist Signup` event is recorded
- Given a mobile visitor on a 320px screen, when viewing the waitlist form, then the layout is usable and no horizontal scroll occurs

## Domain Review

**Domains relevant:** Marketing, Product, Legal

### Marketing

**Status:** reviewed
**Assessment:** The waitlist form is a conversion opportunity on the highest-intent page. Key concerns: (1) The CTA copy "Join the Waitlist" is adequate but could be tested against alternatives like "Get Early Access" or "Reserve Your Spot" for conversion optimization. (2) The success message should reinforce the value proposition, not just confirm signup. (3) The Plausible `Waitlist Signup` goal enables tracking the conversion funnel from pricing page visit to waitlist signup -- this metric should be added to the weekly growth audit. (4) Consider adding the waitlist count to the pricing page as social proof once it reaches a meaningful number.

### Legal

**Status:** reviewed
**Assessment:** Low legal risk. The waitlist form collects the same data type (email address) via the same processor (Buttondown) under the same legal basis (consent, Art. 6(1)(a) GDPR) as the existing newsletter form. The `pricing-waitlist` tag is internal segmentation metadata, not a new data category. Tier interest metadata (if captured) is non-PII categorization data provided voluntarily. No privacy policy or GDPR policy updates are required. The form must include: (1) a consent-clear submit action (the "Join the Waitlist" button constitutes active consent), (2) a link to the privacy policy, (3) an unsubscribe mechanism (handled by Buttondown's default footer). Double opt-in confirmation email satisfies the verified consent requirement.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo
**Pencil available:** N/A

#### Findings

**User Flow Analysis:** The flow is linear and minimal risk: Card CTA -> scroll to form -> enter email -> submit -> confirmation. Dead ends: none (success message is terminal, appropriate for a waitlist). Missing states: none identified. Error handling: network failure and invalid email are covered.

**Product Assessment:** The waitlist form validates demand for the Hosted Pro tier before building it. The tier interest capture (enhancement) adds signal quality at minimal implementation cost. Concern: the form should set clear expectations about timeline -- "We'll email you when Hosted Pro launches" is better than a generic "Thanks for signing up" because it establishes a concrete commitment. The pricing page currently has only two tiers (Open Source + Hosted Pro); if more tiers are added later, the form should support multiple tier interest capture.

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Buttondown embed endpoint does not accept `tag` param | Medium | Medium | Test manually first; fallback to manual tagging |
| Buttondown embed endpoint does not accept `metadata` param | Medium | Low | Defer tier interest capture to a post-MVP enhancement |
| Double opt-in email looks like newsletter confirmation | Low | Low | Review Buttondown confirmation email customization |
| Form is mistaken for newsletter signup | Low | Medium | Distinct section heading and copy differentiate it |

## Success Metrics

- **Waitlist signup rate:** % of pricing page visitors who submit the waitlist form (target: >2% in first month)
- **Confirmation rate:** % of waitlist signups who confirm via double opt-in (target: >70%)
- **Plausible event tracking:** `Waitlist Signup` events appear in Plausible dashboard with correct properties

## References & Research

### Internal References

- Pricing page: `plugins/soleur/docs/pages/pricing.njk`
- Newsletter form template: `plugins/soleur/docs/_includes/newsletter-form.njk`
- Base template (inline JS): `plugins/soleur/docs/_includes/base.njk:119-147`
- Site config (Buttondown username): `plugins/soleur/docs/_data/site.json:12-14`
- CSS styles: `plugins/soleur/docs/css/style.css:1021-1070` (newsletter), `1098-1216` (pricing)
- Privacy policy: `plugins/soleur/docs/pages/legal/privacy-policy.md:93-101`
- Learning -- PII collection legal pattern: `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`
- Learning -- Buttondown GDPR: `knowledge-base/project/learnings/2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md`
- Learning -- Plausible operationalization: `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md`

### Related Issues

- Parent issue: [#656](https://github.com/jikig-ai/soleur/issues/656) -- Pricing page v2
- PR: [#1136](https://github.com/jikig-ai/soleur/pulls/1136) -- Pricing page v2 implementation (OPEN, WIP)
- This issue: [#1139](https://github.com/jikig-ai/soleur/issues/1139)
