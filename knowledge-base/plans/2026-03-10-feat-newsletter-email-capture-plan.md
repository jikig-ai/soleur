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

### Form HTML (core pattern, Nunjucks)

```html
<form class="newsletter-form" id="newsletter-{{ location }}"
  action="https://buttondown.com/api/emails/embed-subscribe/{{ site.newsletter.username }}"
  method="post">
  <label for="newsletter-email-{{ location }}" class="sr-only">Email address</label>
  <input type="email" name="email" id="newsletter-email-{{ location }}"
    placeholder="you@example.com" required autocomplete="email" inputmode="email"
    aria-describedby="newsletter-privacy-{{ location }}" />
  <input type="hidden" name="embed" value="1" />
  <div class="honeypot-trap" aria-hidden="true">
    <input type="text" name="url" tabindex="-1" autocomplete="off" />
  </div>
  <button type="submit" class="btn btn-primary">Subscribe</button>
  <p id="newsletter-privacy-{{ location }}" class="newsletter-privacy">
    Monthly updates about Soleur. Unsubscribe anytime.
    <a href="/pages/legal/privacy-policy/">Privacy Policy</a>
  </p>
  <div class="newsletter-status" aria-live="polite" role="status"></div>
</form>
```

Each form instance uses unique `id` attributes via the `location` parameter (`footer`, `homepage`, `blog`) to avoid duplicate ID conflicts on pages with multiple forms.

### JS submission (inline, ~35 lines)

```javascript
document.querySelectorAll('.newsletter-form').forEach(form => {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('button[type="submit"]');
    const status = form.querySelector('.newsletter-status');
    const location = form.id.replace('newsletter-', '');
    btn.disabled = true;
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
    } catch (err) {
      status.textContent = 'Something went wrong. Please try again.';
      status.className = 'newsletter-status newsletter-error';
    } finally {
      btn.disabled = false;
    }
  });
});
```

Works without JS (falls back to plain POST to Buttondown). Progressive enhancement.

## Technical Considerations

- **No backend needed.** Forms POST directly to Buttondown's API. JS fetch keeps users on-site.
- **Buttondown's free tier** covers Phase A (100 subscribers, no time limit). Upgrade at $9/mo when needed.
- **Double opt-in is Buttondown's default** — no configuration required for GDPR compliance.
- **Plain HTML form with no Buttondown JS/iframe** means zero cookies and zero tracking pixels on the host page. Verify with DevTools after deploy.
- **Legal docs exist in 2 locations** with different frontmatter formats. Both must be updated in lockstep. Source: `docs/legal/`. Published: `plugins/soleur/docs/pages/legal/`.
- **This is the first PII collection on soleur.ai** — current legal docs claim "no personal data collection." All contradicting statements must be identified and updated.
- **CSP check:** If the site has Content-Security-Policy headers (via GitHub Pages or Cloudflare), `connect-src` must include `https://buttondown.com` or the fetch will be blocked.
- **Learnings to apply:**
  - Cookie-free analytics legal update pattern: update all GDPR-related docs in lockstep
  - GDPR Article 30: check ALL sections that reference processors, not just the one being updated
  - Legal doc bulk consistency: grep verification after editing to catch missed references
  - CSS variable: use `--color-accent` not `--accent` for gold
  - Build Eleventy from repo root: `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`

## Acceptance Criteria

- [ ] Signup form appears in site footer, homepage CTA section, and end of blog posts
- [ ] Form submits via JS fetch with inline success/error messages (falls back to plain POST without JS)
- [ ] Forms styled to match design system (dark bg, gold accent, responsive at mobile/desktop)
- [ ] Privacy notice with Privacy Policy link at each form
- [ ] Privacy Policy, GDPR Policy, and Data Protection Disclosure updated (both locations each)
- [ ] No legal doc contradictions remain (grep verified: "does not collect", "no personal data", negated "email")
- [ ] Plausible custom event fires on successful signup
- [ ] Eleventy build passes with no errors

## Test Scenarios

