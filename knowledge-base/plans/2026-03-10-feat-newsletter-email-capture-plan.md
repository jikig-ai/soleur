---
title: feat: Newsletter Email Capture
type: feat
date: 2026-03-10
---

# feat: Newsletter Email Capture

## Overview

Add Buttondown-powered email signup forms to soleur.ai in three locations (site footer, homepage CTA, blog posts) with double opt-in, GDPR-compliant privacy notices, and legal document updates. This is Phase A (capture only) — no newsletter sends until Phase B triggers are met (100+ weekly visitors, 4+ published articles).

## Problem Statement / Motivation

The marketing strategy identifies email capture as a Medium-priority infrastructure blocker: "Email / newsletter: Does not exist. No way to capture or nurture leads." The site currently collects zero personal data. Adding email capture enables both validation outreach (Phase 2) and future content distribution (Phase 4).

## Proposed Solution

Embed Buttondown's signup form as a plain HTML `<form>` with minimal JavaScript for on-site submission UX. Buttondown handles double opt-in, subscriber management, and unsubscribe — no custom backend needed.

### Form HTML (core pattern)

```html
<form class="newsletter-form" id="newsletter-footer"
  action="https://buttondown.com/api/emails/embed-subscribe/{username}"
  method="post">
  <label for="newsletter-email-footer" class="sr-only">Email address</label>
  <input type="email" name="email" id="newsletter-email-footer"
    placeholder="you@example.com" required autocomplete="email" inputmode="email"
    aria-describedby="newsletter-privacy-footer" />
  <input type="hidden" name="embed" value="1" />
  <!-- Honeypot for bot protection -->
  <div style="position: absolute; left: -5000px;" aria-hidden="true">
    <input type="text" name="url" tabindex="-1" autocomplete="off" />
  </div>
  <button type="submit" class="btn btn-primary">Subscribe</button>
  <p id="newsletter-privacy-footer" class="newsletter-privacy">
    Monthly updates about Soleur. Unsubscribe anytime.
    <a href="/pages/legal/privacy-policy/">Privacy Policy</a>
  </p>
  <div class="newsletter-status" aria-live="polite" role="status"></div>
</form>
```

Each form instance uses unique `id` attributes (e.g., `newsletter-footer`, `newsletter-homepage`, `newsletter-blog`) to avoid duplicate ID conflicts on pages with multiple forms.

### JS submission (inline, ~30 lines)

```javascript
document.querySelectorAll('.newsletter-form').forEach(form => {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const status = form.querySelector('.newsletter-status');
    const email = form.querySelector('input[type="email"]').value;
    const location = form.id.replace('newsletter-', '');
    try {
      const res = await fetch(form.action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(new FormData(form))
      });
      if (res.ok) {
        status.textContent = 'Check your email to confirm your subscription.';
        status.className = 'newsletter-status newsletter-success';
        form.querySelector('input[type="email"]').value = '';
        if (window.plausible) plausible('Newsletter Signup', { props: { location } });
      } else {
        status.textContent = 'Something went wrong. Please try again.';
        status.className = 'newsletter-status newsletter-error';
      }
    } catch {
      status.textContent = 'Something went wrong. Please try again.';
      status.className = 'newsletter-status newsletter-error';
    }
  });
});
```

Works without JS (falls back to plain POST to Buttondown). Progressive enhancement.

## Technical Considerations

- **No backend needed.** Forms POST directly to Buttondown's API. JS fetch keeps users on-site.
- **Buttondown's free tier** covers Phase A (100 subscribers, no time limit). Upgrade at $9/mo when needed.
- **Double opt-in is Buttondown's default** — no configuration required for GDPR compliance.
- **Plain HTML form with no Buttondown JS/iframe** means zero cookies and zero tracking pixels on the host page.
- **Legal docs exist in 2 locations** with different frontmatter formats. Both must be updated in lockstep. Source: `docs/legal/`. Published: `plugins/soleur/docs/pages/legal/`.
- **This is the first PII collection on soleur.ai** — current legal docs claim "no personal data collection." All contradicting statements must be identified and updated.
- **Learnings to apply:**
  - Cookie-free analytics legal update pattern: update all GDPR-related docs in lockstep
  - GDPR Article 30: check ALL sections that reference processors, not just the one being updated
  - Legal doc bulk consistency: grep verification after editing to catch missed references
  - CSS variable: use `--color-accent` not `--accent` for gold
  - Build Eleventy from repo root: `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`

## Acceptance Criteria

