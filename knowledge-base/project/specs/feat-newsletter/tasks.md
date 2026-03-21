# Tasks: Newsletter Email Capture

## Phase 1: Prerequisites (Manual)

- [x] 1.1 Create Buttondown account at buttondown.com
- [x] 1.2 Verify double opt-in is enabled (default)
- [ ] 1.3 Request DPA with SCCs from <justin@buttondown.email>
- [ ] 1.4 Confirm EU-US data transfer mechanism
- [x] 1.5 Add `"newsletter"` key to `plugins/soleur/docs/_data/site.json` with Buttondown username

## Phase 2: Legal Updates

- [x] 2.1 Update Privacy Policy — new Section 4.6 "Newsletter Subscription Data", Buttondown in Section 5, consent in Section 6, retention in Section 7
  - [x] 2.1.1 Published: `plugins/soleur/docs/pages/legal/privacy-policy.md`
  - [x] 2.1.2 Source: `docs/legal/privacy-policy.md`
- [x] 2.2 Update GDPR Policy — consent (Art. 6(1)(a)) as Section 3.6, fix Section 3.4/3.5 numbering, remove email from "NOT collected" in 4.1, Buttondown in 4.2, processing activity #6 in Section 10
  - [x] 2.2.1 Published: `plugins/soleur/docs/pages/legal/gdpr-policy.md`
  - [x] 2.2.2 Source: `docs/legal/gdpr-policy.md`
- [x] 2.3 Update Data Protection Disclosure — newsletter in Section 2.3, Buttondown in 4.2
  - [x] 2.3.1 Published: `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  - [x] 2.3.2 Source: `docs/legal/data-protection-disclosure.md`
- [x] 2.4 Verify Cookie Policy — confirm Buttondown form POST sets no cookies; update if it does
- [x] 2.5 Grep verification — "does not collect", "no personal data", negated "email" references

## Phase 3: Implementation

- [x] 3.1 Add newsletter form CSS to `plugins/soleur/docs/css/style.css` (`@layer components` + `.honeypot-trap` in `@layer utilities`)
- [x] 3.2 Create Nunjucks partial `plugins/soleur/docs/_includes/newsletter-form.njk` with `location` parameter
- [x] 3.3 Include partial in `base.njk` — pre-footer section between `</main>` and `<footer>`, `location="footer"`
- [x] 3.4 Include partial in `index.njk` — new section before `<!-- Final CTA -->`, `location="homepage"`
- [x] 3.5 Include partial in `blog-post.njk` — after `.prose` closing `</div>` (not inside `.prose`), `location="blog"`
- [x] 3.6 Add inline `<script>` to `base.njk` — JS fetch handler with button disable and Plausible tracking
- [x] 3.7 Run Eleventy build and verify all form placements
