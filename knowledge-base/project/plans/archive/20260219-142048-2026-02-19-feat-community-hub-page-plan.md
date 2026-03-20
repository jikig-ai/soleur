---
title: "feat: Add community hub page to docs site"
type: feat
date: 2026-02-19
issue: "#149"
---

# feat: Add community hub page to docs site

## Overview

Create a static community hub page on the Soleur docs site that consolidates GitHub and Discord links into a single "Community" navigation item. The page has four sections: platform cards (Discord/GitHub), contributing guide, support/getting help, and code of conduct.

## Acceptance Criteria

- [x] New `community.njk` page served at `pages/community.html`
- [x] Header nav: hardcoded GitHub/Discord links removed from `base.njk`, "Community" added to `site.nav`
- [x] Footer nav: GitHub/Discord entries in `site.footerLinks` replaced with Community link
- [x] Page has hero section, Discord/GitHub cards, contributing, support, and code of conduct sections
- [x] No custom CSS -- reuses existing `.page-hero`, `.catalog-grid`, `.component-card` classes
- [x] Responsive at all breakpoints (desktop, 1024px, 768px)
- [x] Included in sitemap (standard Eleventy collection behavior)
- [x] Eleventy build passes with no errors

## Test Scenarios

- Given a user on any docs page, when they click "Community" in the header, then they land on `pages/community.html`
- Given a user on the community page, when they click the Discord card link, then they are taken to `https://discord.gg/PYZbPBKMUY` in a new tab
- Given a user on the community page, when they click the GitHub card link, then they are taken to `https://github.com/jikig-ai/soleur` in a new tab
- Given a user on mobile (768px), when they view the community page, then the cards stack vertically and all content is readable

## Context

- Brainstorm: `knowledge-base/brainstorms/2026-02-19-community-page-brainstorm.md`
- Spec: `knowledge-base/specs/feat-community-page/spec.md`
- The docs site uses Eleventy with Nunjucks templates. All pages use `base.njk` layout.
- `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` both exist in the repo root.

## MVP

### 1. Update `plugins/soleur/docs/_data/site.json`

Add "Community" to the `nav` array and update `footerLinks`:

```json
{
  "nav": [
    { "label": "Get Started", "url": "pages/getting-started.html" },
    { "label": "Agents", "url": "pages/agents.html" },
    { "label": "Skills", "url": "pages/skills.html" },
    { "label": "Community", "url": "pages/community.html" },
    { "label": "Changelog", "url": "pages/changelog.html" }
  ],
  "footerLinks": [
    { "label": "Get Started", "url": "pages/getting-started.html" },
    { "label": "Community", "url": "pages/community.html" }
  ]
}
```

### 2. Update `plugins/soleur/docs/_includes/base.njk`

Remove the two hardcoded `<li>` elements for GitHub and Discord (lines 77-78). The header nav will now be fully driven by `site.nav`.

```html
<!-- Remove these two lines -->
<li><a href="{{ site.github }}" target="_blank" rel="noopener">GitHub</a></li>
<li><a href="{{ site.discord }}" target="_blank" rel="noopener">Discord</a></li>
```

### 3. Create `plugins/soleur/docs/pages/community.njk`

New Nunjucks template following the pattern of `agents.njk`:

