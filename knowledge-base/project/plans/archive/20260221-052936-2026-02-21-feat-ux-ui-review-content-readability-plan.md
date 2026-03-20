---
title: "feat: UX/UI review -- content readability and header logo"
type: feat
date: 2026-02-21
---

# feat: UX/UI review -- content readability and header logo

## Overview

Add a `.prose` CSS utility class for comfortable reading width and vertical rhythm on long-form content pages (changelog, legal, getting started, vision). Add the gold S logo mark image to the site header alongside the "Soleur" wordmark. Fix changelog styling by applying `.prose` plus changelog-specific overrides via `#changelog-content`.

## Problem Statement / Motivation

The soleur.ai documentation site has three readability issues:

1. **Header uses plain text** -- just "Soleur" in bold Inter. The gold S circle logo mark (`logo-mark-512.png`) exists but is unused.
2. **Long-form content is too wide** -- legal pages, changelog, getting started, and vision prose stretch to the full 1200px container. Optimal reading width is ~75ch.
3. **Changelog is unstyled** -- `.changelog-entry` CSS exists but markdown-it generates plain HTML without those classes, so styles never apply.

## Proposed Solution

**Single `.prose` CSS class** added to the `@layer components` section of `style.css`. Applied via template markup to all long-form content pages. Header gets an `<img>` tag for the logo mark.

This is the simplest approach -- one class definition reused across all pages rather than per-page scoped styles or a new template layout.

## Technical Considerations

- `.community-text` already uses `max-width: 65ch` -- `.prose` uses `75ch` for wider reading lanes on dedicated content pages
- Getting Started page mixes prose sections with grid components (`.quickstart-code`, `.commands-list`) -- wrap individual markdown prose sections in `<div class="prose">` / `</div>` pairs so grids stay full-width
- Vision page already has `65ch` via `.community-text` -- needs `margin-bottom` added to `.community-text` for paragraph spacing
- Logo image needs explicit `width`/`height` attributes for CLS prevention and `alt=""` since the adjacent text serves as the accessible name
- CSS reset has `img { display: block }` -- the logo `<img>` inside the flex `.logo` container needs an explicit size to work as a flex child (HTML attributes handle this)
- Mobile: `75ch` exceeds narrow viewports but `max-width` naturally caps at available width -- no media query needed

## Acceptance Criteria

- [x] Header displays ~24px gold S logo mark next to "Soleur" text on all pages
- [x] Logo mark has `width="24" height="24" alt=""` attributes
- [x] Long-form content (changelog, legal, getting started) capped at `max-width: 75ch`
- [x] Proper vertical spacing between headings, paragraphs, and lists in `.prose` content
- [x] Changelog h2/h3/ul have clear spacing via `.prose` + `#changelog-content` overrides
- [x] Vision prose paragraphs have proper paragraph margin
- [x] All 7 legal pages styled (privacy-policy, terms-and-conditions, cookie-policy, acceptable-use-policy, data-protection-disclosure, disclaimer, gdpr-policy)
- [x] No layout breakage on mobile viewports
- [x] Existing card grids, hero sections, and nav remain unchanged

## Test Scenarios

- Given the homepage, when viewing the header, then the gold S logo mark appears left of "Soleur" text at ~24px
- Given the privacy policy page, when viewing content, then text width is ~75ch with proper heading/paragraph spacing
- Given the changelog page, when viewing version entries, then h2 entries have border-bottom and margin separation
- Given the getting started page, when viewing prose sections, then text is reading-width but command grids remain full-width
- Given any page on a 375px mobile viewport, when viewing content, then no horizontal overflow occurs
- Given the vision page, when viewing the first section, then paragraphs have visible margin between them
- Given the disclaimer page, when viewing content, then text width is ~75ch (not missed)

## Deferred Items

The following were identified in the UX audit but are out of scope for this iteration:

