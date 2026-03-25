---
title: "feat: implement waitlist signup form and subscriber storage for pricing page"
type: feat
date: 2026-03-25
issue: 1139
parent_issue: 656
deepened: 2026-03-25
---

# feat: implement waitlist signup form and subscriber storage for pricing page

## Enhancement Summary

**Deepened on:** 2026-03-25
**Sections enhanced:** 6 (Proposed Solution, Technical Considerations, Implementation, Acceptance Criteria, Dependencies, References)
**Research sources:** Buttondown API docs, MDN Web Docs, Plausible goals provisioning script, project learnings (3), codebase analysis

### Key Improvements

1. **Buttondown API confirmed** -- embed forms officially support `name="tag"` for tags and `name="metadata__<key>"` for custom metadata. Top two risks eliminated; tier interest capture is MVP, not enhancement.
2. **Plausible goal provisioning automated** -- existing `scripts/provision-plausible-goals.sh` already provisions goals via PUT API. Add one line for `Waitlist Signup` event goal instead of manual dashboard configuration.
3. **Concrete HTML/JS reference code** -- added copy-paste-ready form markup and submission handler adapted from the proven newsletter pattern, reducing implementation ambiguity.

### New Considerations Discovered

- Buttondown metadata keys are cached for up to 1 hour before appearing in dashboard filters -- do not treat missing metadata in the dashboard as a bug immediately after first submission.
- The `.honeypot-trap` CSS class already exists in `style.css` accessibility layer -- reuse it directly, no new CSS needed for the honeypot.
- `html { scroll-behavior: smooth; }` is already set in the site CSS -- the `#waitlist` anchor link will smooth-scroll natively with no additional JS. `prefers-reduced-motion` is also handled.
- Multiple `<input name="tag">` fields are supported for multi-tag assignment -- future tier-specific tags can be added without architectural changes.

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

Create a new Nunjucks partial adapted from `newsletter-form.njk`. Reference markup:

```html
<section class="waitlist-section">
  <div class="container">
    <h2>Get early access to Hosted Pro</h2>
    <p>Be the first to know when the hosted platform launches. No spam, just a launch email.</p>
    <form class="waitlist-form" id="waitlist-{{ location }}"
      action="https://buttondown.com/api/emails/embed-subscribe/{{ site.newsletter.username }}"
      method="post">
      <label for="waitlist-email-{{ location }}" class="sr-only">Email address</label>
      <input type="email" name="email" id="waitlist-email-{{ location }}"
        placeholder="you@example.com" required autocomplete="email" inputmode="email"
        aria-describedby="waitlist-privacy-{{ location }}" />
      <input type="hidden" name="embed" value="1" />
      <input type="hidden" name="tag" value="pricing-waitlist" />
      <input type="hidden" name="metadata__tier_interest" value="{{ tier | default('hosted-pro') }}" />
      <div class="honeypot-trap" aria-hidden="true">
        <input type="text" name="url" tabindex="-1" autocomplete="off" />
      </div>
      <button type="submit" class="btn btn-primary">Join the Waitlist</button>
      <p id="waitlist-privacy-{{ location }}" class="newsletter-privacy">
        One email when we launch. Unsubscribe anytime.
        <a href="/pages/legal/privacy-policy/">Privacy Policy</a>
      </p>
      <div class="waitlist-status" aria-live="polite" role="status"></div>
    </form>
  </div>
</section>
```

Key decisions:

- Reuses `{{ site.newsletter.username }}` from `site.json` (same Buttondown account)
- The `tier` Nunjucks variable defaults to `hosted-pro`; pricing card CTAs can override it
- Reuses existing `.honeypot-trap` CSS class (already in `style.css` accessibility layer)
- Reuses `.newsletter-privacy` class for the privacy notice (same styling as newsletter)

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

#### 3. Form submission JavaScript (inline in `base.njk`)

Add a second `querySelectorAll` block after the existing newsletter handler in `base.njk` (line ~147). Reference implementation adapted from the newsletter pattern:

```javascript
document.querySelectorAll('.waitlist-form').forEach(function(form) {
  form.addEventListener('submit', function(e) {
    e.preventDefault();
    var btn = form.querySelector('button[type="submit"]');
    var status = form.querySelector('.waitlist-status');
    var tier = form.querySelector('input[name="metadata__tier_interest"]');
    btn.disabled = true;
    fetch(form.action, {
      method: 'POST',
      body: new FormData(form)
    }).then(function(res) {
      if (res.ok) {
        status.textContent = 'You are on the list! Check your email to confirm your spot.';
        status.className = 'waitlist-status waitlist-success';
        form.querySelector('input[type="email"]').value = '';
        if (window.plausible) plausible('Waitlist Signup', {
          props: { location: 'pricing-waitlist', tier: tier ? tier.value : 'unknown' }
        });
      } else {
        status.textContent = 'Something went wrong. Please try again.';
        status.className = 'waitlist-status waitlist-error';
      }
    }).catch(function() {
      status.textContent = 'Something went wrong. Please try again.';
      status.className = 'waitlist-status waitlist-error';
    }).finally(function() {
      btn.disabled = false;
    });
  });
});
```

