---
title: "feat: add X/Twitter (@soleur_ai) links to website and brand guide"
type: feat
date: 2026-03-10
semver: patch
---

# feat: Add X/Twitter (@soleur_ai) Links to Website and Brand Guide

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5
**Research sources:** 6 institutional learnings, CSS grid analysis, Nunjucks template review, Twitter Card meta tag best practices

### Key Improvements

1. Added grid orphan analysis with breakpoint verification checklist (from landing-page-grid-orphan-regression learning)
2. Added Eleventy build command correction -- must build from repo root, not docs directory (from build-errors learning)
3. Added CSS variable consistency check -- use `--color-*` tokens, not shorthand `--accent` (from docs-site-css-variable learning)
4. Added `twitter:creator` meta tag alongside `twitter:site` for author attribution
5. Promoted footer social links from "optional" to "included" -- minimal CSS, high discoverability value

### Institutional Learnings Applied

- `2026-02-22-landing-page-grid-orphan-regression` -- grid divisibility rule at all breakpoints
- `2026-02-22-docs-site-css-variable-inconsistency` -- use `var(--color-accent)` not `var(--accent)`
- `docs-site/2026-02-19-adding-docs-pages-pattern` -- add CSS to `@layer components`, reuse existing classes
- `build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas` -- build from repo root
- `2026-03-04-nunjucks-block-inheritance-with-content-safe` -- block inheritance pattern
- `2026-02-26-worktree-missing-node-modules-silent-hang` -- `npm install` before building in worktree

## Overview

The `@soleur_ai` X account was provisioned in #474 and the backend integration is complete (x-setup.sh, x-community.sh, community SKILL.md). However, the public-facing docs site and brand guide were not updated to surface the new X/Twitter presence. This issue tracks closing that marketing/docs gap.

Closes #480

## Problem Statement / Motivation

Users visiting the Soleur website have no way to discover the X/Twitter account. The community page lists only Discord and GitHub in the Connect section. The brand guide's X/Twitter voice section references tone and format but does not specify the canonical handle. The footer lacks social icon links entirely. This creates a discoverability gap between the backend capability (posting to X) and the public-facing surfaces.

## Proposed Solution

Five targeted edits to existing files -- no new files, no new dependencies, no new CSS classes beyond minimal additions to the existing component layer.

### 1. `plugins/soleur/docs/_data/site.json` -- Add X URL

Add an `"x"` key alongside the existing `"github"` and `"discord"` URLs:

```json
{
  "github": "https://github.com/jikig-ai/soleur",
  "discord": "https://discord.gg/PYZbPBKMUY",
  "x": "https://x.com/soleur_ai"
}
```

This makes the URL available as `{{ site.x }}` in all Nunjucks templates, consistent with `{{ site.discord }}` and `{{ site.github }}`.

### 2. `plugins/soleur/docs/pages/community.njk` -- Add X/Twitter Card

Add a third card to the Connect section's `catalog-grid`, between the existing Discord and GitHub cards:

```html
<a href="{{ site.x }}" target="_blank" rel="noopener" class="component-card community-card-link">
  <div class="card-header">
    <span class="card-dot" style="background: #E7E9EA"></span>
    <span class="card-category">Social</span>
  </div>
  <h3 class="card-title">X / Twitter</h3>
  <p class="card-description">Follow @soleur_ai for updates, threads on building with AI, and announcements.</p>
</a>
```

#### Research Insights: Grid Divisibility

The `catalog-grid` uses `grid-template-columns: repeat(auto-fill, minmax(300px, 1fr))`. Unlike the landing page's fixed-column grids (`repeat(3, 1fr)`), `auto-fill` adapts to container width. Breakpoint analysis:

| Viewport | Container Width | Columns | Cards | Remainder | Status |
|----------|----------------|---------|-------|-----------|--------|
| Desktop (>1024px) | ~1200px | 3 | 3 | 0 | Clean |
| Tablet (769-1024px) | ~900px | 2 | 3 | 1 | 2+1 orphan |
| Mobile (<768px) | ~360px | 1 | 3 | 0 | Clean |

