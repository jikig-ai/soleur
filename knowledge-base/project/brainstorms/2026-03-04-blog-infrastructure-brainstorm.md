# Brainstorm: Blog Infrastructure for SEO/AEO

Date: 2026-03-04
Issue: #431
Branch: feat-blog-infrastructure
PR: #437

## What We're Building

Rename the existing `articles/` system (delivered in PR #428) to `blog/` and add the remaining infrastructure gaps: RSS feed, clean URLs, Open Graph meta tags, tag support with index pages, GEO/AEO template features, and updated Schema.org structured data.

The blog will host three content types at high cadence (multiple posts per week, with a burst of foundational articles at launch): long-form articles, product updates, and tutorials.

## Why This Approach

### Rename articles -> blog

- Every SaaS competitor uses `/blog/` (Vercel, Supabase, Linear, Stripe)
- LLMs expect `/blog/` for AEO discoverability
- Zero articles published = zero migration cost right now
- Current `/pages/articles.html` leaks Eleventy internals into URLs
- `.html` extensions signal "legacy static site" -- contradicts brand

### Single collection with type frontmatter

- All posts in one `blog/` directory with `type: article | update | tutorial`
- Simplest for the `content-writer` skill to target (one output location)
- Tags create topical clusters for SEO; type field creates content categories
- Listing page with filter tabs by type
- At high cadence, simpler than managing 3 subdirectories

### Full scope now (not incremental)

- RSS, tags, OG tags, clean URLs, GEO/AEO features are all lightweight
- Shipping infrastructure incomplete means content-writer output needs rework later
- Brand guide says "write like the future is already here" -- ship the complete system

## Key Decisions

1. **URL structure:** `/blog/` (listing), `/blog/{slug}` (individual posts, no `.html`)
2. **Content types via frontmatter:** `type: article | update | tutorial` (not subdirectories)
3. **Tags:** Free-form tags in frontmatter, tag index pages generated automatically
4. **Authorship:** Named founder as `Person` author, Soleur as `Organization` publisher (E-E-A-T signal)
5. **Schema.org:** `BlogPosting` (not generic `Article`) for precise SEO signal
6. **RSS feed:** Via `@11ty/eleventy-plugin-rss`, full content in feed
7. **Clean URLs:** No `.html` extensions, no `/pages/` prefix
8. **GEO/AEO template features:** Structural support for citations, statistics callouts, expert quotations (each +30-40% AI visibility per Princeton GEO research)
9. **Open Graph tags:** Title, description, type, URL in `<head>` for social sharing
10. **Reuse `.prose` class** for article body styling (existing utility, `max-width: 75ch`)

## Open Questions

1. What is the founder's full name for Schema.org `Person` authorship?
2. Should tag index pages render at `/blog/tag/{tag-name}` or `/blog/tags/{tag-name}`?
3. Should the RSS feed include full content or summaries only?

## Research Inputs

### CMO Assessment

- Strong recommendation for `/blog/` over `/articles/` based on SEO, convention, and AEO signals
- Identified clean URLs, RSS, and Schema.org upgrade as P1 gaps
- Noted that Vercel uses `/blog` URL but sometimes calls posts "articles" in copy

### Learnings Research (10 files)

- `content-writer` skill already generates articles with Eleventy frontmatter and JSON-LD
- Marketing strategy unification identified blog infrastructure as the #1 capacity blocker
- GEO/AEO research: citations, statistics, quotations each give +30-40% AI visibility
- `.prose` utility class exists for long-form content styling
- Eleventy build must run from repo root with `--input` pointing to docs directory