```nunjucks
---
title: Community
description: "Join the Soleur community. Connect on Discord, contribute on GitHub, get help, and learn about our community guidelines."
layout: base.njk
permalink: pages/community.html
---

<section class="page-hero">
  <div class="container">
    <h1>Community</h1>
    <p>Connect, contribute, and get help.</p>
  </div>
</section>

<div class="container">
  <!-- Discord + GitHub cards -->
  <section class="category-section">
    <div class="category-header">
      <h2 class="category-title">Connect</h2>
    </div>
    <div class="catalog-grid">
      <a href="{{ site.discord }}" target="_blank" rel="noopener" class="component-card" style="text-decoration: none; color: inherit;">
        <div class="card-header">
          <span class="card-dot" style="background: #5865F2"></span>
          <span class="card-category">Chat</span>
        </div>
        <h3 class="card-title">Discord</h3>
        <p class="card-description">Ask questions, share what you're building, and connect with other Soleur users.</p>
      </a>
      <a href="{{ site.github }}" target="_blank" rel="noopener" class="component-card" style="text-decoration: none; color: inherit;">
        <div class="card-header">
          <span class="card-dot" style="background: #F0F0F0"></span>
          <span class="card-category">Code</span>
        </div>
        <h3 class="card-title">GitHub</h3>
        <p class="card-description">Browse the source, report issues, submit pull requests, and star the project.</p>
      </a>
    </div>
  </section>

  <!-- Contributing -->
  <section class="category-section">
    <div class="category-header">
      <h2 class="category-title">Contributing</h2>
    </div>
    <p style="color: var(--color-text-secondary); line-height: 1.6; max-width: 65ch;">
      We welcome contributions of all kinds -- bug reports, feature requests, documentation improvements, and code.
      Read the <a href="{{ site.github }}/blob/main/CONTRIBUTING.md" target="_blank" rel="noopener" style="color: var(--color-accent);">contributing guide</a> to get started.
    </p>
  </section>

  <!-- Support -->
  <section class="category-section">
    <div class="category-header">
      <h2 class="category-title">Getting Help</h2>
    </div>
    <div class="catalog-grid">
      <article class="component-card">
        <div class="card-header">
          <span class="card-dot" style="background: var(--cat-review)"></span>
          <span class="card-category">Questions</span>
        </div>
        <h3 class="card-title">Ask on Discord</h3>
        <p class="card-description">Join the Discord server and ask in the help channel. The community and maintainers are active there.</p>
      </article>
      <article class="component-card">
        <div class="card-header">
          <span class="card-dot" style="background: var(--cat-workflow)"></span>
          <span class="card-category">Bugs</span>
        </div>
        <h3 class="card-title">Report an Issue</h3>
        <p class="card-description">Found a bug? Open an issue on GitHub with reproduction steps and we'll look into it.</p>
      </article>
      <article class="component-card">
        <div class="card-header">
          <span class="card-dot" style="background: var(--cat-design)"></span>
          <span class="card-category">Ideas</span>
        </div>
        <h3 class="card-title">Request a Feature</h3>
        <p class="card-description">Have an idea? Open a GitHub issue or start a discussion on Discord. We love hearing what you'd find useful.</p>
      </article>
    </div>
  </section>

  <!-- Code of Conduct -->
  <section class="category-section">
    <div class="category-header">
      <h2 class="category-title">Code of Conduct</h2>
    </div>
    <p style="color: var(--color-text-secondary); line-height: 1.6; max-width: 65ch;">
      We are committed to providing a welcoming and inclusive experience for everyone.
      Please read our <a href="{{ site.github }}/blob/main/CODE_OF_CONDUCT.md" target="_blank" rel="noopener" style="color: var(--color-accent);">code of conduct</a> before participating.
    </p>
  </section>
</div>
```

### 4. Verify build

```bash
cd plugins/soleur/docs && npx @11ty/eleventy --input=. --output=../_site_test
```

Confirm:
- `pages/community.html` is generated
- Sitemap includes the new page
- No build errors

### 5. Version bump

This modifies files under `plugins/soleur/docs/` -- requires a PATCH bump (docs update, no new skill/agent/command).

Update:
- `plugins/soleur/.claude-plugin/plugin.json` -- bump patch version
- `plugins/soleur/CHANGELOG.md` -- add entry under new version
- `plugins/soleur/README.md` -- verify counts (no new components, just docs page)

## References

- Issue: #149
- Layout template: `plugins/soleur/docs/_includes/base.njk`
- Data file: `plugins/soleur/docs/_data/site.json`
- Pattern reference: `plugins/soleur/docs/pages/agents.njk`
- CSS tokens: `plugins/soleur/docs/css/style.css:25-60`
