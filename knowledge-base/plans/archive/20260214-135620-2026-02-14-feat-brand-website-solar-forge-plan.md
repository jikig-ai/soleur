---
title: "feat: Publish Brand Website (Solar Forge)"
type: feat
date: 2026-02-14
---

# feat: Publish Brand Website (Solar Forge)

[Updated 2026-02-14: Simplified after plan review by DHH, Kieran, and simplicity reviewers. Collapsed 6 phases to 2, reduced acceptance criteria from 16 to 8, removed process overhead.]

## Overview

Replace the current docs homepage with a marketing landing page generated from the Solar Forge .pen design, and restyle all docs pages to match the Solar Forge brand identity. Deploy as a unified site via the existing GitHub Pages workflow.

## Problem Statement

PR #86 shipped a functional docs site with a generic light/dark theme. The Solar Forge brand identity exists in a .pen design file but is not reflected on the live site. The homepage is a simple stats page that does not communicate what Soleur is or why someone should use it.

## Proposed Solution

Generate the Solar Forge landing page from the .pen design file (`knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`, frame `0Ja8a`), rewrite the CSS with Solar Forge brand tokens, and apply consistent styling to all docs pages.

## Design Decisions

1. **Theme toggle: Remove it.** Solar Forge is a dark-only brand. Remove `data-theme` attribute from all `<html>` tags entirely. CSS tokens move from the `[data-theme="dark"]` selector to `:root`. Remove the localStorage theme persistence script and toggle button from all pages.

2. **Font loading: Self-host woff2 files.** Download Cormorant Garamond (500) and Inter (400, 700) as `.woff2` files into `docs/fonts/`. Use `@font-face` declarations with `font-display: swap`. Skip the italic variant and Inter 600 unless the implementation actually uses them. JetBrains Mono stays as a system fallback in the font stack -- not self-hosted.

3. **CTA destinations:** "Start Building" links to `pages/getting-started.html`. "Read the Docs" links to `pages/agents.html`.

4. **Navigation: Unified across all pages.** Same nav structure everywhere: logo, docs links (Agents, Commands, Skills, MCP, Changelog, Get Started), GitHub link. Drop marketing-specific "Platform, Docs, Community" from the .pen design -- those are future items. "Solar Forge" is an internal codename for the design direction, not a user-facing name.

5. **CSS architecture: Single `style.css`, rewritten.** Replace the existing oklch token system with Solar Forge hex values. Keep the CSS layers architecture (`@layer reset, tokens, base, layout, components, utilities`). All brand tokens defined in the `@layer tokens` block at the top of the file -- this serves as the single source of truth without needing a separate file. The tokens block is ~20 lines at the top of a single file; a separate `tokens.css` adds an HTTP request for negligible organizational benefit.

6. **Dead code: Delete `js/main.js` and `js/` directory.** The file exists but no page loads it. The nav toggle is handled by a CSS checkbox hack. The `.open` class it toggles has no CSS rule. The sidebar links it references do not exist.

7. **Favicon: One file.** Single `favicon.png` (32x32). No apple-touch-icon, no .ico multi-format. This is a developer tool docs site, not a consumer app.

8. **Accessibility: Adjust low-contrast colors.** The .pen design uses `#4A4A4A` for footer text (fails WCAG AA against `#0A0A0A`). Lighten tertiary text to `#737373` (5.5:1 ratio). Contrast pairs to verify during implementation:
   - `#FFFFFF` on `#0A0A0A` -- 19.3:1 (passes)
   - `#848484` on `#0A0A0A` -- 5.0:1 (passes AA normal text)
   - `#737373` on `#0A0A0A` -- 5.5:1 (passes AA normal text)
   - `#737373` on `#0E0E0E` -- 5.1:1 (passes AA normal text)
   - `#737373` on `#141414` -- 4.6:1 (passes AA normal text)
   - `#C9A962` on `#0A0A0A` -- 6.5:1 (passes AA normal text)

9. **Responsive: Landing page sections need responsive rules.** The non-goal is adding *new* breakpoints. But new landing page sections (stats strip, feature grid) need responsive rules at the existing 768px and 640px breakpoints. This is in scope.

10. **Code generation: Manual adjustment expected.** Pencil code generation from the .pen frame will produce a starting point, not final output. Class names, structure, and content will be manually adjusted to match the CSS and site structure.

## Local Development

All pages use `<base href="/soleur/">` for GitHub Pages. Local testing requires mirroring the path:

```bash
mkdir -p /tmp/soleur-test/soleur
cp -r plugins/soleur/docs/* /tmp/soleur-test/soleur/
cd /tmp/soleur-test
python3 -m http.server 8766
# Access at http://localhost:8766/soleur/
```

## Acceptance Criteria

- [ ] Landing page renders Solar Forge brand design (hero, stats, problem, quote, features, CTA, footer)
- [ ] All pages force dark theme (no toggle, no localStorage script)
- [ ] Fonts self-hosted and loading correctly
- [ ] Favicon present
- [ ] Dead `js/main.js` deleted
- [ ] Navigation and footer consistent across all pages
- [ ] Text meets WCAG AA contrast ratios (see contrast matrix in Decision 8)
- [ ] GitHub Pages deployment succeeds