Key differences from newsletter handler:

- Selector: `.waitlist-form`
- Plausible event name: `Waitlist Signup` (distinct from `Newsletter Signup`)
- Includes `tier` property in Plausible event props
- Success message sets expectation: "Check your email to confirm your spot"

#### 4. CSS additions (`plugins/soleur/docs/css/style.css`)

Minimal new CSS needed. Most styling is inherited from existing classes:

**Reuse directly (no new CSS):**

- `.honeypot-trap` -- already in accessibility layer (line 1244)
- `.newsletter-privacy` -- reuse for the privacy notice
- `.btn`, `.btn-primary` -- existing button styles

**New classes needed in the `@layer components` section (after `.newsletter-*` block, ~line 1070):**

```css
/* Waitlist signup form */
.waitlist-section {
  background: var(--color-bg-secondary);
  border-top: 2px solid var(--color-accent);
  border-bottom: 1px solid var(--color-border);
  padding: var(--space-8) 0;
  text-align: center;
}
.waitlist-section h2 {
  font-family: var(--font-display);
  font-size: var(--text-xl);
  color: var(--color-text);
  margin-bottom: var(--space-2);
}
.waitlist-section p {
  color: var(--color-text-secondary);
  margin-bottom: var(--space-4);
}
.waitlist-form {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
  align-items: center;
  justify-content: center;
  max-width: 480px;
  margin: 0 auto;
}
.waitlist-form input[type="email"] {
  flex: 1 1 220px;
  padding: var(--space-3) var(--space-4);
  background: var(--color-bg);
  border: 1px solid var(--color-border);
  border-radius: 4px;
  color: var(--color-text);
  font-size: var(--text-base);
}
.waitlist-form input[type="email"]:focus {
  outline: 2px solid var(--color-focus);
  outline-offset: 2px;
  border-color: var(--color-accent);
}
.waitlist-form input[type="email"]::placeholder {
  color: var(--color-text-tertiary);
}
.waitlist-form button[type="submit"] {
  cursor: pointer;
  border: none;
}
.waitlist-form button[type="submit"]:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.waitlist-status { font-size: var(--text-sm); margin-top: var(--space-2); width: 100%; }
.waitlist-success { color: var(--color-success, #22c55e); }
.waitlist-error { color: var(--color-error, #ef4444); }
```

The accent top-border on `.waitlist-section` visually differentiates it from the newsletter section. All custom properties (`--color-*`, `--font-*`, etc.) are from the existing token layer.

#### 5. Plausible analytics goal (`scripts/provision-plausible-goals.sh`)

Add the `Waitlist Signup` event goal to the existing provisioning script. Insert after line 137 (`provision_goal "event" "Newsletter Signup"`):

```bash
provision_goal "event" "Waitlist Signup"
```

The script uses Plausible's PUT `/api/v1/sites/goals` endpoint with upsert semantics (find-or-create), making it safe to re-run. After adding the line, run the script to provision the goal:

```bash
PLAUSIBLE_API_KEY=<key> PLAUSIBLE_SITE_ID=soleur.ai bash scripts/provision-plausible-goals.sh
```

Properties to track: `location` (always `pricing-waitlist`) and `tier` (e.g., `hosted-pro`). Plausible auto-discovers custom properties from event payloads -- no separate property registration is needed.

#### 6. Legal doc review

The privacy policy already covers Buttondown email collection (Section 4.6). Waitlist signup uses the same mechanism (email submitted to Buttondown with consent). Verify:

- The consent language in the waitlist form matches the privacy policy's description
- The `pricing-waitlist` tag does not constitute a new data category requiring policy update
- If tier interest metadata is stored, confirm it falls under the existing "subscription metadata" category

No new legal documents should be needed -- this is an additional use of an existing data processor for the same data type (email address) under the same legal basis (consent, Art. 6(1)(a)).

## Technical Considerations

### Buttondown API compatibility (confirmed)

The Buttondown embed-subscribe endpoint (`https://buttondown.com/api/emails/embed-subscribe/<username>`) accepts form-encoded POST data with these fields:

- `email` -- subscriber email (required)
- `tag` -- tag to apply; use `<input type="hidden" name="tag" value="pricing-waitlist">`. Multiple tags supported via multiple `<input name="tag">` elements.
- `metadata__<key>` -- custom metadata; use `<input type="hidden" name="metadata__tier_interest" value="solo">`. Keys follow the `metadata__` prefix convention.
- `embed` -- set to `1` for embed mode (matches existing newsletter pattern)
- `url` -- honeypot field (bots fill it; Buttondown rejects submissions with a non-empty `url` field)