- [ ] Buttondown account created and username configured in `site.json`
- [ ] Signup form in site footer (every page via `base.njk`)
- [ ] Signup form in homepage CTA section (`index.njk`)
- [ ] Signup form at end of blog posts (`blog-post.njk`)
- [ ] Double opt-in confirmation flow working (Buttondown default)
- [ ] Privacy notice with Privacy Policy link at each form
- [ ] Forms styled to match design system (dark bg, gold accent, responsive)
- [ ] Honeypot field for bot protection
- [ ] Accessible: labels, aria-describedby, autocomplete, keyboard navigation, screen reader announcements
- [ ] JS fetch keeps user on-site with inline success/error messages
- [ ] Graceful fallback to plain POST when JS disabled
- [ ] Plausible custom event tracks signups per placement
- [ ] Privacy Policy updated (both locations)
- [ ] GDPR Policy updated (both locations)
- [ ] Data Protection Disclosure updated (both locations)
- [ ] All legal doc contradictions resolved (grep verified)
- [ ] Eleventy build passes with no errors
- [ ] Responsive: form works at mobile and desktop breakpoints

## Test Scenarios

- Given a visitor on any page, when they scroll to the footer, then they see a newsletter signup form with email input and subscribe button
- Given a visitor on the homepage, when they scroll past FAQ, then they see a newsletter CTA section with signup form
- Given a visitor reading a blog post, when they reach the end, then they see a newsletter signup prompt
- Given a visitor, when they enter a valid email and click subscribe, then the form shows "Check your email to confirm" and the page does not navigate away
- Given a visitor, when they enter an invalid email and click subscribe, then HTML5 validation prevents submission
- Given a visitor with JS disabled, when they submit the form, then the browser POSTs to Buttondown (graceful degradation)
- Given a bot, when it fills all form fields including the honeypot, then Buttondown rejects the submission
- Given a visitor who is already subscribed, when they submit the same email, then they see a neutral confirmation message (no subscription status leak)
- Given a mobile visitor (< 768px), when they view the footer form, then it displays correctly in single-column layout
- Given a screen reader user, when they navigate to the form, then the label, privacy notice, and status messages are properly announced
- Given the Privacy Policy page, when a visitor reads Section 4, then newsletter email collection is documented
- Given the GDPR Policy Section 4.1, when a visitor reads it, then email addresses are no longer listed as "NOT collected"

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Buttondown lacks DPA/SCCs | Blocks launch — GDPR Chapter V violation | Verify before coding. Email DPO (justin@buttondown.email). Have backup plan (Loops). |
| Confirmation emails land in spam | Users can't complete double opt-in | Monitor deliverability. Add DNS records (DKIM/SPF) early if needed. |
| Legal doc contradictions missed | Compliance failure visible to users | Grep verification after all edits. Run legal-compliance-auditor agent. |
| 100-subscriber free tier limit hit quickly | Need to upgrade to $9/mo | Track subscriber count. Budget already assessed by COO ($34/mo total). |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-10-newsletter-brainstorm.md`
- Spec: `knowledge-base/specs/feat-newsletter/spec.md`
- Footer structure: `plugins/soleur/docs/_includes/base.njk:94-112`
- Homepage final CTA: `plugins/soleur/docs/index.njk:218-223`
- Blog post layout: `plugins/soleur/docs/_includes/blog-post.njk:48-54`
- CSS tokens: `plugins/soleur/docs/css/style.css:25-75`
- Site config: `plugins/soleur/docs/_data/site.json`
- Marketing strategy gap: `knowledge-base/overview/marketing-strategy.md`

### External References

- [Buttondown embed form docs](https://docs.buttondown.com/building-your-subscriber-base)
- [Buttondown double opt-in](https://docs.buttondown.com/glossary-double-optin)
- [Buttondown pricing](https://buttondown.com/pricing)
- [Buttondown GDPR compliance](https://docs.buttondown.com/gdpr-eu-compliance)
- [Buttondown privacy policy](https://buttondown.com/legal/privacy) — DPO: justin@buttondown.email

### Related Work

- Issue: #501
- PR: #512 (draft)

## Implementation Phases

### Phase 0: Prerequisites (Manual)

These are manual steps that must be completed before coding:

- [ ] 0.1 Create Buttondown account at buttondown.com
- [ ] 0.2 Note the username for embed form URL
- [ ] 0.3 Verify double opt-in is enabled (default — just confirm)
- [ ] 0.4 Email justin@buttondown.email to request DPA with SCCs
- [ ] 0.5 Verify Buttondown's EU-US data transfer mechanism (DPF or SCCs)
- [ ] 0.6 Add `"newsletter"` key to `plugins/soleur/docs/_data/site.json` with Buttondown username

### Phase 1: Legal Document Updates

Update all legal docs BEFORE the form goes live. Both source (`docs/legal/`) and published (`plugins/soleur/docs/pages/legal/`) copies.

- [ ] 1.1 Update Privacy Policy — add newsletter email collection section
  - `plugins/soleur/docs/pages/legal/privacy-policy.md` — Section 4.3 (Docs Site data), new Section 4.x (newsletter), Section 5 (third-party: Buttondown), Section 6 (legal basis: consent), Section 7 (retention)
  - `docs/legal/privacy-policy.md` — mirror changes with source frontmatter
- [ ] 1.2 Update GDPR Policy — add processing activity, fix contradictions
  - `plugins/soleur/docs/pages/legal/gdpr-policy.md` — Section 3 (new lawful basis: consent Art. 6(1)(a)), Section 4.1 (remove email from "NOT collected" list), Section 4.2 table (add Buttondown row), Section 10 (add processing activity #6 to Article 30 register)
  - `docs/legal/gdpr-policy.md` — mirror changes
- [ ] 1.3 Update Data Protection Disclosure — add Buttondown as processor
  - `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — Section 2.3 (add newsletter item), Section 4.2 table (add Buttondown row)
  - `docs/legal/data-processing-agreement.md` — mirror changes (note: filename differs)