## Test Scenarios

- Given a new visitor, when they load the homepage, then they see the Solar Forge landing page with hero, stats, and CTA sections
- Given a visitor on the landing page, when they click "Agents" in nav, then they arrive at the agents page styled in Solar Forge brand
- Given a visitor on mobile (<768px), when they tap the hamburger, then the nav slides in with all links visible
- Given a screen reader user, when they press Tab on page load, then the skip link focuses and jumps to main content
- Given any text on any page, when checked for contrast against its background, then it meets WCAG AA minimum (4.5:1 normal, 3:1 large)

## Implementation Phases

### Phase A: Landing Page and CSS Rewrite

This is the real work. Everything else is mechanical propagation.

**Files created:**
- `plugins/soleur/docs/fonts/cormorant-garamond-500.woff2`
- `plugins/soleur/docs/fonts/inter-400.woff2`
- `plugins/soleur/docs/fonts/inter-700.woff2`
- `plugins/soleur/docs/images/favicon.png` (32x32)
- `plugins/soleur/docs/images/og-image.png` (1200x630)

**Files modified:**
- `plugins/soleur/docs/css/style.css` (full rewrite)
- `plugins/soleur/docs/index.html` (full rewrite)

**Files deleted:**
- `plugins/soleur/docs/js/main.js`
- `plugins/soleur/docs/js/` (directory)

**Tasks:**
1. Download font woff2 files into `docs/fonts/`
2. Export favicon and OG image from .pen file logo variations
3. Rewrite `style.css`:
   - Add `@font-face` declarations
   - Replace oklch tokens with Solar Forge hex values in `:root` (no `[data-theme]` selectors)
   - Remove light theme token set and theme toggle styles
   - Add landing page section styles
   - Update existing docs component styles with new tokens
   - Add responsive rules for new landing page sections at 768px breakpoint
4. Rewrite `index.html`:
   - Generate from .pen frame `0Ja8a`, manually adjust class names and structure
   - Remove theme toggle from nav, remove theme init script
   - Remove `data-theme` from `<html>`, add favicon/OG meta tags
   - Preserve `<main id="main-content">` and skip link
   - Wire CTAs: "Start Building" -> getting-started, "Read the Docs" -> agents
5. Delete `js/main.js` and `js/` directory
6. Verify landing page looks right locally

### Phase B: Propagate to Remaining Pages + Ship

Mechanical changes: same header/footer/head across all remaining pages.

**Files modified:**
- `plugins/soleur/docs/pages/agents.html`
- `plugins/soleur/docs/pages/commands.html`
- `plugins/soleur/docs/pages/skills.html`
- `plugins/soleur/docs/pages/mcp-servers.html`
- `plugins/soleur/docs/pages/changelog.html`
- `plugins/soleur/docs/pages/getting-started.html`
- `plugins/soleur/docs/404.html`
- `plugins/soleur/docs/sitemap.xml` (verify URLs are correct)
- `plugins/soleur/.claude-plugin/plugin.json` (PATCH bump)
- `plugins/soleur/CHANGELOG.md`
- `plugins/soleur/README.md`
- Root `README.md` (version badge)

**Tasks (per page):**
1. Remove `data-theme="light"` from `<html>` tag
2. Remove inline theme detection `<script>` from `<head>`
3. Remove theme toggle button from nav
4. Add favicon `<link>` tag
5. Add `og:image` meta tag
6. Unify footer markup to match landing page footer

**Ship tasks:**
7. PATCH bump version across versioning triad
8. Grep all HTML for old version string, update version badges
9. Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
10. Commit all files (brainstorm, spec, plan, tasks, code, assets)
11. Push and create PR referencing issue #88

## Version Bump Intent

**PATCH** -- docs/website update, no new plugin components.

## Dependencies and Risks

- **Font files size:** woff2 files add ~100KB to the repo (3 files). Acceptable.
- **OG image generation:** Requires exporting from the .pen file. If Pencil cannot export, screenshots can substitute.
- **.pen file access:** The design file is in the main repo, not in the worktree. Code generation references the main repo path.
- **CSS migration scope:** Full CSS rewrite affects all 8 pages. Mitigate by testing each page after Phase B.

## Non-Goals

- JavaScript interactions or animations
- Blog or CMS functionality
- New responsive breakpoints (existing 768px/640px breakpoints are used for new sections)
- Analytics or tracking
- Multi-language support
- Light theme variant

## References

### Internal
- Spec: `knowledge-base/specs/feat-brand-website/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-02-14-brand-website-brainstorm.md`
- Design source: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` (frame `0Ja8a`)
- Brand guide: `knowledge-base/overview/brand-guide.md`

### Learnings Applied
- `knowledge-base/learnings/2026-02-13-base-href-breaks-local-dev-server.md`
- `knowledge-base/learnings/2026-02-13-parallel-subagent-css-class-mismatch.md`
- `knowledge-base/learnings/2026-02-13-version-bump-cascades-to-html-badges.md`
- `knowledge-base/learnings/2026-02-13-static-docs-site-from-brand-guide.md`
