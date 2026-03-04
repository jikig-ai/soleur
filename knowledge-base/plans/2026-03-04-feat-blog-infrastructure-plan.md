---
title: "feat: Blog Infrastructure for SEO/AEO"
type: feat
date: 2026-03-04
---

# feat: Blog Infrastructure for SEO/AEO

## Overview

Rename the existing `articles/` system (PR #428) to `blog/` and add missing infrastructure: RSS feed, clean URLs, Open Graph overrides, tag index pages, GEO/AEO template features, and `BlogPosting` Schema.org structured data. Zero articles exist — rename is cost-free now.

## Problem Statement / Motivation

PR #428 delivered article infrastructure under non-standard naming (`/pages/articles.html`, `/articles/{slug}.html`). Every SaaS competitor uses `/blog/` (Vercel, Supabase, Linear, Stripe). LLMs expect `/blog/` for AEO discoverability. Current URLs leak Eleventy internals (`/pages/`, `.html` extensions). Missing RSS blocks content distribution to developer RSS readers and AI training pipelines. Missing tags prevent SEO topical clustering. The window for a cost-free rename closes the moment the first article ships.

## Proposed Solution

### Phase 1: Rename and Clean URLs (Foundation)

Remove old articles system and create blog directory structure with clean URLs.

**Files:**

1. **Delete** `plugins/soleur/docs/articles/articles.json`
2. **Delete** `plugins/soleur/docs/pages/articles.njk`
3. **Delete** `plugins/soleur/docs/_includes/article.njk`
4. **Create** `plugins/soleur/docs/blog/blog.json` — collection data cascade:

```json
{
  "tags": "blog",
  "layout": "blog-post.njk",
  "permalink": "blog/{{ page.fileSlug }}/index.html"
}
```

Note: `permalink: "blog/{{ page.fileSlug }}/index.html"` renders as `/blog/my-post/` — Eleventy's clean URL pattern. The trailing `/index.html` is the file on disk; browsers see `/blog/my-post/`.

5. **Update** `plugins/soleur/docs/_data/site.json` — rename nav/footer "Articles" → "Blog", URL → `blog/`. Also add author data:

```json
{
  "label": "Blog", "url": "blog/"
}
```

Add author object to `site.json`:
```json
{
  "author": {
    "name": "FOUNDER_NAME",
    "url": "https://soleur.ai"
  }
}
```

6. **Update** `plugins/soleur/docs/llms.txt.njk` — replace "Articles" references with "Blog"

7. **Create redirect** from old URL — `plugins/soleur/docs/pages/articles.njk` with meta refresh:

```njk
---
permalink: pages/articles.html
eleventyExcludeFromCollections: true
---
<!DOCTYPE html>
<html><head><meta http-equiv="refresh" content="0;url=/blog/"></head></html>
```

8. **Update** `base.njk` nav active state logic — change from exact match to `startsWith`:

```njk
{# Before #}
{% if page.url == ('/' + item.url) %}
{# After #}
{% if page.url == ('/' + item.url) or (item.url == 'blog/' and page.url.startsWith('/blog')) %}
```

### Phase 2: Blog Post Layout (Core Template)

Create the blog post layout with BlogPosting schema, OG overrides, and GEO/AEO structural classes.

**First, update `base.njk`** — add `{% block extraHead %}{% endblock %}` before `</head>`:

```njk
    {% block extraHead %}{% endblock %}
  </head>
```

**Create** `plugins/soleur/docs/_includes/blog-post.njk`:

```njk
---
layout: base.njk
---
{% block extraHead %}
<meta property="og:type" content="article" />
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
    "name": "{{ author | default('FOUNDER_NAME') }}"
  },
  "publisher": {
    "@type": "Organization",
    "name": "{{ site.name }}",
    "url": "{{ site.url }}"
  }
}
</script>

<section class="hero">
  <div class="container">
    <h1>{{ title }}</h1>
    <p class="subtitle">{{ description }}</p>
    <div class="blog-post-meta">
      <time datetime="{{ date | dateToRfc3339 }}">{{ date | dateToRfc3339 }}</time>
      {% if type %}<span class="blog-type-badge blog-type-{{ type }}">{{ type }}</span>{% endif %}
    </div>
    {% if tags %}
    <div class="blog-tags">
      {% for tag in tags %}{% if tag != "blog" %}
      <a href="/blog/tag/{{ tag | slugify }}/" class="blog-tag-chip">{{ tag }}</a>
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
```

**OG type override:** `base.njk` hardcodes `og:type` to `"website"`. Two options:
- **Option A (simple):** Add a conditional in `base.njk`: `<meta property="og:type" content="{{ ogType | default('website') }}" />` — blog posts set `ogType: "article"` in frontmatter via `blog.json` or individual posts.
- **Option B (no base change):** Accept `og:type: website` for blog posts. Not ideal but functional.

Recommend **Option A** — minimal change to `base.njk`, big SEO benefit.

**GEO/AEO structural CSS classes** (used in article markdown via HTML):
- `.geo-citation` — styled blockquote for source citations
- `.geo-statistic` — highlighted stat callout
- `.geo-quote` — expert quotation with attribution

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
  {# Filter tabs #}
  <div class="blog-filter-tabs">
    <button class="blog-filter-tab active" data-filter="all">All</button>
    <button class="blog-filter-tab" data-filter="article">Articles</button>
    <button class="blog-filter-tab" data-filter="update">Updates</button>
    <button class="blog-filter-tab" data-filter="tutorial">Tutorials</button>
  </div>

  {% if collections.blog and collections.blog.length > 0 %}
  <div class="catalog-grid" id="blog-grid">
    {% for post in collections.blog | reverse %}
    <a href="{{ post.url }}" class="component-card blog-card" data-type="{{ post.data.type | default('article') }}">
      <div class="card-header">
        <span class="card-dot" style="background: var(--color-accent)"></span>
        <span class="card-category">{{ post.date | dateToRfc3339 }}</span>
        {% if post.data.type %}
        <span class="blog-type-badge blog-type-{{ post.data.type }}">{{ post.data.type }}</span>
        {% endif %}
      </div>
      <h3 class="card-title">{{ post.data.title }}</h3>
      <p class="card-description">{{ post.data.description }}</p>
      {% if post.data.tags %}
      <div class="blog-tags">
        {% for tag in post.data.tags %}{% if tag != "blog" %}
        <span class="blog-tag-chip-sm">{{ tag }}</span>
        {% endif %}{% endfor %}
      </div>
      {% endif %}
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

{# Filter JS — minimal, no framework #}
<script>
document.querySelectorAll('.blog-filter-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.blog-filter-tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    const filter = tab.dataset.filter;
    document.querySelectorAll('.blog-card').forEach(card => {
      card.style.display = (filter === 'all' || card.dataset.type === filter) ? '' : 'none';
    });
  });
});
</script>
```

### Phase 4: Tag Index Pages

**Create** `plugins/soleur/docs/pages/blog-tag.njk` — uses Eleventy pagination to generate a page per tag:

```njk
---
pagination:
  data: collections
  size: 1
  alias: tag
  filter:
    - all
    - blog
    - articles
