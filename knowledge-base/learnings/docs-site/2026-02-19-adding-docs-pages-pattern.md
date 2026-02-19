---
title: Adding new pages to the Eleventy docs site
category: docs-site
module: docs
tags: [eleventy, docs-site, navigation, nunjucks]
date: 2026-02-19
severity: low
---

# Adding New Pages to the Eleventy Docs Site

## Problem

Need a repeatable pattern for adding new pages to the docs site at `plugins/soleur/docs/`.

## Solution

Three files to touch for a new page:

1. **Create the page** at `plugins/soleur/docs/pages/<name>.njk` with frontmatter:
   ```yaml
   ---
   title: Page Name
   description: "Page description for SEO."
   layout: base.njk
   permalink: pages/<name>.html
   ---
   ```

2. **Add to navigation** in `plugins/soleur/docs/_data/site.json`:
   - Add entry to `nav` array for header
   - Add entry to `footerLinks` array for footer (if desired)

3. **Template changes** (if needed): Edit `base.njk` only if hardcoded elements need removing (e.g., the GitHub/Discord links were hardcoded outside the `site.nav` loop).

## Key Insight

- The header nav has two sources: the `site.nav` data loop AND hardcoded elements after the loop. When adding a page that replaces hardcoded links, both must be updated.
- Reuse existing CSS classes (`.page-hero`, `.catalog-grid`, `.component-card`, `.category-section`) -- no custom styles needed for standard pages.
- Add new CSS classes to `style.css` in the `@layer components` block rather than using inline styles.
- The `_site_test/` directory from test builds was not gitignored -- added it alongside `_site/`.
- Run `npm install` in worktrees before building -- dependencies are not shared across worktrees.

## Tags
category: docs-site
module: docs
