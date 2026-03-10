---
title: "fix: Remove duplicate newsletter signup from homepage"
type: fix
date: 2026-03-10
semver: patch
---

# fix: Remove duplicate newsletter signup from homepage

The homepage (`index.njk`) renders two newsletter signup forms: one inline at lines 218-220 (with `location="homepage"`) and one in the footer via `base.njk` (lines 94-95, `location="footer"`). Since `index.njk` uses `layout: base.njk`, every homepage load gets both. The footer newsletter is visible on every page site-wide, making the homepage-specific one redundant. This is the same pattern fixed for blog posts in PR #525.

## Acceptance Criteria

- [ ] Homepage renders exactly one newsletter signup form (the footer one from `base.njk`)
- [ ] The footer newsletter form (`location="footer"`) continues to appear on all pages including the homepage
- [ ] The `newsletter-form.njk` partial is not deleted (still used by `base.njk`)
- [ ] No CSS changes needed (`.newsletter-section` styles remain for the footer instance)
- [ ] Plausible analytics `Newsletter Signup` event with `location: footer` continues to fire on the homepage

## Test Scenarios

- Given the homepage, when the page loads, then exactly one newsletter form is visible (in the footer area, not inline in the page content)
- Given a blog post page, when the page loads, then only the footer newsletter form is present (no change from PR #525)
- Given any non-homepage page (e.g., Getting Started, Changelog), when the page loads, then only the footer newsletter form is present (no change)

### Build Verification

After the edit, run an Eleventy build and verify HTML output:

```bash
cd plugins/soleur/docs && npx @11ty/eleventy --quiet
# Verify homepage has exactly one newsletter form
grep -c 'newsletter-form' _site/index.html
# Expected: 1 (footer only, not 2)

# Verify a non-blog page also has exactly one
grep -c 'newsletter-form' _site/pages/getting-started/index.html
# Expected: 1 (footer only)
```

## Implementation

### `plugins/soleur/docs/index.njk`

Remove lines 218-220:

```njk
    <!-- Newsletter CTA -->
    {% set location = "homepage" %}
    {% include "newsletter-form.njk" %}
```

This is the only file change required.

### Why This Is Safe (Template Inheritance Analysis)

The `index.njk` template uses `layout: base.njk`. In `base.njk`, the newsletter include is at lines 94-95, which is OUTSIDE the `{% block content %}` block (that block ends at line 91 with `</main>`). Per the Nunjucks block inheritance pattern documented in `knowledge-base/learnings/2026-03-04-nunjucks-block-inheritance-with-content-safe.md`, content outside blocks renders unconditionally from the parent layout. Removing the newsletter from within the page content cannot affect the parent's footer newsletter.

### Analytics Impact

Removing the homepage include eliminates the `location: homepage` analytics segment in Plausible. Homepage visitors will still see and can use the `location: footer` form. If granular homepage-specific conversion tracking is needed later, it can be re-added.

### Post-Change: `newsletter-form.njk` Usage

After this change, `newsletter-form.njk` is included only from `base.njk` (footer). If no other page-specific includes remain, the `location` variable mechanism becomes unnecessary but is harmless to keep for future flexibility.

## Non-goals

- Removing or refactoring `newsletter-form.njk` itself
- Removing the `location` variable mechanism from the partial
- Changing newsletter analytics tracking or the footer newsletter
- CSS cleanup (all newsletter styles are still needed for the footer instance)

## Context

This follows the same pattern as PR #525, which removed the duplicate newsletter from blog post pages. The PR #525 plan explicitly listed "The homepage newsletter form (`location="homepage"` in `index.njk` line 219-220) is unaffected" as an acceptance criterion, and "Removing the homepage newsletter form" as a non-goal. The user has now decided to remove the homepage duplicate as well.

### Files involved

| File | Action | Lines |
|------|--------|-------|
| `plugins/soleur/docs/index.njk` | Remove newsletter include | Lines 218-220 |

### Files NOT changed (verified)

| File | Reason |
|------|--------|
| `plugins/soleur/docs/_includes/base.njk` | Footer newsletter stays (lines 94-95, outside `{% block content %}`) |
| `plugins/soleur/docs/_includes/newsletter-form.njk` | Partial stays (used by base.njk) |
| `plugins/soleur/docs/css/style.css` | Newsletter CSS stays (used by footer instance) |

## References

- PR #525: Removed duplicate newsletter from blog post pages (same pattern)
- Existing blog newsletter plan: `knowledge-base/plans/2026-03-10-feat-remove-blog-newsletter-duplicate-plan.md`
- Newsletter implementation plan: `knowledge-base/plans/2026-03-10-feat-newsletter-email-capture-plan.md`
- Learning: `knowledge-base/learnings/2026-03-04-nunjucks-block-inheritance-with-content-safe.md` (confirms block inheritance safety)