permalink: "blog/tag/{{ tag | slugify }}/index.html"
layout: base.njk
eleventyComputed:
  title: "Posts tagged '{{ tag }}'"
  description: "Blog posts tagged with {{ tag }}"
---

<section class="page-hero">
  <div class="container">
    <h1>Tagged: {{ tag }}</h1>
    <p><a href="/blog/">← Back to all posts</a></p>
  </div>
</section>

<div class="container">
  <div class="catalog-grid">
    {% for post in collections[tag] | reverse %}
    <a href="{{ post.url }}" class="component-card blog-card">
      <div class="card-header">
        <span class="card-dot" style="background: var(--color-accent)"></span>
        <span class="card-category">{{ post.date | dateToRfc3339 }}</span>
      </div>
      <h3 class="card-title">{{ post.data.title }}</h3>
      <p class="card-description">{{ post.data.description }}</p>
    </a>
    {% endfor %}
  </div>
</div>
```

**Update** `eleventy.config.js` — add a custom collection for blog tags to avoid generating pages for non-blog tags:

```js
eleventyConfig.addCollection("blogTags", function(collection) {
  const tagSet = new Set();
  collection.getFilteredByTag("blog").forEach(item => {
    (item.data.tags || []).forEach(tag => {
      if (tag !== "blog") tagSet.add(tag);
    });
  });
  return [...tagSet].sort();
});
```

Then update `blog-tag.njk` to paginate over `collections.blogTags` instead of `collections`.

### Phase 5: RSS Feed

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
  // ... existing config
}
```

**Add** `<link>` in `base.njk` `<head>`:

```html
<link rel="alternate" type="application/atom+xml" title="Soleur Blog" href="/blog/feed.xml" />
```

### Phase 6: OG Type Override + Blog CSS

**Update** `plugins/soleur/docs/_includes/base.njk`:
- Replace hardcoded `og:type` with `{{ ogType | default('website') }}`
- Blog posts will set `ogType: "article"` via computed data or `blog.json`

**Update** `plugins/soleur/docs/css/style.css` — add to `@layer components`:

