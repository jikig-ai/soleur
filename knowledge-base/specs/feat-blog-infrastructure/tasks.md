# Tasks: Blog Infrastructure for SEO/AEO

Issue: #431
Branch: feat-blog-infrastructure
Plan: `knowledge-base/plans/2026-03-04-feat-blog-infrastructure-plan.md`

## Phase 1: Foundation (Rename + Clean URLs)

- [ ] 1.1 Delete `plugins/soleur/docs/articles/articles.json`
- [ ] 1.2 Delete `plugins/soleur/docs/_includes/article.njk`
- [ ] 1.3 Replace `plugins/soleur/docs/pages/articles.njk` with redirect to `/blog/` (meta refresh, `eleventyExcludeFromCollections: true`)
- [ ] 1.4 Create `plugins/soleur/docs/blog/blog.json` with `tags: "blog"`, `layout: "blog-post.njk"`, `permalink: "blog/{{ page.fileSlug }}/index.html"`, `ogType: "article"`
- [ ] 1.5 Update `plugins/soleur/docs/_data/site.json` — rename nav + footerLinks "Articles" → "Blog", URL → `blog/`, add `author` object
- [ ] 1.6 Update `plugins/soleur/docs/llms.txt.njk` — replace "Articles" with "Blog"
- [ ] 1.7 Update `base.njk` nav active state — `startsWith('/blog')` instead of exact URL match

## Phase 2: Blog Post Layout

- [ ] 2.1 Update `plugins/soleur/docs/_includes/base.njk`:
  - [ ] 2.1.1 Add `{% block extraHead %}{% endblock %}` before `</head>`
  - [ ] 2.1.2 Wrap body content in `{% block content %}{{ content | safe }}{% endblock %}`
  - [ ] 2.1.3 Replace hardcoded `og:type` with `{{ ogType | default('website') }}`
  - [ ] 2.1.4 Add RSS auto-discovery `<link>` in `<head>`
- [ ] 2.2 Create `plugins/soleur/docs/_includes/blog-post.njk` extending `base.njk`
  - [ ] 2.2.1 `{% block extraHead %}` with OG article meta + standalone BlogPosting JSON-LD
  - [ ] 2.2.2 `{% block content %}` with hero section (title, description, readable date)
  - [ ] 2.2.3 Tag chips as plain text labels (no links)
  - [ ] 2.2.4 Content area with `.prose` class wrapper

## Phase 3: Blog Listing Page

- [ ] 3.1 Create `plugins/soleur/docs/pages/blog.njk` with `permalink: blog/index.html`
  - [ ] 3.1.1 Page hero with title and description
  - [ ] 3.1.2 Flat reverse-chronological card grid using `.catalog-grid` + `.component-card`
  - [ ] 3.1.3 Each card shows readable date, title, description
  - [ ] 3.1.4 Empty state message when no posts

## Phase 4: RSS Feed

- [ ] 4.1 Install `@11ty/eleventy-plugin-rss` as devDependency
- [ ] 4.2 Configure `feedPlugin` in `eleventy.config.js` with Atom output at `/blog/feed.xml`
- [ ] 4.3 Rename manual `dateToRfc3339` filter to `dateToShort` (avoids conflict with RSS plugin)
- [ ] 4.4 Add `readableDate` filter to `eleventy.config.js` for human-friendly dates
- [ ] 4.5 Update any templates referencing old `dateToRfc3339` to use `dateToShort` or `readableDate`

## Phase 5: Content-Writer Alignment + Blog CSS + Build Verification

- [ ] 5.1 Update `plugins/soleur/skills/content-writer/SKILL.md`:
  - [ ] 5.1.1 Default layout to `blog-post.njk`
  - [ ] 5.1.2 Default output path to `plugins/soleur/docs/blog/`
  - [ ] 5.1.3 Schema type from `Article` to `BlogPosting`
  - [ ] 5.1.4 Remove inline JSON-LD generation (layout handles it)
- [ ] 5.2 Add blog CSS to `plugins/soleur/docs/css/style.css` under `@layer components`:
  - [ ] 5.2.1 `.blog-tag-chip` styling
  - [ ] 5.2.2 `.blog-tags` flex container
  - [ ] 5.2.3 `.blog-post-meta` for date layout
- [ ] 5.3 Run `npm install` in worktree
- [ ] 5.4 Run `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`
- [ ] 5.5 Verify `/blog/` directory exists in `_site/`
- [ ] 5.6 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] 5.7 Verify nav active state works on blog listing + post pages
- [ ] 5.8 Test blog listing empty state renders correctly
- [ ] 5.9 Create a test blog post and verify individual post renders
- [ ] 5.10 Verify RSS feed outputs valid XML
- [ ] 5.11 Verify redirect from `/pages/articles.html` to `/blog/`
