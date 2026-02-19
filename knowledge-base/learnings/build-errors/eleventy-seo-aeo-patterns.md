# Learning: Eleventy SEO/AEO build-time patterns

## Problem

The docs site changelog page used client-side JavaScript to fetch CHANGELOG.md from GitHub raw URLs and render it in the browser. This made the content invisible to search engine crawlers and AI models, which don't execute JavaScript. Additionally, when converting the sitemap to use Eleventy's `collections.all`, the 404 page appeared in the sitemap because it lacked `eleventyExcludeFromCollections`.

## Solution

Three patterns emerged:

### 1. Build-time rendering replaces client-side fetch

Install `markdown-it` as a devDependency and create a `_data/changelog.js` file that reads and renders CHANGELOG.md at build time:

```javascript
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import MarkdownIt from "markdown-it";

const md = new MarkdownIt();

export default function () {
  try {
    const raw = readFileSync(resolve("plugins/soleur/CHANGELOG.md"), "utf-8");
    const body = raw.replace(/^# .+\n(?:.*\n)*?(?=\n## )/, "");
    return { html: md.render(body) };
  } catch {
    return { html: "" };
  }
}
```

Then use `{{ changelog.html | safe }}` in the Nunjucks template instead of a `<script>` block. The build already triggers on CHANGELOG.md changes, so the client-side fetch provided no freshness benefit.

### 2. Exclude non-content pages from collections

Any page that should not appear in `sitemap.xml` (when using `collections.all`) must have `eleventyExcludeFromCollections: true` in its frontmatter. This includes: 404.html, sitemap.xml itself, llms.txt, and any utility templates.

### 3. CI SEO validation must be standalone bash

GitHub Actions cannot invoke Claude Code. SEO validation scripts must be self-contained bash that checks `_site/` output with `grep` and `test` commands. The script lives alongside the skill at `skills/seo-aeo/scripts/validate-seo.sh` and is called directly by the CI workflow.

## Key Insight

When content is rendered client-side (JS fetch + DOM manipulation), it is invisible to crawlers and AI models. For SEO and AEO, all content must be available in the HTML source at build time. Build-time rendering with Eleventy data files is the correct pattern -- it uses the same data pipeline as other dynamic content and requires no runtime dependencies.

## Tags

category: build-errors
module: docs-site
symptoms: changelog invisible to crawlers, 404 in sitemap, CI cannot run Claude