```css
/* Blog filter tabs */
.blog-filter-tabs {
  display: flex;
  gap: var(--space-3);
  margin-bottom: var(--space-6);
  border-bottom: 1px solid var(--color-border);
  padding-bottom: var(--space-3);
}

.blog-filter-tab {
  background: none;
  border: none;
  color: var(--color-text-secondary);
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  cursor: pointer;
  padding: var(--space-2) var(--space-3);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.blog-filter-tab.active {
  color: var(--color-accent);
  border-bottom: 2px solid var(--color-accent);
}

/* Blog type badges */
.blog-type-badge {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 2px 8px;
  border-radius: 4px;
  background: var(--color-bg-tertiary);
  color: var(--color-text-secondary);
}

.blog-type-article { color: var(--cat-engineering); }
.blog-type-update { color: var(--cat-product); }
.blog-type-tutorial { color: var(--cat-operations); }

/* Blog tag chips */
.blog-tag-chip, .blog-tag-chip-sm {
  display: inline-block;
  font-family: var(--font-mono);
  text-transform: lowercase;
  border-radius: 4px;
  background: var(--color-bg-tertiary);
  color: var(--color-text-secondary);
  text-decoration: none;
}

.blog-tag-chip {
  font-size: var(--text-sm);
  padding: 4px 12px;
}

.blog-tag-chip-sm {
  font-size: var(--text-xs);
  padding: 2px 8px;
}

.blog-tag-chip:hover {
  color: var(--color-accent);
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

/* GEO/AEO structural classes */
.geo-citation {
  border-left: 3px solid var(--color-accent);
  padding: var(--space-3) var(--space-4);
  margin: var(--space-4) 0;
  background: var(--color-bg-secondary);
  border-radius: 0 8px 8px 0;
  font-size: var(--text-sm);
}

.geo-citation cite {
  display: block;
  margin-top: var(--space-2);
  color: var(--color-text-tertiary);
  font-style: normal;
}

.geo-statistic {
  display: inline-block;
  padding: var(--space-2) var(--space-3);
  background: var(--color-bg-tertiary);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-family: var(--font-mono);
  font-size: var(--text-lg);
  color: var(--color-accent);
  margin: var(--space-3) 0;
}

.geo-quote {
  border-left: 3px solid var(--color-accent);
  padding: var(--space-4);
  margin: var(--space-4) 0;
  background: var(--color-bg-secondary);
  border-radius: 0 8px 8px 0;
  font-style: italic;
}

.geo-quote .attribution {
  display: block;
  margin-top: var(--space-2);
  font-style: normal;
  font-weight: 600;
  color: var(--color-text-secondary);
}
```

### Phase 7: Content-Writer Alignment + Build Verification

**Update** `plugins/soleur/skills/content-writer/SKILL.md`:
- Change default layout from `post.njk` to `blog-post.njk`
- Change default output path to `plugins/soleur/docs/blog/`
- Change schema type from `Article` to `BlogPosting`
- Add `type` and `author` to default frontmatter

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

## SpecFlow Findings (Incorporated)

SpecFlow identified 33 gaps and 4 conflicts. Critical items addressed in this plan:

1. **`base.njk` needs `{% block extraHead %}`** — Required for blog-specific OG tags, JSON-LD, and RSS auto-discovery. Backwards-compatible: no existing template defines this block. Added to Phase 2.
2. **Author data model undefined** — Add `site.author` object to `site.json` with name and URL. Used by BlogPosting schema.
3. **Redirect from `pages/articles.html`** — Create a meta-refresh redirect to `/blog/`. Added to Phase 1.
4. **`readableDate` filter needed** — ISO dates are not user-friendly. Add a human-readable date filter. Added to Phase 5 (eleventy.config.js).
5. **Filter tabs need ARIA roles** — `tablist`, `tab`, `tabpanel` for accessibility. Updated Phase 3 template.
6. **Nav active state for blog posts** — Current `aria-current` uses exact URL match. Blog posts at `/blog/slug/` won't highlight "Blog" nav item. Use `startsWith` comparison. Added to Phase 1.
7. **Dual JSON-LD** — BlogPosting goes in `{% block extraHead %}`, integrated into the existing `@graph` or as a standalone block. Content-writer must stop generating inline JSON-LD (defers to layout).
8. **RSS feed excluded from sitemap** — Add `eleventyExcludeFromCollections: true` to feed template.
9. **Tag convention** — Enforce lowercase-with-hyphens in frontmatter; document in content-writer skill.

## Technical Considerations

### Architecture