The tablet breakpoint produces a 2+1 layout. However, this is the existing behavior for the Getting Help section (which already has 3 cards in a `catalog-grid`), so it is a known and accepted pattern for this grid type -- `auto-fill` orphans are visually acceptable because each card is self-contained (unlike fixed grids where visual grouping matters). No CSS changes needed.

**Card dot color:** `#E7E9EA` (X's light-mode text color) for visibility on the `#141414` card surface. `#000000` is nearly invisible on dark backgrounds. The inline style is acceptable here -- the existing Discord (`#5865F2`) and GitHub (`#F0F0F0`) cards both use inline `style="background: ..."` for their dots.

### 3. `plugins/soleur/docs/_includes/base.njk` -- Add Twitter Card Meta Tags

Add two meta tags after the existing Twitter Card tags (after line 21):

```html
<meta name="twitter:site" content="@soleur_ai">
<meta name="twitter:creator" content="@soleur_ai">
```

- `twitter:site` -- associates the website with the @soleur_ai account. When a link is shared on X, the card preview attributes the content to this account.
- `twitter:creator` -- identifies the content author. Since Soleur is a single-founder project, both site and creator are the same handle. This is standard practice and adds the "by @soleur_ai" attribution to card previews.

### 4. `knowledge-base/overview/brand-guide.md` -- Specify Handle

Add the canonical handle to the X/Twitter Channel Notes section. Insert after the `### X/Twitter` heading (line 150) and before the first bullet:

```markdown
**Handle:** [@soleur_ai](https://x.com/soleur_ai)
```

This makes the handle discoverable for any agent or human reading the brand guide for X/Twitter voice guidance.

### 5. Footer Social Icons in `plugins/soleur/docs/_includes/base.njk`

Add social icon links (Discord, GitHub, X) to the footer between `footer-links` and `footer-tagline`. Use text labels rather than SVG icons to avoid adding image assets:

```html
<div class="footer-social">
  <a href="{{ site.discord }}" target="_blank" rel="noopener" aria-label="Discord">Discord</a>
  <a href="{{ site.github }}" target="_blank" rel="noopener" aria-label="GitHub">GitHub</a>
  <a href="{{ site.x }}" target="_blank" rel="noopener" aria-label="X / Twitter">X</a>
</div>
```

With minimal CSS in `style.css` under `@layer components` (insert after the existing `.community-text a` rule, around line 331):

```css
/* Footer social links */
.footer-social {
  display: flex;
  gap: var(--space-4);
}
.footer-social a {
  font-size: var(--text-xs);
  color: var(--color-text-secondary);
  text-decoration: none;
}
.footer-social a:hover { color: var(--color-text); }
```

#### Research Insights: Footer Responsive Behavior

The `.footer-inner` is a flex container with `justify-content: space-between`. At mobile (`max-width: 768px`), it switches to `flex-direction: column; text-align: center`. The `footer-social` div will naturally stack vertically at mobile as a flex child. No additional responsive CSS needed.

The insertion order in the HTML matters for the stacking order: `footer-left` > `footer-links` > `footer-social` > `footer-tagline`. Social links appear between navigation and the tagline, which is the standard pattern (navigation first, then social, then branding).

## Technical Considerations

- **Path correction:** Issue #480 references `docs/_data/site.json` but the actual path is `plugins/soleur/docs/_data/site.json`. Same for all docs paths. The plan uses correct paths throughout.
- **No SVG icons:** The site currently uses no SVG icon library. Adding one for three social icons is overhead. Text labels are consistent with the existing pattern (the logo mark is a text "S", not an SVG).
- **Card dot color:** X's brand guidelines specify black, but on a `#141414` surface card, `#000000` is nearly invisible. Use `#E7E9EA` (X's light-mode text color) for contrast. This matches the pragmatic approach taken for GitHub's dot (`#F0F0F0` instead of GitHub's true black).
- **No new data files:** The `site.json` already holds `github` and `discord` URLs. Adding `x` follows the established pattern.
- **Responsive behavior:** All changes use existing CSS classes (`catalog-grid`, `community-card-link`, `footer-*`). No responsive breakpoint changes needed.
- **CSS variable consistency:** Use full token names (`--color-text-secondary`, `--color-accent`) per the docs-site-css-variable learning. Never use shorthand like `--accent`.
- **Build from repo root:** Run `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site` from the repository root, not from the docs directory (Eleventy v3 passthrough copy resolves paths from project root).
- **Worktree build prerequisite:** Run `npm install` in the worktree before building -- worktrees do not share `node_modules/` with the main working tree and missing dependencies cause silent hangs.