- [ ] 1.4 Grep verification — search all legal docs for "does not collect", "no personal data", "email addresses" in negation context. Fix any remaining contradictions.
- [ ] 1.5 Run legal-compliance-auditor agent on all updated docs

### Phase 2: Form CSS

Build form styles from scratch in `@layer components` section of `style.css`.

- [ ] 2.1 Add newsletter form component styles to `plugins/soleur/docs/css/style.css`
  - `.newsletter-section` — full-width section with `--color-bg-secondary` background
  - `.newsletter-form` — flex layout (input + button inline on desktop, stacked on mobile)
  - Input styling: `--color-bg-tertiary` background, `--color-border` border, `--color-text` text, `--color-accent` focus ring
  - Submit button: reuse `.btn .btn-primary` pattern
  - `.newsletter-privacy` — `--color-text-tertiary`, small font
  - `.newsletter-success` / `.newsletter-error` — status message colors
  - Responsive: stack at `max-width: 768px`

### Phase 3: Form HTML Templates

- [ ] 3.1 Add Nunjucks partial: `plugins/soleur/docs/_includes/newsletter-form.njk`
  - Accepts `location` parameter for unique IDs
  - Reads Buttondown username from `site.newsletter` data
  - Includes honeypot, privacy notice, status area
- [ ] 3.2 Add pre-footer newsletter section to `plugins/soleur/docs/_includes/base.njk`
  - Insert between `</main>` (line 93) and `<footer>` (line 94)
  - Include partial with `location="footer"`
- [ ] 3.3 Add newsletter CTA section to `plugins/soleur/docs/index.njk`
  - Insert before the Final CTA section (line 218)
  - Brand-aligned heading and copy
  - Include partial with `location="homepage"`
- [ ] 3.4 Add newsletter CTA to `plugins/soleur/docs/_includes/blog-post.njk`
  - Insert after `{{ content | safe }}` (line 52), before closing `</section>`
  - Include partial with `location="blog"`

### Phase 4: JavaScript and Tracking

- [ ] 4.1 Add inline `<script>` to `base.njk` — JS fetch handler (~30 lines)
  - Progressive enhancement: forms work without JS
  - Inline success/error messages via `aria-live` status region
  - Plausible custom event: `plausible('Newsletter Signup', { props: { location } })`
- [ ] 4.2 Add `newsletter` key to `site.json` with Buttondown username

### Phase 5: Build Verification

- [ ] 5.1 Run Eleventy build: `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`
- [ ] 5.2 Visual check: footer form on all pages, homepage CTA, blog post CTA
- [ ] 5.3 Mobile responsive check at 375px and 768px breakpoints
- [ ] 5.4 Accessibility check: keyboard navigation, screen reader labels, focus states
- [ ] 5.5 Test form submission with real Buttondown account
- [ ] 5.6 Verify JS-disabled fallback (disable JS, submit form)
- [ ] 5.7 Verify legal doc links from privacy notices resolve correctly