- **Clean URL pattern:** `permalink: "blog/{{ page.fileSlug }}/index.html"` creates directory-based clean URLs (`/blog/my-post/`). This differs from the existing `pages/{name}.html` pattern but is correct for modern blog URLs. GitHub Pages serves `foo/index.html` at `foo/` with trailing slash redirect.
- **`base.njk` gets `{% block extraHead %}`:** Enables blog templates to inject OG overrides and JSON-LD into `<head>`. Backwards-compatible since no existing template uses Nunjucks blocks.
- **Tag pagination uses custom `blogTags` collection:** Avoids generating pages for internal Eleventy tags like "blog". Only topical tags from blog posts get index pages.
- **Filter tabs are client-side JS with ARIA:** Simple `display: none` toggle with `role="tablist"`, `role="tab"`, `aria-selected`. No framework needed. All posts visible with JS disabled.
- **Nav active state uses `startsWith`:** `page.url.startsWith('/blog')` instead of exact match, so "Blog" highlights on both listing and post pages.

### Gotchas from Learnings

- **Nunjucks frontmatter:** Do NOT use `{{ variables }}` in YAML frontmatter — they render as literal text. Use `eleventyComputed` or template-body `{% set %}` blocks.
- **page.url already has leading slash:** `{{ site.url }}{{ page.url }}` is correct. No extra `/` separator.
- **CSS variables:** Use `--color-accent` not `--accent`.
- **npm install in worktree:** Required before building. Verify: `ls node_modules/@11ty/eleventy/package.json`.
- **Build from repo root:** `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`.
- **Grid divisibility rule:** Blog card grid at 3+ breakpoints must satisfy `cards % columns == 0`.

### RSS Plugin Considerations

- `@11ty/eleventy-plugin-rss` v5+ (for Eleventy v3) uses ESM and the `feedPlugin` export
- The plugin provides `absoluteUrl` and `dateToRfc3339` filters — the manual `dateToRfc3339` filter in `eleventy.config.js` will conflict. Remove the manual one after adding the plugin, OR rename one.

## Acceptance Criteria

- [ ] Blog listing page renders at `/blog/` (clean URL, no `.html`)
- [ ] Individual posts render at `/blog/{slug}/` (clean URL)
- [ ] Filter tabs on listing page toggle between All, Articles, Updates, Tutorials
- [ ] Tag index pages render at `/blog/tag/{tag-name}/`
- [ ] RSS/Atom feed renders at `/blog/feed.xml`
- [ ] Blog post `<head>` contains correct OG meta tags with `og:type: article`
- [ ] Blog post body contains `BlogPosting` JSON-LD with Person author
- [ ] Navigation says "Blog" linking to `/blog/` (desktop + mobile + footer)
- [ ] `llms.txt` references "Blog" instead of "Articles"
- [ ] GEO/AEO CSS classes (`.geo-citation`, `.geo-statistic`, `.geo-quote`) render correctly
- [ ] Content-writer skill outputs aligned with blog infrastructure
- [ ] Eleventy build passes: `npx @11ty/eleventy --input=plugins/soleur/docs`
- [ ] SEO validation passes: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] No `dateToRfc3339` filter conflict between manual filter and RSS plugin

## Test Scenarios

- Given no blog posts exist, when visiting `/blog/`, then the empty state message displays
- Given a blog post with `type: tutorial`, when visiting `/blog/`, then clicking "Tutorials" tab shows only that post
- Given a blog post tagged `agentic-engineering`, when visiting `/blog/tag/agentic-engineering/`, then the post appears in the listing
- Given a blog post exists, when fetching `/blog/feed.xml`, then valid Atom XML is returned with the post
- Given a blog post is shared on social media, when the OG tags are parsed, then `og:type` is `article` and title/description are correct
- Given `npx @11ty/eleventy` runs, when build completes, then `/blog/` directory exists in `_site/` with clean URL structure

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| `dateToRfc3339` filter name conflict with RSS plugin | Check RSS plugin's filter names; rename if needed |
| Tag pagination generates pages for non-blog tags | Use custom `blogTags` collection to filter |
| Clean URL pattern breaks `aria-current` in nav | Verify nav active state works with `/blog/` URL |
| Content-writer skill changes break existing workflows | Backwards-compatible: new defaults, old format still works |

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
- `knowledge-base/learnings/2026-02-20-geo-aeo-methodology-incorporation.md` — GEO techniques (+30-40% AI visibility)
- `knowledge-base/learnings/2026-02-22-docs-site-css-variable-inconsistency.md` — use `--color-accent` not `--accent`
- `knowledge-base/learnings/2026-02-22-landing-page-grid-orphan-regression.md` — grid divisibility rule

### Related Work

- PR #428: Original articles system delivery
- Issue #431: Blog infrastructure feature request
- PR #437: This feature's draft PR
