---
title: Enable GitHub Pages
type: feat
date: 2026-02-13
issue: "#85"
deepened: 2026-02-13
---

# Enable GitHub Pages

## Enhancement Summary

**Deepened on:** 2026-02-13
**Research agents used:** GitHub Pages best practices, frontend design, architecture strategist, code simplicity, security sentinel, learnings researcher

### Key Improvements
1. Added `.nojekyll`, `404.html`, `robots.txt`, `sitemap.xml` for complete GitHub Pages setup
2. Added `<base href="/soleur/">` pattern for clean cross-page linking
3. Defined visual design direction: utilitarian precision aesthetic with warm amber accent, OKLCH colors, CSS custom properties, dark mode, and accessibility compliance
4. Aligned page list with deploy-docs skill expectations (added changelog, getting-started)
5. Security: HTML-escape all content generated from markdown source files, self-host all assets

### Considerations from Research
- deploy-docs skill validation expects 7 pages (index + 6 subpages) — plan now matches
- Static site numbers (agent/skill counts) are maintained by release-docs skill, not hand-edited
- Documentation staleness is a known risk — release-docs integration prevents drift

## Overview

Create the documentation site at `plugins/soleur/docs/` so the existing GitHub Actions workflow can deploy it. GitHub Pages is already enabled in repo settings (source: GitHub Actions). The deploy workflow (`.github/workflows/deploy-docs.yml`) and validation skills (`deploy-docs`, `release-docs`) already exist — only the content is missing.

## Acceptance Criteria

- [ ] `plugins/soleur/docs/index.html` exists with landing page, nav, and workflow pipeline visualization
- [ ] `plugins/soleur/docs/pages/agents.html` lists all 23 agents grouped by category
- [ ] `plugins/soleur/docs/pages/commands.html` lists all 8 commands
- [ ] `plugins/soleur/docs/pages/skills.html` lists all 37 skills
- [ ] `plugins/soleur/docs/pages/mcp-servers.html` exists (placeholder — 0 servers currently)
- [ ] `plugins/soleur/docs/pages/changelog.html` renders changelog content
- [ ] `plugins/soleur/docs/pages/getting-started.html` has installation + quick start
- [ ] `plugins/soleur/docs/css/style.css` exists with responsive styling, dark mode, accessibility
- [ ] `plugins/soleur/docs/404.html` exists with nav and "return home" link
- [ ] `plugins/soleur/docs/.nojekyll` exists (zero-byte file)
- [ ] `/soleur:deploy-docs` validation passes (all pages present, counts match)
- [ ] Site deploys successfully to https://jikig-ai.github.io/soleur/
- [ ] No Jekyll — plain static HTML (matches existing workflow)
- [ ] All content from markdown source files is HTML-escaped (no raw insertion)
- [ ] All assets self-hosted (no external CDN dependencies)
- [ ] Every page has `<base href="/soleur/">` for correct path resolution

## Test Scenarios

- Given the docs directory exists with all required pages, when deploy-docs validation runs, then all checks pass
- Given the site is deployed, when visiting https://jikig-ai.github.io/soleur/, then the landing page renders correctly with dark/light mode
- Given a user navigates between pages, when clicking nav links, then all pages load without 404s
- Given a user hits an invalid URL, when the 404 page renders, then it shows navigation back to the site
- Given a user views the site on mobile, when the viewport is < 768px, then the nav collapses to hamburger and cards stack vertically
- Given a screen reader user, when navigating the site, then semantic HTML, skip links, and ARIA labels provide full accessibility

## Implementation Plan

### File Structure

```text
plugins/soleur/docs/
├── .nojekyll               # Prevent Jekyll processing
├── index.html              # Landing page with workflow pipeline
├── 404.html                # Custom 404 with navigation
├── robots.txt              # Search engine discoverability
├── sitemap.xml             # Page listing for search engines
├── css/
│   └── style.css           # Shared styles (OKLCH, dark mode, responsive)
└── pages/
    ├── agents.html         # 23 agents grouped by category
    ├── commands.html       # 8 commands
    ├── skills.html         # 37 skills
    ├── mcp-servers.html    # MCP servers (placeholder)
    ├── changelog.html      # Changelog content
    └── getting-started.html # Installation + quick start
```

Total: 11 files (6 HTML pages + index + 404 + CSS + robots.txt + sitemap.xml + .nojekyll)

### Visual Design Direction

**Aesthetic:** Utilitarian precision — typography-forward, monochrome-dominant, single warm accent color. Communicates engineering rigor without being generic.

**Color palette:** OKLCH-based CSS custom properties for perceptual uniformity. Light and dark themes via `data-theme` attribute on `<html>`.
- Background hierarchy: near-white → subtle gray → code-block gray
- Text hierarchy: near-black → mid-gray → light-gray
- Accent: warm amber (`oklch(0.75 0.15 75)`) — distinctive, avoids cliche purple
- Category colors for agent domains (steel blue, teal, muted purple, etc.)

**Typography:** System font stack for body (no external font dependencies — self-hosting constraint). Monospace for component names and code. Major third type scale (1.25 ratio).

**Layout:**
- Fixed header with frosted-glass effect (`backdrop-filter: blur`)
- Sticky category filter bar on catalog pages (horizontal pill navigation)
- CSS Grid with `auto-fill minmax(320px, 1fr)` for responsive card grids
- Max-width 1200px container
- Mobile-first breakpoints: base (mobile) → 768px (tablet) → 1024px (desktop)

**Dark mode:** `data-theme="dark"` toggled via small inline script in `<head>` (respects `prefers-color-scheme`, persists to `localStorage`). Only JavaScript on the site.

