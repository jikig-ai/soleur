---
title: "feat: add X/Twitter (@soleur_ai) links to website and brand guide"
type: feat
date: 2026-03-10
semver: patch
---

# feat: Add X/Twitter (@soleur_ai) Links to Website and Brand Guide

## Overview

The `@soleur_ai` X account was provisioned in #474 and the backend integration is complete (x-setup.sh, x-community.sh, community SKILL.md). However, the public-facing docs site and brand guide were not updated to surface the new X/Twitter presence. This issue tracks closing that marketing/docs gap.

Closes #480

## Problem Statement / Motivation

Users visiting the Soleur website have no way to discover the X/Twitter account. The community page lists only Discord and GitHub in the Connect section. The brand guide's X/Twitter voice section references tone and format but does not specify the canonical handle. The footer lacks social icon links entirely. This creates a discoverability gap between the backend capability (posting to X) and the public-facing surfaces.

## Proposed Solution

Four targeted edits to existing files -- no new files, no new dependencies, no new CSS classes beyond minimal additions to the existing component layer.

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
    <span class="card-dot" style="background: #000000"></span>
    <span class="card-category">Social</span>
  </div>
  <h3 class="card-title">X / Twitter</h3>
  <p class="card-description">Follow @soleur_ai for updates, threads on building with AI, and announcements.</p>
</a>
```

**Grid impact:** The `catalog-grid` uses `grid-template-columns: repeat(auto-fill, minmax(300px, 1fr))`. Three cards flow cleanly at desktop (3 columns at 1200px container), tablet (2+1), and mobile (1 column). No orphan card issue.

**Card dot color:** `#000000` for X's brand color (black on dark background has low contrast -- alternative: `#E7E9EA` which is X's light theme text color, or the brand gold `var(--color-accent)`). Decision: use `#E7E9EA` for visibility on the dark background.

### 3. `plugins/soleur/docs/_includes/base.njk` -- Add `twitter:site` Meta Tag

Add `twitter:site` meta tag after the existing Twitter Card meta tags to associate the site with the @soleur_ai handle:

```html
<meta name="twitter:site" content="@soleur_ai">
```

This improves Twitter Card attribution when links are shared on X.

### 4. `knowledge-base/overview/brand-guide.md` -- Specify Handle

Add the canonical handle to the X/Twitter Channel Notes section. Insert after the "### X/Twitter" heading and before the bullet list:

```markdown
**Handle:** [@soleur_ai](https://x.com/soleur_ai)
```

### 5. (Optional) Footer Social Icons in `plugins/soleur/docs/_includes/base.njk`

Add social icon links (Discord, GitHub, X) to the footer between `footer-links` and `footer-tagline`. Use Unicode/text labels rather than SVG icons to avoid adding image assets:

```html
<div class="footer-social">
  <a href="{{ site.discord }}" target="_blank" rel="noopener" aria-label="Discord">Discord</a>
  <a href="{{ site.github }}" target="_blank" rel="noopener" aria-label="GitHub">GitHub</a>
  <a href="{{ site.x }}" target="_blank" rel="noopener" aria-label="X / Twitter">X</a>
</div>
```

With minimal CSS in `style.css` under `@layer components`:

```css
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

**Decision point:** The footer currently has `footer-left` (logo), `footer-links` (nav), and `footer-tagline`. Adding social links is a nice-to-have but increases footer complexity. Recommend including it since it follows existing patterns and the CSS is minimal.

## Technical Considerations

- **Path correction:** Issue #480 references `docs/_data/site.json` but the actual path is `plugins/soleur/docs/_data/site.json`. Same for all docs paths. The plan uses correct paths throughout.
- **No SVG icons:** The site currently uses no SVG icon library. Adding one for three social icons is overhead. Text labels or Unicode characters are sufficient and consistent with the existing pattern (the logo mark is a text "S", not an SVG).
- **Card dot color:** X's brand guidelines specify black, but on a `#141414` surface card, `#000000` is nearly invisible. Use `#E7E9EA` (X's light-mode text color) for contrast.
- **No new data files:** The `site.json` already holds `github` and `discord` URLs. Adding `x` follows the established pattern.
- **Responsive behavior:** All changes use existing CSS classes (`catalog-grid`, `community-card-link`, `footer-*`). No responsive breakpoint changes needed.

## Acceptance Criteria

- [ ] `plugins/soleur/docs/_data/site.json` contains `"x": "https://x.com/soleur_ai"`
- [ ] Community page Connect section shows three cards: Discord, X/Twitter, GitHub
- [ ] X/Twitter card links to `https://x.com/soleur_ai` with `target="_blank" rel="noopener"`
- [ ] `base.njk` includes `<meta name="twitter:site" content="@soleur_ai">`
- [ ] `brand-guide.md` specifies `@soleur_ai` handle in the X/Twitter section
- [ ] Footer contains social links for Discord, GitHub, and X
- [ ] Docs site builds without errors (`npx @11ty/eleventy`)
- [ ] All three community cards render correctly at desktop (>1024px), tablet (769-1024px), and mobile (<768px) breakpoints

## Test Scenarios

- Given a user visits the community page, when they look at the Connect section, then they see three cards (Discord, X/Twitter, GitHub) with working external links
- Given a user shares a Soleur page on X, when the card preview renders, then it shows `@soleur_ai` as the site attribution
- Given a user views the footer on any page, when they look for social links, then they see Discord, GitHub, and X links
- Given a developer reads brand-guide.md, when they look at the X/Twitter section, then they find the canonical handle `@soleur_ai`
- Given the docs site is built with Eleventy, when all changes are applied, then the build completes with zero errors

## Non-Goals

- Adding SVG social icons or an icon library
- Redesigning the footer layout
- Adding X feed embed or timeline widget
- Automating X post previews on the docs site
- Changing existing Discord or GitHub card content

## Dependencies and Risks

- **No external dependencies.** All changes are to existing files with existing patterns.
- **Risk: X brand compliance.** X's brand guidelines restrict use of the old Twitter bird logo. Using text "X / Twitter" avoids trademark issues entirely.
- **Risk: Card dot color choice.** The `#E7E9EA` color for the X card dot differs from the brand's black. This is a pragmatic visibility choice on a dark background.

## References

- Issue: #480
- X provisioning PR: #474
- Community skill: `plugins/soleur/skills/community/SKILL.md`
- X provisioning learning: `knowledge-base/learnings/2026-03-09-x-provisioning-playwright-automation.md`
- Brand guide: `knowledge-base/overview/brand-guide.md` (lines 150-163, X/Twitter section)
- Site data: `plugins/soleur/docs/_data/site.json`
- Community page: `plugins/soleur/docs/pages/community.njk`
- Base template: `plugins/soleur/docs/_includes/base.njk`
- Stylesheet: `plugins/soleur/docs/css/style.css`