- Footer crowding on mobile (brainstorm issue #6)
- Console `ERR_NAME_NOT_RESOLVED` for Vercel analytics script (brainstorm issue #8)
- "Uncategorized" pill on Skills page (brainstorm issue #7)

## Implementation

### CSS changes (`plugins/soleur/docs/css/style.css`)

Add to `@layer components`:

```css
/* plugins/soleur/docs/css/style.css -- @layer components */

/* Prose reading width and vertical rhythm */
.prose {
  max-width: 75ch;
}

.prose h2,
.prose h3 {
  margin-top: var(--space-6);
  margin-bottom: var(--space-3);
}

.prose p {
  margin-bottom: var(--space-4);
}

.prose ul,
.prose ol {
  margin-bottom: var(--space-4);
  padding-left: var(--space-5);
}

.prose li {
  margin-bottom: var(--space-2);
}
```

Changelog-specific overrides (`.prose` handles base rhythm, ID selector adds changelog-only styling):

```css
/* Changelog overrides -- applied alongside .prose on #changelog-content */
#changelog-content h2 {
  font-family: var(--font-mono);
  font-size: var(--text-xl);
  border-bottom: 1px solid var(--color-border);
  padding-bottom: var(--space-2);
  margin-top: var(--space-8);
}

#changelog-content h2:first-child {
  margin-top: 0;
}

#changelog-content h3 {
  font-size: var(--text-base);
  margin-top: var(--space-5);
}
```

Vision page paragraph spacing (add to existing `.community-text` rule):

```css
/* Add margin-bottom to .community-text for paragraph spacing */
.community-text + .community-text {
  margin-top: var(--space-4);
}
```

### Template changes

**`plugins/soleur/docs/_includes/base.njk`** -- Add logo image to header:

```html
<!-- Change from: -->
<a href="index.html" class="logo">{{ site.name }}</a>

<!-- Change to: -->
<a href="index.html" class="logo">
  <img src="images/logo-mark-512.png" width="24" height="24" alt="">
  {{ site.name }}
</a>
```

No `.logo-mark` CSS class needed -- HTML `width`/`height` attributes handle sizing and CLS prevention. The flex `.logo` container (`display: flex; align-items: center; gap: var(--space-2)`) positions the image correctly.

**`plugins/soleur/docs/pages/changelog.njk`** -- Add `.prose` class to the changelog div:

```html
<!-- Change from: -->
<div id="changelog-content">

<!-- Change to: -->
<div id="changelog-content" class="prose">
```

**`plugins/soleur/docs/pages/legal/*.md`** -- All 7 legal pages need `.prose` wrapper:

- `acceptable-use-policy.md`
- `cookie-policy.md`
- `data-protection-disclosure.md`
- `disclaimer.md`
- `gdpr-policy.md`
- `privacy-policy.md`
- `terms-and-conditions.md`

Each has a `<section class="content">` block. Add `<div class="prose">` wrapper around the Markdown content inside the container div.

**`plugins/soleur/docs/pages/getting-started.md`** -- Wrap individual prose sections in `<div class="prose">` / `</div>` pairs around markdown headings and paragraphs. Leave `.quickstart-code`, `.commands-list`, `.command-item`, and `.learn-more-links` divs unwrapped so they stay full container width.

**`plugins/soleur/docs/pages/vision.njk`** -- No template change needed. The `.community-text + .community-text` CSS rule adds spacing between consecutive paragraphs.

### Verification

- Build docs with `npx @11ty/eleventy` (uses config defaults)
- Check each modified page visually
- Verify mobile responsiveness at 375px
- Confirm card grids, hero sections, and nav are unchanged

## Dependencies & Risks

- **Low risk:** CSS-only changes plus one `<img>` tag -- no JavaScript, no build changes
- **Logo path:** `images/logo-mark-512.png` must be copied to `_site/images/` by Eleventy passthrough -- verify it exists in the passthrough config
- **Getting Started complexity:** Mixed prose + grid layout requires `<div class="prose">` wrappers around specific sections to avoid narrowing grid components

## References & Research

- Brainstorm: `knowledge-base/brainstorms/2026-02-21-ux-ui-review-brainstorm.md`
- Spec: `knowledge-base/specs/feat-ux-ui-review/spec.md`
- GitHub issue: #201
- Existing prose pattern: `.community-text { max-width: 65ch }` in `style.css`
- CSS layers: `@layer reset, tokens, base, layout, components, utilities`
- Logo asset: `plugins/soleur/docs/images/logo-mark-512.png`
- Version bump intent: PATCH (docs styling update, no new skills/commands/agents)
