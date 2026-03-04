# Spec: Blog Infrastructure for SEO/AEO

Issue: #431
Branch: feat-blog-infrastructure
Date: 2026-03-04

## Problem Statement

PR #428 delivered an `articles/` content system but used non-standard URL paths (`/pages/articles.html`, `/articles/{slug}.html`), missed several infrastructure requirements (RSS, tags, OG tags, clean URLs), and used the less SEO-friendly "articles" naming instead of the universally recognized "blog" convention. With zero content published, the rename is cost-free now but increasingly expensive later.

## Goals

- G1: Blog content renders at clean URLs (`/blog/`, `/blog/{slug}`)
- G2: RSS feed available for content distribution and AI training pipeline ingestion
- G3: Tag-based content clustering for SEO topical authority
- G4: Social sharing produces rich preview cards via Open Graph meta tags
- G5: Schema.org `BlogPosting` with named author for E-E-A-T signals
- G6: Blog templates structurally support GEO/AEO best practices
- G7: Nav, llms.txt, and all references updated consistently

## Non-Goals

- Writing actual blog content (separate effort)
- Email capture / newsletter subscription
- CMS or admin interface
- Comment system
- Search functionality within blog

## Functional Requirements

- FR1: Blog listing page renders at `/blog/` showing all posts reverse-chronologically
- FR2: Individual posts render at `/blog/{slug}` (no `.html` extension)
- FR3: Listing page has filter tabs for content types (articles, updates, tutorials)
- FR4: Posts support frontmatter: title, description, date, type, tags, author
- FR5: Tag index pages render at `/blog/tag/{tag-name}` listing all posts with that tag
- FR6: RSS feed renders at `/blog/feed.xml` with full post content
- FR7: Open Graph meta tags (og:title, og:description, og:type, og:url) in blog post `<head>`
- FR8: Schema.org `BlogPosting` JSON-LD with Person author and Organization publisher
- FR9: Navigation (desktop + mobile) shows "Blog" linking to `/blog/`
- FR10: llms.txt updated to reference "Blog" instead of "Articles"
- FR11: Blog post template includes structural support for citations, statistics callouts, and quotations

## Technical Requirements

- TR1: Eleventy collection via directory data file (`blog/blog.json` with `tags: "blog"`)
- TR2: RSS via `@11ty/eleventy-plugin-rss` (add to devDependencies)
- TR3: Clean URLs via Eleventy permalink configuration (no `.html`)
- TR4: Reuse existing `.prose` class for article body styling
- TR5: Build passes: `npx @11ty/eleventy --input=plugins/soleur/docs`
- TR6: Tag pages generated via Eleventy pagination over collection tags
- TR7: All files in `plugins/soleur/docs/` -- follows existing site structure

## Files to Change

| Action | File | Description |
|--------|------|-------------|
| Delete | `docs/pages/articles.njk` | Replace with blog.njk |
| Delete | `docs/articles/articles.json` | Replace with blog/blog.json |
| Rename | `docs/_includes/article.njk` → `blog-post.njk` | Update layout name and Schema.org |
| Create | `docs/pages/blog.njk` | Blog listing page with filter tabs |
| Create | `docs/blog/blog.json` | Collection data cascade |
| Create | `docs/_includes/blog-post.njk` | Post layout with OG tags, BlogPosting schema |
| Create | `docs/pages/blog-tag.njk` | Tag index page (paginated) |
| Create | `docs/blog/feed.njk` | RSS feed template |
| Update | `docs/_data/site.json` | Nav label: Articles → Blog |
| Update | `docs/llms.txt.njk` | Reference Blog instead of Articles |
| Update | `docs/css/style.css` | Blog-specific styles (filter tabs, tag chips) |
| Update | `eleventy.config.js` | Add RSS plugin, tag collection |
