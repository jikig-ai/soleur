---
title: "feat: redesign footer link layout after legal links addition"
type: feat
date: 2026-04-02
semver: patch
---

# Redesign Footer Link Layout After Legal Links Addition

Closes #1410

## Overview

The docs site footer currently renders 9 links in a single flat `<ul>` row: Get Started, Pricing, Blog, Community, Vision, About, Legal, Privacy Policy, Terms of Service. After the legal links were added, the footer feels cluttered with three legal-related links appearing inline alongside navigation links. The footer needs a cleaner layout that visually separates navigation links from legal links.

## Problem Statement

The current footer layout in `plugins/soleur/docs/_includes/base.njk` iterates over `site.footerLinks` from `plugins/soleur/docs/_data/site.json` and renders all 9 links in a single horizontal `<ul class="footer-links">`. This creates two problems:

1. **Visual clutter**: 9 links of equal visual weight compete for attention on a single row
2. **No semantic grouping**: Legal links (Legal, Privacy Policy, Terms of Service) appear inline alongside product navigation links (Get Started, Pricing, Blog, etc.), making the footer harder to scan

The footer layout on mobile (below 768px) already wraps to `flex-direction: column`, but on desktop the single row becomes too wide.

## Proposed Solution

Adopt a **two-row footer layout** that separates primary navigation links from legal links:

- **Row 1 (primary)**: Get Started, Pricing, Blog, Community, Vision, About -- the main site navigation links rendered at current `--text-xs` size
- **Row 2 (legal)**: Legal, Privacy Policy, Terms of Service -- rendered in a smaller/muted style with `--text-xs` font and `--color-text-tertiary` color, visually subordinate to primary links

This approach:

- Reduces the primary link count from 9 to 6, removing clutter
- Creates a clear visual hierarchy -- legal links are present but not competing with navigation
- Requires minimal code changes: split `footerLinks` into two arrays in `site.json`, add a second `<ul>` in `base.njk`, and add a small CSS class
- Preserves all existing links (nothing removed)
- Works naturally with the existing mobile responsive behavior

### Why Not a Single "Legal" Link?

A single "Legal" link pointing to the hub page (`pages/legal.html`) would reduce the footer to 7 links, but:

- Privacy Policy and Terms of Service are the two most commonly accessed legal pages (users expect direct footer access per web convention)
- GDPR compliance recommendations suggest making the Privacy Policy directly accessible from every page
- The existing Legal hub page (`pages/legal.html`) already serves as a comprehensive index of all 9 legal documents

The two-row approach keeps Privacy Policy and Terms of Service directly accessible while visually de-emphasizing them.

## Technical Approach

### Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/docs/_data/site.json` | Split `footerLinks` into `footerNav` (6 links) and `footerLegal` (3 links) |
| `plugins/soleur/docs/_includes/base.njk` | Add second `<ul class="footer-legal">` loop for legal links |
| `plugins/soleur/docs/css/style.css` | Add `.footer-legal` styles in `@layer components` footer section |

### Implementation

#### Phase 1: Data Structure (`site.json`)

Replace the single `footerLinks` array with two arrays:

```json
"footerNav": [
  { "label": "Get Started", "url": "pages/getting-started.html" },
  { "label": "Pricing", "url": "pages/pricing.html" },
  { "label": "Blog", "url": "blog/" },
  { "label": "Community", "url": "pages/community.html" },
  { "label": "Vision", "url": "pages/vision.html" },
  { "label": "About", "url": "about/" }
],
"footerLegal": [
  { "label": "Legal", "url": "pages/legal.html" },
  { "label": "Privacy Policy", "url": "pages/legal/privacy-policy.html" },
  { "label": "Terms of Service", "url": "pages/legal/terms-and-conditions.html" }
]
```

#### Phase 2: Template (`base.njk`)

Update the footer section to render two link groups:

```html
<ul class="footer-links">
  {%- for link in site.footerNav %}
  <li><a href="{{ link.url }}">{{ link.label }}</a></li>
  {%- endfor %}
</ul>
<ul class="footer-legal">
  {%- for link in site.footerLegal %}
  <li><a href="{{ link.url }}">{{ link.label }}</a></li>
  {%- endfor %}
</ul>
```

