---
title: "feat: Remove duplicate newsletter signup from blog post pages"
type: feat
date: 2026-03-10
semver: patch
deepened: 2026-03-10
---

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 3 (Implementation, Test Scenarios, Context)
**Research sources:** Nunjucks block inheritance learning, Eleventy blog post pattern learning, template architecture analysis

### Key Improvements

1. Added Nunjucks template inheritance verification confirming the footer newsletter renders outside `{% block content %}` and is unaffected by child template overrides
2. Added build verification step to test scenarios (Eleventy build + HTML output grep)
3. Added analytics tracking consideration -- `location: blog` events will stop; confirmed this is acceptable since footer captures the same users

### New Considerations Discovered

- The `newsletter-form.njk` partial uses `location` variable for both HTML element IDs and Plausible analytics tracking -- removing the blog include eliminates the `location: blog` analytics segment (acceptable trade-off since footer captures the same audience)
- Nunjucks block inheritance means the footer newsletter (outside `{% block content %}`) renders independently of child template content -- no risk of accidentally removing the footer form

---

# feat: Remove duplicate newsletter signup from blog post pages

Blog post pages render two newsletter signup forms: one inline within the blog post content section (`blog-post.njk` line 53-54) and one in the footer via `base.njk` (line 94-95). Since `blog-post.njk` extends `base.njk`, every blog post page gets both. The footer newsletter is visible on every page site-wide, making the blog-specific one redundant and cluttering the reading experience.

## Acceptance Criteria

- [x] Blog post pages render exactly one newsletter signup form (the footer one from `base.njk`)
- [x] The footer newsletter form (`location="footer"`) continues to appear on all pages including blog posts
- [x] The homepage newsletter form (`location="homepage"` in `index.njk` line 219-220) is unaffected
- [x] The `newsletter-form.njk` partial is not deleted (still used by `base.njk` and `index.njk`)
- [x] No CSS changes needed (`.newsletter-section` styles remain for footer and homepage instances)
- [x] Plausible analytics `Newsletter Signup` event with `location: footer` continues to fire on blog pages

## Test Scenarios

- Given a blog post page, when the page loads, then exactly one newsletter form is visible (in the footer area, not in the article content section)
- Given the homepage, when the page loads, then both the in-page and footer newsletter forms are present (no change)
- Given any non-blog page (e.g., Getting Started, Changelog), when the page loads, then only the footer newsletter form is present (no change)

### Build Verification

After the edit, run an Eleventy build and verify HTML output:

```bash
cd plugins/soleur/docs && npx @11ty/eleventy --quiet
# Verify a blog post has exactly one newsletter form
grep -c 'newsletter-form' _site/blog/*/index.html
# Expected: 1 (footer only, not 2)

# Verify homepage still has two (in-page + footer)
grep -c 'newsletter-form' _site/index.html
# Expected: 2
```

## Implementation

### `plugins/soleur/docs/_includes/blog-post.njk`

Remove lines 53-54:

```njk
    {% set location = "blog" %}
    {% include "newsletter-form.njk" %}
```

This is the only file change required.

### Why This Is Safe (Template Inheritance Analysis)

The `blog-post.njk` template uses `layout: base.njk` and overrides `{% block content %}`. In `base.njk`, the newsletter include is at line 94-95, which is OUTSIDE the `{% block content %}` block (that block ends at line 91 with `</main>`). Per the Nunjucks block inheritance pattern documented in `knowledge-base/project/learnings/2026-03-04-nunjucks-block-inheritance-with-content-safe.md`, content outside blocks renders unconditionally from the parent layout. Removing the newsletter from inside `{% block content %}` in the child template cannot affect the parent's footer newsletter.

### Analytics Impact

The `newsletter-form.njk` partial tracks signups with Plausible using `location` as a property (line 134 of `base.njk`). Removing the blog include eliminates the `location: blog` analytics segment. Blog visitors will still see and can use the `location: footer` form. If granular blog-specific conversion tracking is needed later, it can be re-added.

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
| `plugins/soleur/docs/_includes/base.njk` | Footer newsletter stays (line 94-95, outside `{% block content %}`) |
| `plugins/soleur/docs/_includes/newsletter-form.njk` | Partial stays (used by base.njk, index.njk) |
| `plugins/soleur/docs/index.njk` | Homepage newsletter stays (line 219-220) |
| `plugins/soleur/docs/css/style.css` | Newsletter CSS stays (used by remaining instances) |

## References

- Existing newsletter plan: `knowledge-base/project/plans/2026-03-10-feat-newsletter-email-capture-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`
- Learning: `knowledge-base/project/learnings/2026-03-04-nunjucks-block-inheritance-with-content-safe.md` (confirms block inheritance safety)
- Learning: `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md` (blog template patterns)
