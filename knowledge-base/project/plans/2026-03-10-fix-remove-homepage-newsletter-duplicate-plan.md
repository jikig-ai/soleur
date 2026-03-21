---
title: "fix: Remove duplicate newsletter signup from homepage"
type: fix
date: 2026-03-10
semver: patch
deepened: 2026-03-10
---

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 2 (Build Verification, Template Inheritance Analysis)
**Research sources:** Nunjucks block inheritance learning, Eleventy worktree build learning, base.njk template verification

### Key Improvements

1. Added worktree-safe verification alternative -- Eleventy build fails in worktrees due to relative path bug in `agents.js` (documented in `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md`); added grep-based source file verification as primary method
2. Verified template inheritance claim against actual `base.njk` source: `{% block content %}` ends at line 91, footer newsletter is at lines 94-95 -- confirmed outside the block
3. Confirmed `index.njk` does NOT use `{% block content %}` override -- its content flows through the default `{{ content | safe }}` rendering in the parent block, meaning the in-page newsletter is injected as body content while the footer newsletter renders independently

### New Considerations Discovered

- The `newsletter-form.njk` JS handler in `base.njk` (lines 118-146) uses `document.querySelectorAll('.newsletter-form').forEach(...)` -- reducing from 2 forms to 1 on the homepage means the forEach still works correctly (iterates over 1 element instead of 2)
- After this change, `newsletter-form.njk` has exactly one caller (`base.njk` line 95). The `location` variable and `id="newsletter-{{ location }}"` mechanism becomes single-use but is harmless to keep

---

# fix: Remove duplicate newsletter signup from homepage

The homepage (`index.njk`) renders two newsletter signup forms: one inline at lines 218-220 (with `location="homepage"`) and one in the footer via `base.njk` (lines 94-95, `location="footer"`). Since `index.njk` uses `layout: base.njk`, every homepage load gets both. The footer newsletter is visible on every page site-wide, making the homepage-specific one redundant. This is the same pattern fixed for blog posts in PR #525.

## Acceptance Criteria

- [x] Homepage renders exactly one newsletter signup form (the footer one from `base.njk`)
- [x] The footer newsletter form (`location="footer"`) continues to appear on all pages including the homepage
- [x] The `newsletter-form.njk` partial is not deleted (still used by `base.njk`)
- [x] No CSS changes needed (`.newsletter-section` styles remain for the footer instance)
- [x] Plausible analytics `Newsletter Signup` event with `location: footer` continues to fire on the homepage

## Test Scenarios

- Given the homepage, when the page loads, then exactly one newsletter form is visible (in the footer area, not inline in the page content)
- Given a blog post page, when the page loads, then only the footer newsletter form is present (no change from PR #525)
- Given any non-homepage page (e.g., Getting Started, Changelog), when the page loads, then only the footer newsletter form is present (no change)

### Build Verification

**Primary method (worktree-safe):** Verify source templates directly, since the Eleventy build fails in worktrees due to relative path resolution in `agents.js` (see `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md`):

```bash
# Verify index.njk no longer includes newsletter-form
grep -c 'newsletter-form' plugins/soleur/docs/index.njk
# Expected: 0

# Verify base.njk still includes footer newsletter
grep -c 'newsletter-form' plugins/soleur/docs/_includes/base.njk
# Expected: 2 (one include at line 95, one querySelectorAll in JS at line 118)

# Verify partial still exists
test -f plugins/soleur/docs/_includes/newsletter-form.njk && echo "OK"
```

**Secondary method (main repo only):** If running from the main checkout (not a worktree), build and verify HTML output:

```bash
cd plugins/soleur/docs && npx @11ty/eleventy --quiet
grep -c 'newsletter-form' _site/index.html
# Expected: 1 (footer only, not 2)
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

The `index.njk` template uses `layout: base.njk`. In `base.njk`, the newsletter include is at lines 94-95, which is OUTSIDE the `{% block content %}` block (that block ends at line 91 with `</main>`). Per the Nunjucks block inheritance pattern documented in `knowledge-base/project/learnings/2026-03-04-nunjucks-block-inheritance-with-content-safe.md`, content outside blocks renders unconditionally from the parent layout. Removing the newsletter from within the page content cannot affect the parent's footer newsletter.

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
- Existing blog newsletter plan: `knowledge-base/project/plans/2026-03-10-feat-remove-blog-newsletter-duplicate-plan.md`
- Newsletter implementation plan: `knowledge-base/project/plans/2026-03-10-feat-newsletter-email-capture-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-04-nunjucks-block-inheritance-with-content-safe.md` (confirms block inheritance safety)
- Learning: `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md` (worktree build limitation -- use source grep instead)
