---
title: "refactor: Remove CaaS hero badge from landing page"
type: refactor
date: 2026-02-26
---

# refactor: Remove CaaS hero badge from landing page

Remove the "The Company-as-a-Service Platform" pill badge from the landing page hero section. The badge duplicates positioning that is covered in depth on the vision page, in `llms.txt`, in `site.json` tagline, and across all legal documents. Removing it declutters the hero and lets the h1 headline ("Build a Billion-Dollar Company. Alone.") land without preamble.

## Acceptance Criteria

- [ ] The `.hero-badge` div (lines 10-13 of `plugins/soleur/docs/index.njk`) is deleted
- [ ] Hero top padding changed from `var(--space-12)` (128px) to `var(--space-10)` (80px) in `plugins/soleur/docs/css/style.css` line 407
- [ ] The `.landing-hero .hero-badge` CSS rule block (lines 410-420) is deleted
- [ ] The `.hero-badge-dot` CSS rule block (lines 421-427) is deleted
- [ ] The frontmatter `description` in `index.njk` line 3 is preserved unchanged (SEO meta tag still references CaaS)
- [ ] No other files are modified -- `site.json` tagline, `llms.txt`, vision page, and legal pages retain CaaS references
- [ ] Version bump in `plugin.json`, `CHANGELOG.md`, and `README.md` (PATCH -- cosmetic docs change)

## Test Scenarios

- Given the landing page is loaded, when the hero section renders, then no badge/pill appears above the h1
- Given the hero section, when inspecting top padding, then `padding-top` resolves to 80px (--space-10) not 128px
- Given the CSS file, when searching for `hero-badge`, then zero matches are found
- Given the frontmatter of `index.njk`, when inspecting `description`, then it still contains "The company-as-a-service platform"
- Given all three responsive breakpoints (mobile <= 768px, tablet 769-1024px, desktop > 1024px), when viewing the hero, then vertical spacing looks intentional with no excessive gap above the h1

## Context

### Files to Edit

| File | Change |
|------|--------|
| `plugins/soleur/docs/index.njk` | Delete lines 10-13 (`.hero-badge` div) |
| `plugins/soleur/docs/css/style.css` | Line 407: `--space-12` to `--space-10`; delete lines 410-427 (badge CSS) |
| `plugins/soleur/plugin.json` | Patch version bump |
| `plugins/soleur/CHANGELOG.md` | Add entry |
| `plugins/soleur/README.md` | Update version |

### CaaS Positioning Retained Elsewhere

The "Company-as-a-Service" phrase remains in 10+ locations across the docs site:

- `index.njk` frontmatter `description` (SEO meta tag)
- `site.json` tagline
- `llms.txt` (LLM-facing site description)
- `pages/vision.njk` (h2 title + body text)
- 5 legal documents (terms, cookie policy, AUP, GDPR, disclaimer, privacy)

No SEO or positioning loss.

### Relevant Learnings

- **Landing page grid orphan regression** (`knowledge-base/learnings/2026-02-22-landing-page-grid-orphan-regression.md`): When modifying landing page layout, verify all responsive breakpoints. The hero section has no grid, but padding changes should be visually checked at mobile/tablet/desktop.
- **Docs site CSS variable inconsistency** (`knowledge-base/learnings/2026-02-22-docs-site-css-variable-inconsistency.md`): Use `--color-accent` not `--accent`. Not directly relevant here but good to be aware of when touching the CSS file.

## MVP

### plugins/soleur/docs/index.njk (lines 8-14, after edit)

```njk
    <!-- Hero -->
    <section class="landing-hero">
      <h1>Build a Billion-Dollar Company. Alone.</h1>
```

### plugins/soleur/docs/css/style.css (lines 404-410, after edit)

```css
  /* Landing page: Hero */
  .landing-hero {
    margin-top: var(--header-h);
    padding: var(--space-10) var(--space-5) var(--space-10);
    text-align: center;
  }
  .landing-hero h1 {
```

## References

- Vision page with full CaaS positioning: `plugins/soleur/docs/pages/vision.njk`
- Landing page template: `plugins/soleur/docs/index.njk`
- Landing page styles: `plugins/soleur/docs/css/style.css`