- Given a visitor, when they submit a valid email, then the form shows "Check your email to confirm" and the page does not navigate away
- Given a visitor with JS disabled, when they submit the form, then the browser POSTs to Buttondown (graceful degradation)
- Given a visitor on a mobile device (< 768px), when they view any form, then it displays correctly in single-column layout
- Given the homepage, when it renders, then two distinct newsletter forms exist (CTA section + footer) without duplicate HTML IDs
- Given a visitor who clicks Subscribe twice quickly, then the button is disabled during the fetch and only one request is sent
- Given the GDPR Policy, when a visitor reads it, then email addresses are no longer listed as "NOT collected" and a newsletter processing activity exists in the Article 30 register

## Prerequisites

Verify Buttondown offers a DPA with SCCs before proceeding. Email DPO (justin@buttondown.email). If they cannot provide adequate GDPR transfer mechanism, evaluate Loops as backup.

- [ ] Create Buttondown account at buttondown.com
- [ ] Verify double opt-in is enabled (default)
- [ ] Request DPA with SCCs from justin@buttondown.email
- [ ] Confirm EU-US data transfer mechanism
- [ ] Add `"newsletter"` key to `plugins/soleur/docs/_data/site.json` with Buttondown username

## Legal Updates

Update all legal docs BEFORE the form goes live. Both source (`docs/legal/`) and published (`plugins/soleur/docs/pages/legal/`) copies. Legal updates and form code ship in the same PR.

- [ ] **Privacy Policy** — add new Section 4.6 "Newsletter Subscription Data" (not in 4.3 which is analytics-specific). Add Buttondown to Section 5 (Third-Party Services), consent basis to Section 6, retention to Section 7. Mirror to `docs/legal/privacy-policy.md`.
- [ ] **GDPR Policy** — add consent lawful basis (Art. 6(1)(a)) as Section 3.6. Remove email from "NOT collected" list in Section 4.1. Add Buttondown row to Section 4.2 table. Add processing activity #6 to Section 10 (Article 30 register). Fix pre-existing Section 3.4/3.5 numbering while editing. Mirror to `docs/legal/gdpr-policy.md`.
- [ ] **Data Protection Disclosure** — add newsletter to Section 2.3 limited processing list. Add Buttondown row to Section 4.2 table. Mirror to `docs/legal/data-processing-agreement.md` (note: filename differs from published version).
- [ ] **Cookie Policy** — verify Buttondown form POST does not set cookies. If it does, update Cookie Policy (both locations).
- [ ] **Grep verification** — search all legal docs for "does not collect", "no personal data", "email addresses" in negation context. Fix any remaining contradictions.

## Implementation

All done in a single pass — CSS, HTML partial, template includes, JS.

- [ ] Add `.newsletter-form` component styles and `.honeypot-trap` utility to `plugins/soleur/docs/css/style.css` in `@layer components` / `@layer utilities`, using existing design tokens
- [ ] Create Nunjucks partial `plugins/soleur/docs/_includes/newsletter-form.njk` with `location` parameter for unique IDs, reading username from `site.newsletter`
- [ ] Include partial in `plugins/soleur/docs/_includes/base.njk` — insert as a pre-footer section between the `</main>` closing tag and the `<footer>` element, with `location="footer"`
- [ ] Include partial in `plugins/soleur/docs/index.njk` — insert as a new section before the `<!-- Final CTA -->` comment, with `location="homepage"`
- [ ] Include partial in `plugins/soleur/docs/_includes/blog-post.njk` — insert after the `.prose` closing `</div>` (not inside `.prose` to avoid typography styles), with `location="blog"`
- [ ] Add inline `<script>` to `base.njk` with JS fetch handler, button disable during submit, and Plausible event tracking
- [ ] Run Eleventy build and verify all three form placements render correctly

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-10-newsletter-brainstorm.md`
- Spec: `knowledge-base/specs/feat-newsletter/spec.md`
- Issue: #501 | PR: #512 (draft)
- Footer: `plugins/soleur/docs/_includes/base.njk` (between `</main>` and `<footer>`)
- Homepage CTA: `plugins/soleur/docs/index.njk` (before `<!-- Final CTA -->`)
- Blog post: `plugins/soleur/docs/_includes/blog-post.njk` (after `.prose` div)
- CSS: `plugins/soleur/docs/css/style.css` (`@layer components`)
- Site config: `plugins/soleur/docs/_data/site.json`
- [Buttondown embed docs](https://docs.buttondown.com/building-your-subscriber-base) | [Buttondown GDPR](https://docs.buttondown.com/gdpr-eu-compliance)
