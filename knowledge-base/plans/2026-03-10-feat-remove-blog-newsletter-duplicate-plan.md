---
title: "feat: Remove duplicate newsletter signup from blog post pages"
type: feat
date: 2026-03-10
semver: patch
---

# feat: Remove duplicate newsletter signup from blog post pages

Blog post pages render two newsletter signup forms: one inline within the blog post content section (`blog-post.njk` line 53-54) and one in the footer via `base.njk` (line 94-95). Since `blog-post.njk` extends `base.njk`, every blog post page gets both. The footer newsletter is visible on every page site-wide, making the blog-specific one redundant and cluttering the reading experience.

## Acceptance Criteria

- [ ] Blog post pages render exactly one newsletter signup form (the footer one from `base.njk`)
- [ ] The footer newsletter form (`location="footer"`) continues to appear on all pages including blog posts
- [ ] The homepage newsletter form (`location="homepage"` in `index.njk` line 219-220) is unaffected
- [ ] The `newsletter-form.njk` partial is not deleted (still used by `base.njk` and `index.njk`)
- [ ] No CSS changes needed (`.newsletter-section` styles remain for footer and homepage instances)
- [ ] Plausible analytics `Newsletter Signup` event with `location: footer` continues to fire on blog pages

## Test Scenarios

- Given a blog post page, when the page loads, then exactly one newsletter form is visible (in the footer area, not in the article content section)
- Given the homepage, when the page loads, then both the in-page and footer newsletter forms are present (no change)
- Given any non-blog page (e.g., Getting Started, Changelog), when the page loads, then only the footer newsletter form is present (no change)

## Implementation

### `plugins/soleur/docs/_includes/blog-post.njk`

Remove lines 53-54:

```njk
    {% set location = "blog" %}
    {% include "newsletter-form.njk" %}
```

This is the only file change required. The `blog-post.njk` template extends `base.njk` which already includes `newsletter-form.njk` with `location="footer"` at line 94-95.

## Non-goals

- Removing the homepage newsletter form (that serves a different conversion purpose in the landing page flow)
- Removing or refactoring `newsletter-form.njk` itself
- Changing newsletter analytics tracking

## Context

The newsletter form was added in the `2026-03-10-feat-newsletter-email-capture-plan.md` implementation. The blog-specific include was likely added for conversion optimization, but since the footer already provides this on every page, it creates visual redundancy on blog posts specifically.

### Files involved

| File | Action | Lines |
|------|--------|-------|
| `plugins/soleur/docs/_includes/blog-post.njk` | Remove newsletter include | Lines 53-54 |

### Files NOT changed (verified)

| File | Reason |
|------|--------|
| `plugins/soleur/docs/_includes/base.njk` | Footer newsletter stays (line 94-95) |
| `plugins/soleur/docs/_includes/newsletter-form.njk` | Partial stays (used by base.njk, index.njk) |
| `plugins/soleur/docs/index.njk` | Homepage newsletter stays (line 219-220) |
| `plugins/soleur/docs/css/style.css` | Newsletter CSS stays (used by remaining instances) |

## References

- Existing newsletter plan: `knowledge-base/plans/2026-03-10-feat-newsletter-email-capture-plan.md`
- Learning: `knowledge-base/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`