**Source:** [Buttondown docs: Building your subscriber base](https://docs.buttondown.com/building-your-subscriber-base) -- confirmed 2026-03-25.

**Caching note:** New metadata keys (e.g., `tier_interest`) are cached for up to 1 hour before appearing in Buttondown's dashboard filters and subscriber detail pages. First submissions will store the data correctly but the key will not be filterable in the UI until the cache refreshes.

No authenticated API or server-side proxy is needed. The embed endpoint handles tags and metadata natively.

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

- [x] "Join the Waitlist" button on Hosted Pro card scrolls to the waitlist form section
- [x] Waitlist form captures email and submits to Buttondown with `pricing-waitlist` tag
- [x] Honeypot spam protection field is present and hidden
- [x] Successful submission shows confirmation message and clears the input
- [x] Failed submission shows error message
- [x] Plausible `Waitlist Signup` event fires on successful submission with `location: pricing-waitlist`
- [x] Form is accessible: labels, aria attributes, keyboard navigation, color contrast
- [x] Mobile responsive: form layout works on screens as narrow as 320px
- [x] Privacy notice with link to privacy policy appears below the form
- [x] Double opt-in confirmation email is sent by Buttondown
- [x] Legal docs reviewed -- no updates needed if existing coverage is sufficient

### Tier interest capture (included in MVP -- API confirmed)

Since Buttondown embed forms natively support `metadata__<key>` fields, tier interest capture requires no extra infrastructure:

- [x] Hidden `metadata__tier_interest` field in waitlist form with value from Nunjucks `tier` variable
- [x] Plausible event includes `tier` property (already in the JS handler above)

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
| ~~Buttondown embed endpoint does not accept `tag` param~~ | ~~Medium~~ | ~~Medium~~ | **Eliminated** -- confirmed via [Buttondown docs](https://docs.buttondown.com/building-your-subscriber-base): `<input name="tag">` is officially supported |
| ~~Buttondown embed endpoint does not accept `metadata` param~~ | ~~Medium~~ | ~~Low~~ | **Eliminated** -- confirmed via same docs: `<input name="metadata__<key>">` is officially supported |
| Metadata key not visible in Buttondown dashboard immediately | Medium | Low | Expected behavior: new metadata keys are cached for up to 1 hour. Document in implementation notes. |
| Double opt-in email looks like newsletter confirmation | Low | Low | Review Buttondown confirmation email customization settings |
| Form is mistaken for newsletter signup | Low | Medium | Distinct section heading ("Get early access to Hosted Pro"), accent border, and different copy differentiate it |
| Plausible Goals API returns 401 (Enterprise plan required) | Low | Low | Provisioning script handles 401 gracefully (exits 0 with skip message); goal can be created manually in dashboard |

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
- CSS styles: `plugins/soleur/docs/css/style.css:1021-1070` (newsletter), `1098-1216` (pricing), `1244` (honeypot-trap), `1252` (prefers-reduced-motion)
- Privacy policy: `plugins/soleur/docs/pages/legal/privacy-policy.md:93-101`
- Plausible goals provisioning: `scripts/provision-plausible-goals.sh:137` (add Waitlist Signup after Newsletter Signup)
- Learning -- PII collection legal pattern: `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`
- Learning -- Buttondown GDPR: `knowledge-base/project/learnings/2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md`
- Learning -- Plausible operationalization: `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md`
- Learning -- Plausible goals API provisioning: `knowledge-base/project/learnings/2026-03-13-plausible-goals-api-provisioning-hardening.md`
- Learning -- Adding docs pages pattern: `knowledge-base/project/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md`
- Learning -- Auto-fill grid mobile grouping: `knowledge-base/project/learnings/ui-bugs/2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile.md`

### External References (confirmed 2026-03-25)

- [Buttondown: Building your subscriber base](https://docs.buttondown.com/building-your-subscriber-base) -- tag and metadata embed form documentation
- [Buttondown: Subscribers API](https://docs.buttondown.com/api-subscribers-create) -- authenticated API reference (not needed for embed forms)
- [MDN: CSS scroll-behavior](https://developer.mozilla.org/en-US/docs/Web/CSS/scroll-behavior) -- baseline widely available since March 2022

### Related Issues

- Parent issue: [#656](https://github.com/jikig-ai/soleur/issues/656) -- Pricing page v2
- PR: [#1136](https://github.com/jikig-ai/soleur/pulls/1136) -- Pricing page v2 implementation (OPEN, WIP)
- This issue: [#1139](https://github.com/jikig-ai/soleur/issues/1139)