#### Phase 3: Styles (`style.css`)

Add `.footer-legal` in the existing footer section within `@layer components`:

```css
.footer-legal {
  display: flex;
  gap: var(--space-4);
  list-style: none;
}
.footer-legal a {
  font-size: var(--text-xs);
  color: var(--color-text-tertiary);
}
.footer-legal a:hover { color: var(--color-text-secondary); }
```

The `.footer-inner` flex layout already handles spacing between children. The legal links row will appear as a natural additional element in the footer's flex container. On mobile (below 768px), the existing `flex-direction: column` rule on `.footer-inner` will stack both link rows vertically.

#### Phase 4: Verify and Test

- Build docs site locally with `npx @11ty/eleventy` to verify no broken links
- Visual check at desktop (1200px+), tablet (769-1024px), and mobile (below 768px) breakpoints
- Verify all 9 footer links still render and point to correct URLs

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Single "Legal" link to hub page | Reduces to 7 links, simplest change | Hides Privacy Policy and ToS behind a click, deviates from web convention, GDPR recommends direct access | Rejected |
| Delimiter/separator between nav and legal links | Minimal code change | Still one row, just adds a visual break -- does not address the density issue | Rejected |
| Multi-column footer grid | Professional look for large sites | Overengineered for 9 links, adds significant CSS complexity | Rejected |
| Smaller font for legal links only (same row) | Minimal change | Mixed font sizes in one row looks inconsistent | Rejected |

## Acceptance Criteria

- [ ] Footer renders primary navigation links (Get Started, Pricing, Blog, Community, Vision, About) in the main link row
- [ ] Footer renders legal links (Legal, Privacy Policy, Terms of Service) in a visually distinct secondary row
- [ ] Legal links use `--color-text-tertiary` color (not `--color-text-secondary` like nav links)
- [ ] Legal links hover to `--color-text-secondary` (not full white like nav links)
- [ ] Footer layout stacks correctly on mobile (below 768px)
- [ ] All 9 links point to the correct URLs (no broken links)
- [ ] Eleventy build completes without errors
- [ ] Update learning file `knowledge-base/project/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md` to reference `footerNav`/`footerLegal` instead of `footerLinks`
- [ ] No other functional references to `site.footerLinks` exist (`.pen` files and archived plans are documentation-only)

## Test Scenarios

- Given the docs site footer, when viewed on desktop (1200px+), then primary nav links appear in one row and legal links appear in a separate subordinate row below
- Given the docs site footer, when viewed on mobile (below 768px), then all footer elements stack vertically with proper spacing
- Given any footer link, when clicked, then the correct page loads (no 404s)
- Given the legal links row, when inspected, then color is `--color-text-tertiary` (not `--color-text-secondary`)

## Domain Review

**Domains relevant:** Marketing, Product

### Marketing

**Status:** reviewed
**Assessment:** The footer layout change is a minor visual improvement with no brand impact. The footer links themselves are unchanged -- only their visual grouping changes. No marketing content, messaging, or brand positioning is affected. The change aligns with clean, minimal brand aesthetics by reducing visual noise.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

This is a layout refinement to an existing footer component. The change improves information hierarchy by visually separating navigation from legal links. No new user flows, pages, or components are introduced.

## Non-Goals

- Redesigning the full footer layout (adding columns, newsletter section restructure, etc.)
- Changing the footer link destinations or adding/removing pages
- Modifying the mobile responsive behavior beyond inheriting existing column stacking

## References

- Current footer template: `plugins/soleur/docs/_includes/base.njk` (lines 129-149)
- Footer data: `plugins/soleur/docs/_data/site.json` (lines 29-39, `footerLinks` array)
- Footer CSS: `plugins/soleur/docs/css/style.css` (lines 739-788, footer section in `@layer components`)
- Mobile responsive rules: `plugins/soleur/docs/css/style.css` (lines 955-956, footer column layout)
- Legal hub page: `plugins/soleur/docs/pages/legal.njk`
- Related issue: #1410
- Learning: `knowledge-base/project/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md` (docs page patterns, reuse existing CSS classes)
