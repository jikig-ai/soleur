# Tasks: Blog Infrastructure for SEO/AEO

Issue: #431
Branch: feat-blog-infrastructure
Plan: `knowledge-base/plans/2026-03-04-feat-blog-infrastructure-plan.md`

## Phase 1: Foundation (Rename + Clean URLs)

- [ ] 1.1 Delete `plugins/soleur/docs/articles/articles.json`
- [ ] 1.2 Delete `plugins/soleur/docs/pages/articles.njk`
- [ ] 1.3 Delete `plugins/soleur/docs/_includes/article.njk`
- [ ] 1.4 Create `plugins/soleur/docs/blog/blog.json` with `tags: "blog"`, `layout: "blog-post.njk"`, `permalink: "blog/{{ page.fileSlug }}/index.html"`
- [ ] 1.5 Update `plugins/soleur/docs/_data/site.json` — rename "Articles" → "Blog", URL → `blog/`, add `author` object
- [ ] 1.6 Update `plugins/soleur/docs/llms.txt.njk` — replace "Articles" with "Blog"
- [ ] 1.7 Create redirect `plugins/soleur/docs/pages/articles.njk` — meta refresh to `/blog/`, `eleventyExcludeFromCollections: true`
- [ ] 1.8 Update `base.njk` nav active state — `startsWith('/blog')` instead of exact URL match

## Phase 2: Blog Post Layout

- [ ] 2.1 Create `plugins/soleur/docs/_includes/blog-post.njk` extending `base.njk`
  - [ ] 2.1.1 BlogPosting JSON-LD with Person author + Organization publisher
  - [ ] 2.1.2 Hero section with title, description, date, type badge
  - [ ] 2.1.3 Tag chips linking to `/blog/tag/{tag}/`
  - [ ] 2.1.4 Content area with `.prose` class wrapper
- [ ] 2.2 Update `plugins/soleur/docs/_includes/base.njk`:
  - [ ] 2.2.1 Add `{% block extraHead %}{% endblock %}` before `</head>`
  - [ ] 2.2.2 Replace hardcoded `og:type` with `{{ ogType | default('website') }}`
  - [ ] 2.2.3 Add RSS auto-discovery `<link>` in `<head>`
- [ ] 2.3 Add `ogType: "article"` to `blog.json` data cascade

## Phase 3: Blog Listing Page

- [ ] 3.1 Create `plugins/soleur/docs/pages/blog.njk` with `permalink: blog/index.html`
  - [ ] 3.1.1 Page hero with title and description
  - [ ] 3.1.2 Filter tabs (All, Articles, Updates, Tutorials) with client-side JS toggle + ARIA `tablist`/`tab`/`tabpanel` roles
  - [ ] 3.1.3 Card grid using `.catalog-grid` + `.component-card` classes
  - [ ] 3.1.4 Empty state message when no posts
  - [ ] 3.1.5 Each card shows date, type badge, title, description, tags

## Phase 4: Tag Index Pages

- [ ] 4.1 Add `blogTags` custom collection to `eleventy.config.js` (filters non-blog tags)
- [ ] 4.2 Create `plugins/soleur/docs/pages/blog-tag.njk` using Eleventy pagination over `blogTags`
  - [ ] 4.2.1 Permalink: `blog/tag/{{ tag | slugify }}/index.html`
  - [ ] 4.2.2 Card grid listing posts with the selected tag
  - [ ] 4.2.3 Back link to `/blog/`

## Phase 5: RSS Feed

- [ ] 5.1 Install `@11ty/eleventy-plugin-rss` as devDependency
- [ ] 5.2 Configure `feedPlugin` in `eleventy.config.js` with Atom output at `/blog/feed.xml`
- [ ] 5.3 Resolve `dateToRfc3339` filter name conflict (remove manual filter if RSS plugin provides it, or rename)
- [ ] 5.4 Add `readableDate` filter to `eleventy.config.js` for human-friendly dates

## Phase 6: Blog CSS

- [ ] 6.1 Add blog-specific styles to `plugins/soleur/docs/css/style.css` under `@layer components`
  - [ ] 6.1.1 `.blog-filter-tabs` + `.blog-filter-tab` + `.active` state
  - [ ] 6.1.2 `.blog-type-badge` + type-specific color variants
  - [ ] 6.1.3 `.blog-tag-chip` + `.blog-tag-chip-sm` + hover state
  - [ ] 6.1.4 `.blog-tags` flex container
  - [ ] 6.1.5 `.blog-post-meta` for date + type badge layout
  - [ ] 6.1.6 GEO/AEO classes: `.geo-citation`, `.geo-statistic`, `.geo-quote`

## Phase 7: Content-Writer Alignment

- [ ] 7.1 Update `plugins/soleur/skills/content-writer/SKILL.md` — default layout to `blog-post.njk`
- [ ] 7.2 Update default output path to `plugins/soleur/docs/blog/`
- [ ] 7.3 Update schema type from `Article` to `BlogPosting`
- [ ] 7.4 Add `type` and `author` to default frontmatter template

## Phase 8: Build Verification

- [ ] 8.1 Run `npm install` in worktree
- [ ] 8.2 Run `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site`
- [ ] 8.3 Verify `/blog/` directory exists in `_site/`
- [ ] 8.4 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] 8.5 Verify nav active state works with `/blog/` URL
- [ ] 8.6 Test blog listing empty state renders correctly
- [ ] 8.7 Create a test blog post and verify individual post renders
- [ ] 8.8 Verify RSS feed outputs valid XML
- [ ] 8.9 Verify tag page generates for test post's tags
