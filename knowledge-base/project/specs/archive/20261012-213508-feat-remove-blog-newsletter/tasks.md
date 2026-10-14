# Tasks: Remove duplicate newsletter signup from blog post pages

## Phase 1: Implementation

- [ ] 1.1 Remove newsletter include from blog-post.njk
  - Remove `{% set location = "blog" %}` (line 53)
  - Remove `{% include "newsletter-form.njk" %}` (line 54)
  - File: `plugins/soleur/docs/_includes/blog-post.njk`

## Phase 2: Verification

- [ ] 2.1 Build docs site and verify blog post pages
  - Run `npx @11ty/eleventy` to build
  - Verify blog post HTML output contains exactly one newsletter form (footer)
- [ ] 2.2 Verify homepage newsletter unaffected
  - Check `index.html` output still contains homepage newsletter form
- [ ] 2.3 Verify footer newsletter present on all pages
  - Check that `base.njk` footer newsletter include is intact
- [ ] 2.4 Run compound and commit
