# Tasks: Waitlist Signup Form for Pricing Page

Issue: #1139 | Plan: `knowledge-base/project/plans/2026-03-25-feat-waitlist-signup-form-plan.md`

## Phase 1: Setup

- [ ] 1.1 Add `Waitlist Signup` event goal to `scripts/provision-plausible-goals.sh` (line ~138, after `Newsletter Signup`)
- [ ] 1.2 Run provisioning script: `PLAUSIBLE_API_KEY=<key> PLAUSIBLE_SITE_ID=soleur.ai bash scripts/provision-plausible-goals.sh`

> **Note:** Buttondown embed API confirmed to support `<input name="tag">` and `<input name="metadata__<key>">` natively. No verification step needed -- [source](https://docs.buttondown.com/building-your-subscriber-base).

## Phase 2: Core Implementation

- [ ] 2.1 Create `plugins/soleur/docs/_includes/waitlist-form.njk`:
  - [ ] 2.1.1 Email input with label, placeholder, required, autocomplete="email"
  - [ ] 2.1.2 Hidden fields: `embed=1`, `tag=pricing-waitlist`, `metadata__tier_interest={{ tier | default('hosted-pro') }}`
  - [ ] 2.1.3 Honeypot trap (reuse `.honeypot-trap` class from style.css:1244)
  - [ ] 2.1.4 Submit button, privacy notice (reuse `.newsletter-privacy` class), status area
- [ ] 2.2 Update `plugins/soleur/docs/pages/pricing.njk`:
  - [ ] 2.2.1 Replace disabled `<button>` on Hosted Pro card with `<a href="#waitlist" class="btn btn-secondary pricing-card-cta">Join the Waitlist</a>`
  - [ ] 2.2.2 Add `<section id="waitlist" class="landing-section">` before Final CTA, include `waitlist-form.njk` with `location = "pricing-waitlist"`
- [ ] 2.3 Add waitlist form submission JS to `plugins/soleur/docs/_includes/base.njk` (after newsletter handler, ~line 147):
  - [ ] 2.3.1 `.waitlist-form` selector, POST via `new FormData(form)` to Buttondown embed endpoint
  - [ ] 2.3.2 Fire `plausible('Waitlist Signup', { props: { location: 'pricing-waitlist', tier: tierValue } })` on success
  - [ ] 2.3.3 Success: "You are on the list! Check your email to confirm your spot." / Error: "Something went wrong. Please try again."
- [ ] 2.4 Add CSS to `plugins/soleur/docs/css/style.css` (after `.newsletter-*` block, ~line 1070):
  - [ ] 2.4.1 `.waitlist-section` with accent top border (`border-top: 2px solid var(--color-accent)`)
  - [ ] 2.4.2 `.waitlist-form` flex layout (mirrors `.newsletter-form`)
  - [ ] 2.4.3 `.waitlist-status`, `.waitlist-success`, `.waitlist-error` status classes

## Phase 3: Verification

- [ ] 3.1 Review privacy policy Section 4.6 -- confirm waitlist email collection is covered under existing Buttondown description (expected: no updates needed)
- [ ] 3.2 Test form submission with valid email -- confirm Buttondown receives it with `pricing-waitlist` tag and `tier_interest` metadata
- [ ] 3.3 Verify double opt-in confirmation email is sent by Buttondown
- [ ] 3.4 Confirm `Waitlist Signup` event appears in Plausible after test submission

## Phase 4: Testing

- [ ] 4.1 Test CTA scroll behavior from Hosted Pro card to `#waitlist` section (smooth scroll via existing `html { scroll-behavior: smooth }`)
- [ ] 4.2 Test honeypot rejection -- submit with honeypot field filled
- [ ] 4.3 Test network error handling -- disconnect and verify error message and button re-enable
- [ ] 4.4 Test mobile layout at 320px width -- no horizontal scroll, form usable
- [ ] 4.5 Test keyboard navigation: Tab through form fields, Enter to submit
- [ ] 4.6 Test screen reader: verify aria-live status announcements