## Acceptance Criteria

- [x] `plugins/soleur/docs/_data/site.json` contains `"x": "https://x.com/soleur_ai"`
- [x] Community page Connect section shows three cards: Discord, X/Twitter, GitHub
- [x] X/Twitter card links to `https://x.com/soleur_ai` with `target="_blank" rel="noopener"`
- [x] X/Twitter card dot uses `#E7E9EA` (not `#000000`)
- [x] `base.njk` includes `<meta name="twitter:site" content="@soleur_ai">`
- [x] `base.njk` includes `<meta name="twitter:creator" content="@soleur_ai">`
- [x] `brand-guide.md` specifies `@soleur_ai` handle in the X/Twitter section
- [x] Footer contains social links for Discord, GitHub, and X on all pages
- [x] Footer social links use `--color-text-secondary` token (not shorthand)
- [x] Docs site builds without errors (`npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`)
- [ ] All three community cards render correctly at desktop (>1024px), tablet (769-1024px), and mobile (<768px) breakpoints

## Test Scenarios

- Given a user visits the community page, when they look at the Connect section, then they see three cards (Discord, X/Twitter, GitHub) with working external links
- Given a user shares a Soleur page on X, when the card preview renders, then it shows `@soleur_ai` as the site attribution
- Given a user views the footer on any page, when they look for social links, then they see Discord, GitHub, and X links
- Given a developer reads brand-guide.md, when they look at the X/Twitter section, then they find the canonical handle `@soleur_ai`
- Given the docs site is built with Eleventy, when all changes are applied, then the build completes with zero errors
- Given a user views the community page at tablet width (769-1024px), when they look at the Connect section, then the three cards display in a 2+1 layout (consistent with the Getting Help section's existing 3-card behavior)

## Non-Goals

- Adding SVG social icons or an icon library
- Redesigning the footer layout
- Adding X feed embed or timeline widget
- Automating X post previews on the docs site
- Changing existing Discord or GitHub card content

## Dependencies and Risks

- **No external dependencies.** All changes are to existing files with existing patterns.
- **Risk: X brand compliance.** X's brand guidelines restrict use of the old Twitter bird logo. Using text "X / Twitter" avoids trademark issues entirely.
- **Risk: Card dot color choice.** The `#E7E9EA` color for the X card dot differs from the brand's black. This is a pragmatic visibility choice on a dark background, consistent with the GitHub card's approach (`#F0F0F0`).

## References

- Issue: #480
- X provisioning PR: #474
- Community skill: `plugins/soleur/skills/community/SKILL.md`
- X provisioning learning: `knowledge-base/project/learnings/2026-03-09-x-provisioning-playwright-automation.md`
- Grid orphan learning: `knowledge-base/project/learnings/2026-02-22-landing-page-grid-orphan-regression.md`
- CSS variable learning: `knowledge-base/project/learnings/2026-02-22-docs-site-css-variable-inconsistency.md`
- Adding pages learning: `knowledge-base/project/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md`
- Eleventy build learning: `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md`
- Brand guide: `knowledge-base/overview/brand-guide.md` (lines 150-163, X/Twitter section)
- Site data: `plugins/soleur/docs/_data/site.json`
- Community page: `plugins/soleur/docs/pages/community.njk`
- Base template: `plugins/soleur/docs/_includes/base.njk`
- Stylesheet: `plugins/soleur/docs/css/style.css`
