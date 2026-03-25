# Tasks: Waitlist Signup Form for Pricing Page

Issue: #1139 | Plan: `knowledge-base/project/plans/2026-03-25-feat-waitlist-signup-form-plan.md`

## Phase 1: Setup & Verification

- [ ] 1.1 Verify Buttondown embed endpoint accepts `tag` parameter via manual test (POST to `https://buttondown.com/api/emails/embed-subscribe/soleur` with `tag=pricing-waitlist`)
- [ ] 1.2 Verify Buttondown embed endpoint accepts `metadata` parameter (for tier interest capture)
- [ ] 1.3 Create Plausible `Waitlist Signup` custom event goal (via API or Plausible dashboard)

## Phase 2: Core Implementation

- [ ] 2.1 Create `plugins/soleur/docs/_includes/waitlist-form.njk` -- email input, honeypot, hidden tag field, submit button, privacy notice, status area
- [ ] 2.2 Update `plugins/soleur/docs/pages/pricing.njk`:
  - [ ] 2.2.1 Replace disabled `<button>` on Hosted Pro card with `<a href="#waitlist">` scroll link
  - [ ] 2.2.2 Add waitlist form section (`<section id="waitlist">`) before Final CTA
  - [ ] 2.2.3 Include `waitlist-form.njk` with `location = "pricing-waitlist"`
- [ ] 2.3 Add waitlist form submission JS to `plugins/soleur/docs/_includes/base.njk`:
  - [ ] 2.3.1 Selector: `.waitlist-form`
  - [ ] 2.3.2 POST to Buttondown embed-subscribe with `pricing-waitlist` tag
  - [ ] 2.3.3 Fire Plausible `Waitlist Signup` event on success
  - [ ] 2.3.4 Show success/error messages in status area
- [ ] 2.4 Add CSS styles to `plugins/soleur/docs/css/style.css`:
  - [ ] 2.4.1 `.waitlist-section` styles (adapt from `.newsletter-section`)
  - [ ] 2.4.2 `.waitlist-form` layout styles
  - [ ] 2.4.3 `.waitlist-status`, `.waitlist-success`, `.waitlist-error` classes
  - [ ] 2.4.4 Mobile responsive breakpoint at 768px

## Phase 3: Legal & Analytics Verification

- [ ] 3.1 Review privacy policy Section 4.6 -- confirm waitlist email collection is covered under existing Buttondown description
- [ ] 3.2 Verify double opt-in confirmation email is sent by Buttondown for waitlist subscribers
- [ ] 3.3 Confirm `Waitlist Signup` event appears in Plausible after a test submission

## Phase 4: Enhancement (Optional, Can Defer)

- [ ] 4.1 Add tier interest capture: hidden `metadata__tier_interest` field in waitlist form
- [ ] 4.2 Pass tier name from pricing card CTA to form via URL fragment or query parameter
- [ ] 4.3 Include `tier` property in Plausible event props

## Phase 5: Testing

- [ ] 5.1 Test form submission with valid email -- confirm Buttondown receives it with correct tag
- [ ] 5.2 Test honeypot rejection -- submit with honeypot field filled
- [ ] 5.3 Test network error handling -- disconnect and verify error message
- [ ] 5.4 Test mobile layout at 320px width
- [ ] 5.5 Test keyboard navigation and screen reader accessibility
- [ ] 5.6 Test CTA scroll behavior from Hosted Pro card to form
