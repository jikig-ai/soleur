---
name: docs-site
description: This skill should be used when scaffolding a Markdown-based documentation site using Eleventy. It generates a complete docs setup with base layout, data files for build-time injection, GitHub Pages deployment workflow, and passthrough copy configuration. Triggers on "create docs site", "scaffold docs", "setup documentation", "eleventy docs", "docs-site".
---

# docs-site Skill

Scaffold a Markdown + Eleventy documentation site with build-time data injection and GitHub Pages deployment.

## Prerequisites

- Node.js 20+
- A `package.json` in the project root (or willingness to create one)

## Step 1: Gather Project Info

Ask the user:

1. **Project name** -- Used in site title, footer, nav logo
2. **Site URL** -- For meta tags, sitemap, og:url (e.g., `https://example.com`)
3. **Docs input directory** -- Where docs source files live (e.g., `docs/`)
4. **GitHub repository URL** -- For nav link and deployment
5. **Pages to create** -- Which pages beyond index (e.g., getting-started, changelog, API reference)

## Step 2: Install Dependencies

```bash
npm install --save-dev @11ty/eleventy
```

Add scripts to `package.json`:

```json
{
  "scripts": {
    "docs:dev": "npx @11ty/eleventy --serve",
    "docs:build": "npx @11ty/eleventy"
  }
}
```

Ensure `"type": "module"` is set in `package.json` for ESM config.

## Step 3: Create Eleventy Config

Create `eleventy.config.js` at the project root:

```javascript
const INPUT = "<docs-input-dir>";

export default function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/css`]: "css" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/images`]: "images" });
  // Add more passthrough copies as needed
}

export const config = {
  dir: {
    input: INPUT,
    output: "_site",
    includes: "_includes",
    data: "_data",
  },
  markdownTemplateEngine: "njk",
  htmlTemplateEngine: "njk",
  templateFormats: ["md", "njk"],
};
```

Add `_site/` to `.gitignore`.

## Step 4: Create Directory Structure

```
<docs-input-dir>/
  _data/
    site.json          # Site metadata (name, url, nav)
  _includes/
    base.njk           # Base HTML layout
  css/
    style.css          # Minimal starter CSS
  images/              # Static images
  index.njk            # Landing page
  pages/
    getting-started.md # First content page
```

### `_data/site.json`

```json
{
  "name": "<Project Name>",
  "url": "<site-url>",
  "nav": [
    { "label": "Get Started", "url": "pages/getting-started.html" }
  ]
}
```

### `_includes/base.njk`

Create a minimal HTML shell with:
- Head: charset, viewport, description meta, title, CSS link
- Header: logo linking to index.html, nav from `site.nav`
- Main: `{{ content | safe }}`
- Footer: project name, links

Use `page.url` comparison for `aria-current="page"` on nav links.

### `css/style.css`

Provide a minimal starter stylesheet with CSS custom properties for easy theming.

### Content pages

Create `.md` files with YAML frontmatter:

```yaml
---
title: Getting Started
description: "How to get started with <Project Name>"
layout: base.njk
permalink: pages/getting-started.html
---
```

## Step 5: Data Files (Optional)

If the project has components to catalog at build time, create data files in `_data/`:

```javascript
// _data/version.js -- reads version from package.json
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export default function () {
  const pkg = JSON.parse(readFileSync(resolve("package.json"), "utf-8"));
  return pkg.version;
}
```

Data files export a function that returns data available in all templates.

## Step 6: GitHub Pages Workflow

Create `.github/workflows/deploy-docs.yml`:

```yaml
name: Deploy Documentation

on:
  push:
    branches: [main]
    paths:
      - '<docs-input-dir>/**'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    environment:
      name: github-pages
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npx @11ty/eleventy
      - uses: actions/configure-pages@v4
      - uses: actions/upload-pages-artifact@v3
        with:
          path: _site
      - uses: actions/deploy-pages@v4
```

## Step 7: Verify

```bash
npx @11ty/eleventy --serve
```

Open `http://localhost:8080` and verify:
- All pages render correctly
- CSS loads
- Navigation works with `aria-current="page"`
- Data variables resolve in templates

## Notes

- Nunjucks variables (`{{ var }}`) are NOT resolved inside YAML frontmatter. Use static strings for `description` in frontmatter, and template variables only in the page body.
- Passthrough copy paths in `addPassthroughCopy()` are relative to the project root, NOT the input directory. Use the mapping format: `{ "source/path": "output/path" }`.
- Eleventy v3 uses ESM (`export default`) -- do not use CommonJS (`module.exports`).
