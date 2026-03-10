---
title: "feat: Blog Infrastructure for SEO/AEO"
type: feat
date: 2026-03-04
semver: minor
---

# feat: Blog Infrastructure for SEO/AEO

## Overview

Rename the existing `articles/` system (PR #428) to `blog/` and add missing infrastructure: RSS feed, clean URLs, Open Graph overrides, and `BlogPosting` Schema.org structured data. Zero articles exist — rename is cost-free now.

## Problem Statement / Motivation

PR #428 delivered article infrastructure under non-standard naming (`/pages/articles.html`, `/articles/{slug}.html`). Every SaaS competitor uses `/blog/` (Vercel, Supabase, Linear, Stripe). LLMs expect `/blog/` for AEO discoverability. Current URLs leak Eleventy internals (`/pages/`, `.html` extensions). Missing RSS blocks content distribution to developer RSS readers and AI training pipelines. The window for a cost-free rename closes the moment the first article ships.

## Non-Goals

- Writing actual blog content (separate effort)
- Tag index pages (add when 5+ posts share a tag)
- Content-type filter tabs (add when the listing page has enough posts to warrant filtering)
- GEO/AEO structural CSS classes (add when the first article that needs them is written)
- Email capture / newsletter subscription
- CMS or admin interface
- Comment system
- Search functionality within blog

## Affected Teams

- **Engineering** — template and config changes
- **Marketing** — blog is a marketing-visible surface (CMO reviewed during brainstorm)

## Proposed Solution

### Phase 1: Rename and Clean URLs (Foundation)

Remove old articles system and create blog directory structure with clean URLs.

**Files:**

1. **Delete** `plugins/soleur/docs/articles/articles.json`
2. **Delete** `plugins/soleur/docs/_includes/article.njk`
3. **Replace** `plugins/soleur/docs/pages/articles.njk` with redirect to `/blog/`:

```njk
---
permalink: pages/articles.html
eleventyExcludeFromCollections: true
---
<!DOCTYPE html>
<html><head><meta http-equiv="refresh" content="0;url=/blog/"></head></html>
```

4. **Create** `plugins/soleur/docs/blog/blog.json` — collection data cascade:

```json
{
  "tags": "blog",
  "layout": "blog-post.njk",
  "permalink": "blog/{{ page.fileSlug }}/index.html",
  "ogType": "article"
}
```

Note: `permalink: "blog/{{ page.fileSlug }}/index.html"` renders as `/blog/my-post/` — Eleventy's clean URL pattern. The trailing `/index.html` is the file on disk; browsers see `/blog/my-post/`.

5. **Update** `plugins/soleur/docs/_data/site.json`:
   - Rename nav entry: `"label": "Blog", "url": "blog/"`
   - Rename footerLinks entry: `"label": "Blog", "url": "blog/"`

6. **Update** `plugins/soleur/docs/llms.txt.njk` — replace "Articles" references with "Blog"

7. **Update** `base.njk` nav active state logic — change from exact match to `startsWith` so "Blog" highlights on post pages too:

```njk
{# Before #}
{% if page.url == ('/' + item.url) %}
{# After #}
{% if page.url == ('/' + item.url) or (item.url == 'blog/' and page.url.startsWith('/blog')) %}
```

### Phase 2: Blog Post Layout (Core Template)

Create the blog post layout with BlogPosting schema and OG overrides.

**Update `base.njk`** — three changes:

1. Add `{% block extraHead %}{% endblock %}` before `</head>` for child template head injection
2. Wrap the body content area in `{% block content %}...{% endblock %}` around the existing `{{ content | safe }}` call (backwards-compatible — templates that don't define this block still pipe through `content|safe`)
3. Replace hardcoded `<meta property="og:type" content="website" />` with `<meta property="og:type" content="{{ ogType | default('website') }}" />`
4. Add RSS auto-discovery: `<link rel="alternate" type="application/atom+xml" title="Soleur Blog" href="/blog/feed.xml" />`

```njk
{# In <head>, before </head>: #}
    <meta property="og:type" content="{{ ogType | default('website') }}" />
    <link rel="alternate" type="application/atom+xml" title="Soleur Blog" href="/blog/feed.xml" />
    {% block extraHead %}{% endblock %}
  </head>

{# Around the body content area: #}
{% block content %}
  {{ content | safe }}
{% endblock %}
```

**Create** `plugins/soleur/docs/_includes/blog-post.njk`:

```njk
---
layout: base.njk
---
{% block extraHead %}
<meta property="article:published_time" content="{{ date | dateToRfc3339 }}" />
{% for tag in tags %}{% if tag != "blog" %}
<meta property="article:tag" content="{{ tag }}" />
{% endif %}{% endfor %}
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BlogPosting",
  "headline": "{{ title }}",
  "description": "{{ description }}",
  "datePublished": "{{ date | dateToRfc3339 }}",
  "url": "{{ site.url }}{{ page.url }}",
  "author": {
    "@type": "Person",
    "name": "{{ site.author.name }}"
  },
  "publisher": {
    "@type": "Organization",
    "name": "{{ site.name }}",
    "url": "{{ site.url }}"
  }
}
</script>
{% endblock %}

{% block content %}
<section class="hero">
  <div class="container">
    <h1>{{ title }}</h1>
    <p class="subtitle">{{ description }}</p>
    <div class="blog-post-meta">
      <time datetime="{{ date | dateToRfc3339 }}">{{ date | readableDate }}</time>
    </div>
    {% if tags %}
    <div class="blog-tags">
      {% for tag in tags %}{% if tag != "blog" %}
      <span class="blog-tag-chip">{{ tag }}</span>
      {% endif %}{% endfor %}
    </div>
    {% endif %}
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">
      {{ content | safe }}
    </div>
  </div>
</section>
{% endblock %}
```

**Design decision — standalone JSON-LD:** `base.njk` already emits a `@graph` with WebSite + WebPage. The BlogPosting goes in a separate `<script type="application/ld+json">` block in `{% block extraHead %}`. Google handles multiple JSON-LD blocks correctly. This avoids modifying the existing `@graph` structure.

**Design decision — `site.author`:** Add `"author": { "name": "FOUNDER_NAME" }` to `site.json` (resolve placeholder during implementation). Referenced in the template as `{{ site.author.name }}`. This is the simplest approach that avoids hardcoding the name in the template.

### Phase 3: Blog Listing Page

**Create** `plugins/soleur/docs/pages/blog.njk`:

```njk
---
title: Blog
description: "Insights on agentic engineering, company-as-a-service, and building at scale with AI teams."
layout: base.njk
permalink: blog/index.html
---

<section class="page-hero">
  <div class="container">
    <h1>Blog</h1>
    <p>{{ description }}</p>
  </div>
</section>

<div class="container">
  {% if collections.blog and collections.blog.length > 0 %}
  <div class="catalog-grid">
    {% for post in collections.blog | reverse %}
    <a href="{{ post.url }}" class="component-card">
      <div class="card-header">
        <span class="card-dot" style="background: var(--color-accent)"></span>
        <span class="card-category">{{ post.date | readableDate }}</span>
      </div>
      <h3 class="card-title">{{ post.data.title }}</h3>
      <p class="card-description">{{ post.data.description }}</p>
    </a>
    {% endfor %}
  </div>
  {% else %}
  <section class="category-section">
    <p style="color: var(--color-text-secondary); text-align: center; padding: var(--space-16) 0;">
      Blog posts are coming soon. Follow our journey on <a href="{{ site.discord }}">Discord</a>.
    </p>
  </section>
  {% endif %}
</div>
```

### Phase 4: RSS Feed

**Install** `@11ty/eleventy-plugin-rss`:

```bash
npm install @11ty/eleventy-plugin-rss --save-dev
```

**Update** `eleventy.config.js`:

```js
import { feedPlugin } from "@11ty/eleventy-plugin-rss";

export default function (eleventyConfig) {
  eleventyConfig.addPlugin(feedPlugin, {
    type: "atom",
    outputPath: "/blog/feed.xml",
    collection: {
      name: "blog",
      limit: 20,
    },
    metadata: {
      language: "en",
      title: "Soleur Blog",
      subtitle: "Insights on agentic engineering and company-as-a-service",
      base: "https://soleur.ai/",
      author: {
        name: "Soleur",
      },
    },
  });

  // Rename manual filter to avoid conflict with RSS plugin's dateToRfc3339
  eleventyConfig.addFilter("dateToShort", (dateObj) => {
    return new Date(dateObj).toISOString().split("T")[0];
  });

  // Human-readable date filter
  eleventyConfig.addFilter("readableDate", (dateObj) => {
    return new Date(dateObj).toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  });

  // ... existing passthrough config
}
```

**Filter conflict resolution:** The existing manual `dateToRfc3339` filter in `eleventy.config.js` produces `YYYY-MM-DD` (not actual RFC 3339). The RSS plugin provides a correct `dateToRfc3339`. **Rename the manual filter to `dateToShort`** and update any templates that used it for display purposes (sitemap uses it — verify). Add a new `readableDate` filter for human-friendly dates in blog templates.

### Phase 5: Content-Writer Alignment + Blog CSS + Build Verification

**Update** `plugins/soleur/skills/content-writer/SKILL.md`:
- Change default layout from `post.njk` to `blog-post.njk`
- Change default output path to `plugins/soleur/docs/blog/`
- Change schema type from `Article` to `BlogPosting`
- Remove inline JSON-LD generation (layout handles it)

**Update** `plugins/soleur/docs/css/style.css` — add to `@layer components`:

```css
/* Blog tag chips */
.blog-tag-chip {
  display: inline-block;
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  text-transform: lowercase;
  padding: 4px 12px;
  border-radius: 4px;
  background: var(--color-bg-tertiary);
  color: var(--color-text-secondary);
}

.blog-tags {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  margin-top: var(--space-2);
}

.blog-post-meta {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin-top: var(--space-2);
  color: var(--color-text-secondary);
  font-size: var(--text-sm);
}
```

**Build and verify:**

```bash
cd /path/to/worktree
npm install
npx @11ty/eleventy --input=plugins/soleur/docs --output=_site
# Verify blog/ directory in output
ls _site/blog/
# Run SEO validation
bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
```

## Rollback Plan

All changes are additive except the article→blog rename. To rollback:

1. Revert the commit — restores `articles/articles.json`, `pages/articles.njk`, `_includes/article.njk`
2. Remove `@11ty/eleventy-plugin-rss` from devDependencies
3. No data migration needed — zero blog posts exist

## Technical Considerations

### Architecture

- **Clean URL pattern:** `permalink: "blog/{{ page.fileSlug }}/index.html"` creates directory-based clean URLs (`/blog/my-post/`). GitHub Pages serves `foo/index.html` at `foo/` with trailing slash redirect.
- **`base.njk` gets two blocks:** `{% block extraHead %}` for head injection AND `{% block content %}` wrapping `{{ content | safe }}`. Both are backwards-compatible — existing templates that don't define these blocks work unchanged because Nunjucks falls through to the default block content.
- **Standalone BlogPosting JSON-LD:** A second `<script type="application/ld+json">` alongside `base.njk`'s `@graph`. Google handles multiple JSON-LD blocks. Avoids modifying the existing `@graph` structure.
- **Nav active state uses `startsWith`:** `page.url.startsWith('/blog')` instead of exact match, so "Blog" highlights on both listing and post pages.
- **`dateToRfc3339` renamed to `dateToShort`:** The manual filter produced `YYYY-MM-DD` (not actual RFC 3339). Renamed to avoid conflict with the RSS plugin's correct `dateToRfc3339` filter. All existing template references updated.

### Gotchas from Learnings

- **Nunjucks frontmatter:** Do NOT use `{{ variables }}` in YAML frontmatter — they render as literal text. Use `eleventyComputed` or template-body `{% set %}` blocks.
- **page.url already has leading slash:** `{{ site.url }}{{ page.url }}` is correct. No extra `/` separator.
- **CSS variables:** Use `--color-accent` not `--accent`.
- **npm install in worktree:** Required before building. Verify: `ls node_modules/@11ty/eleventy/package.json`.
- **Build from repo root:** `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`.

## Acceptance Criteria

- [ ] Blog listing page renders at `/blog/` (clean URL, no `.html`)
- [ ] Individual posts render at `/blog/{slug}/` (clean URL)
- [ ] RSS/Atom feed renders at `/blog/feed.xml`
- [ ] Blog post `<head>` contains correct OG meta tags with `og:type: article`
- [ ] Blog post `<head>` contains `BlogPosting` JSON-LD with Person author
- [ ] Navigation says "Blog" linking to `/blog/` (desktop + mobile + footer)
- [ ] Nav highlights "Blog" on both listing page and individual post pages
- [ ] `llms.txt` references "Blog" instead of "Articles"
- [ ] Content-writer skill outputs aligned with blog infrastructure
- [ ] Eleventy build passes: `npx @11ty/eleventy --input=plugins/soleur/docs`
- [ ] SEO validation passes: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] No `dateToRfc3339` filter conflict (manual filter renamed to `dateToShort`)
- [ ] `readableDate` filter renders human-friendly dates

## Test Scenarios

- Given no blog posts exist, when visiting `/blog/`, then the empty state message displays
- Given a blog post exists, when fetching `/blog/feed.xml`, then valid Atom XML is returned with the post
- Given a blog post is shared on social media, when the OG tags are parsed, then `og:type` is `article` and title/description are correct
- Given `npx @11ty/eleventy` runs, when build completes, then `/blog/` directory exists in `_site/` with clean URL structure
- Given a user visits `/pages/articles.html`, then they are redirected to `/blog/`

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| `dateToRfc3339` filter rename breaks existing templates | Search for all `dateToRfc3339` usages and update to `dateToShort` or `readableDate` |
| Clean URL pattern breaks `aria-current` in nav | Phase 1 adds `startsWith` comparison |
| Content-writer skill changes break existing workflows | Backwards-compatible: new defaults, old format still works |
| `{% block content %}` addition breaks existing templates | Backwards-compatible: Nunjucks falls through to default block content when not overridden |

## References & Research

### Internal References

- Spec: `knowledge-base/specs/feat-blog-infrastructure/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-03-04-blog-infrastructure-brainstorm.md`
- Existing articles: `plugins/soleur/docs/articles/articles.json`, `plugins/soleur/docs/pages/articles.njk`, `plugins/soleur/docs/_includes/article.njk`
- Eleventy config: `eleventy.config.js`
- CSS: `plugins/soleur/docs/css/style.css:779` (`.prose` class)
- Base layout: `plugins/soleur/docs/_includes/base.njk`
- Nav config: `plugins/soleur/docs/_data/site.json`
- Content-writer: `plugins/soleur/skills/content-writer/SKILL.md`

### Learnings Applied

- `knowledge-base/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md` — frontmatter variable resolution, page.url slash
- `knowledge-base/learnings/build-errors/eleventy-seo-aeo-patterns.md` — build-time rendering mandatory
- `knowledge-base/learnings/ui-bugs/2026-02-21-prose-utility-class-and-eleventy-build-patterns.md` — `.prose` class reuse
- `knowledge-base/learnings/2026-02-22-docs-site-css-variable-inconsistency.md` — use `--color-accent` not `--accent`

### Related Work

- PR #428: Original articles system delivery
- Issue #431: Blog infrastructure feature request
- PR #437: This feature's draft PR
