# Tasks: Newsletter Email Capture

## Phase 0: Prerequisites (Manual)

- [ ] 0.1 Create Buttondown account at buttondown.com
- [ ] 0.2 Note username for embed form URL
- [ ] 0.3 Verify double opt-in is enabled (default)
- [ ] 0.4 Email justin@buttondown.email to request DPA with SCCs
- [ ] 0.5 Verify EU-US data transfer mechanism (DPF or SCCs)
- [ ] 0.6 Add `"newsletter"` key to `plugins/soleur/docs/_data/site.json`

## Phase 1: Legal Document Updates

- [ ] 1.1 Update Privacy Policy (published): `plugins/soleur/docs/pages/legal/privacy-policy.md`
  - [ ] 1.1.1 Add newsletter email collection to Section 4.3 (Docs Site data)
  - [ ] 1.1.2 Add Buttondown to Section 5 (Third-Party Services)
  - [ ] 1.1.3 Add consent basis to Section 6 (Legal Basis)
  - [ ] 1.1.4 Add newsletter retention to Section 7 (Data Retention)
- [ ] 1.2 Update Privacy Policy (source): `docs/legal/privacy-policy.md` — mirror 1.1
- [ ] 1.3 Update GDPR Policy (published): `plugins/soleur/docs/pages/legal/gdpr-policy.md`
  - [ ] 1.3.1 Add consent lawful basis (Art. 6(1)(a)) to Section 3
  - [ ] 1.3.2 Remove email from "NOT collected" list in Section 4.1
  - [ ] 1.3.3 Add Buttondown row to Section 4.2 table
  - [ ] 1.3.4 Add processing activity #6 to Section 10 (Article 30 register)
- [ ] 1.4 Update GDPR Policy (source): `docs/legal/gdpr-policy.md` — mirror 1.3
- [ ] 1.5 Update Data Protection Disclosure (published): `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  - [ ] 1.5.1 Add newsletter to Section 2.3 limited processing list
  - [ ] 1.5.2 Add Buttondown row to Section 4.2 table
- [ ] 1.6 Update Data Protection Disclosure (source): `docs/legal/data-processing-agreement.md` — mirror 1.5
- [ ] 1.7 Grep verification: search for "does not collect", "no personal data", negated "email" references
- [ ] 1.8 Run legal-compliance-auditor agent on updated docs

## Phase 2: Form CSS

- [ ] 2.1 Add newsletter component styles to `plugins/soleur/docs/css/style.css` in `@layer components`
  - [ ] 2.1.1 `.newsletter-section` — full-width section styling
  - [ ] 2.1.2 `.newsletter-form` — flex layout (inline desktop, stacked mobile)
  - [ ] 2.1.3 Email input styles (bg, border, focus ring, placeholder)
  - [ ] 2.1.4 Status message styles (`.newsletter-success`, `.newsletter-error`)
  - [ ] 2.1.5 `.newsletter-privacy` — small text styling
  - [ ] 2.1.6 Responsive breakpoint (max-width: 768px)

## Phase 3: Form HTML Templates

- [ ] 3.1 Create Nunjucks partial: `plugins/soleur/docs/_includes/newsletter-form.njk`
  - [ ] 3.1.1 Parameterized `location` for unique IDs
  - [ ] 3.1.2 Email input with label, honeypot, hidden embed field
  - [ ] 3.1.3 Privacy notice with Policy link
  - [ ] 3.1.4 Status area with `aria-live="polite"`
- [ ] 3.2 Add pre-footer newsletter section to `plugins/soleur/docs/_includes/base.njk`
- [ ] 3.3 Add newsletter CTA section to `plugins/soleur/docs/index.njk`
- [ ] 3.4 Add newsletter CTA to `plugins/soleur/docs/_includes/blog-post.njk`

## Phase 4: JavaScript and Tracking

- [ ] 4.1 Add inline `<script>` to `base.njk` with fetch handler
- [ ] 4.2 Add Plausible custom event tracking per form location

## Phase 5: Build Verification

- [ ] 5.1 Run Eleventy build successfully
- [ ] 5.2 Visual check: footer on all pages, homepage CTA, blog post CTA
- [ ] 5.3 Mobile responsive check (375px, 768px)
- [ ] 5.4 Accessibility check (keyboard nav, screen reader, focus states)
- [ ] 5.5 Test form submission with Buttondown account
- [ ] 5.6 Verify JS-disabled fallback
- [ ] 5.7 Verify legal doc links resolve correctly