**Navigation:** Duplicate nav in each page (not JS includes). Release-docs skill regenerates all pages, so duplication is a non-issue. Mobile: checkbox-based hamburger toggle (CSS-only, no JS needed).

**Accessibility:**
- Semantic HTML (`<header>`, `<nav>`, `<main>`, `<article>`, `<footer>`)
- Skip link: `<a href="#main-content" class="skip-link">Skip to main content</a>`
- `lang="en"` on `<html>`
- Focus-visible styles with accent color ring
- `prefers-reduced-motion` media query to disable transitions
- All cards as `<article>` elements with headings
- ARIA labels on decorative elements and toggles
- 4.5:1 contrast ratio for text

**Memorable element:** Workflow pipeline visualization on landing page showing `brainstorm → plan → work → review → compound` as connected horizontal nodes. Collapses to vertical on mobile.

### Cross-Page Path Handling

Every HTML page includes `<base href="/soleur/">` in `<head>`. All paths are then relative to site root without leading slashes:
- `css/style.css` (from any page)
- `pages/agents.html` (from any page)
- `index.html` (from any page)

This eliminates `../` vs `./` inconsistency across directory levels.

### Pages to Create

1. **`index.html`** — Landing page
   - Brief description of Soleur (one sentence, not marketing copy)
   - Workflow pipeline visualization (brainstorm → plan → work → review → compound)
   - Navigation links to all subpages
   - Quick start: `claude install jikig-ai/soleur`
   - Component counts (auto-maintained by release-docs skill)

2. **`pages/agents.html`** — Agent catalog
   - Read all `plugins/soleur/agents/**/*.md`, extract frontmatter (name, description)
   - Group by category: Engineering/Review (14), Engineering/Design (1), Research (5), Workflow (2), Marketing (1)
   - Render as card grid with category pill navigation
   - Each card: category dot + label, name in monospace, description, usage example

3. **`pages/commands.html`** — Command reference
   - Read all `plugins/soleur/commands/soleur/*.md`, extract frontmatter
   - Wider horizontal card layout (fewer items, more detail per card)
   - Each card: name, description, arguments, process steps

4. **`pages/skills.html`** — Skills catalog
   - Read all `plugins/soleur/skills/*/SKILL.md`, extract frontmatter
   - Group by category (Development Tools, Content & Workflow, etc.)
   - Card grid with category navigation

5. **`pages/mcp-servers.html`** — MCP servers
   - Show Context7 server from plugin.json
   - Placeholder structure for future servers

6. **`pages/changelog.html`** — Changelog
   - Render content from `CHANGELOG.md`
   - Version sections with dates

7. **`pages/getting-started.html`** — Quick start guide
   - Installation command
   - First steps (brainstorm → plan → work → review → compound)
   - Links to key skills and commands

8. **`404.html`** — Custom error page
   - Site navigation preserved
   - "Return to home" link

### CSS Architecture

Single `css/style.css` file using CSS `@layer` for cascade control:

```css
@layer reset, tokens, base, layout, components, utilities;
```

- `reset` — Minimal reset
- `tokens` — All CSS custom properties (colors, typography, spacing)
- `base` — HTML elements, body, headings, links
- `layout` — Container, grids, page structure
- `components` — Cards, pills, pipeline, nav, hero
- `utilities` — `.sr-only`, `.skip-link`

Target: under 600 lines. No build step. No framework.

### Security Implementation Notes

- **HTML-escape all content** from markdown/YAML source files when generating HTML. Every `<`, `>`, `&`, `"`, `'` must be entity-escaped.
- **Self-host all assets.** No Google Fonts, no CDN CSS, no external images.
- **If external resources are ever needed:** Add SRI (`integrity` + `crossorigin`) attributes.
- **Dark mode toggle script** is the only JavaScript — minimal attack surface.

### Workflow Validation Enhancement

Add a lightweight file-existence check to `.github/workflows/deploy-docs.yml` before the upload step:

```yaml
- name: Validate docs
  run: |
    test -f plugins/soleur/docs/index.html || exit 1
    for page in agents commands skills mcp-servers changelog getting-started; do
      test -f "plugins/soleur/docs/pages/${page}.html" || exit 1
    done
```

### Version Bump

This adds files under `plugins/soleur/` but no new skills/commands/agents — PATCH bump: 2.5.0 → 2.5.1. Update plugin.json, CHANGELOG.md, README.md.

## Context

- GitHub Pages already enabled: `build_type: "workflow"`, URL: `https://jikig-ai.github.io/soleur/`
- Deploy workflow: `.github/workflows/deploy-docs.yml` triggers on pushes to main touching `plugins/soleur/docs/**`
- `release-docs` skill: inventories components and regenerates HTML pages (prevents staleness)
- `deploy-docs` skill: validates site before deployment (expects 7 pages)
- Known risk: overview docs go stale after restructures (learning: `2026-02-12-overview-docs-stale-after-restructure.md`)

## References

- Issue: #85
- Deploy workflow: `.github/workflows/deploy-docs.yml`
- Deploy-docs skill: `plugins/soleur/skills/deploy-docs/SKILL.md`
- Release-docs skill: `plugins/soleur/skills/release-docs/SKILL.md`
- Learning — docs staleness: `knowledge-base/learnings/technical-debt/2026-02-12-overview-docs-stale-after-restructure.md`
- Learning — documentation system: `knowledge-base/learnings/implementation-patterns/project-overview-documentation-system.md`
- Learning — plugin versioning: `knowledge-base/learnings/plugin-versioning-requirements.md`
