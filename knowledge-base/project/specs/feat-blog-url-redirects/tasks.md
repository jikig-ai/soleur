# Tasks: fix: Blog URL Redirects

## Phase 1: Setup

- [ ] 1.1 Read existing redirect pattern in `plugins/soleur/docs/pages/articles.njk` as reference
- [ ] 1.2 Read `plugins/soleur/docs/blog/blog.json` to confirm permalink pattern
- [ ] 1.3 Read `eleventy.config.js` to understand current configuration
- [ ] 1.4 Run `npx @11ty/eleventy` to verify clean baseline build

## Phase 2: Core Implementation

- [ ] 2.1 Create `plugins/soleur/docs/blog/redirects.njk` -- Nunjucks template that uses pagination over `collections.blog` to generate redirect pages for date-prefixed blog posts
  - [ ] 2.1.1 Use `eleventyExcludeFromCollections: true` to keep redirects out of sitemap and collections
  - [ ] 2.1.2 For each blog post, extract the full filename from `page.inputPath` and check for `YYYY-MM-DD-` prefix
  - [ ] 2.1.3 Generate `<meta http-equiv="refresh" content="0;url=/blog/<fileSlug>/">` redirect
  - [ ] 2.1.4 Include `<link rel="canonical" href="/blog/<fileSlug>/">` for SEO
  - [ ] 2.1.5 Include visible fallback link text
- [ ] 2.2 If needed, add a custom Eleventy filter in `eleventy.config.js` to extract the full slug (with date prefix) from `page.inputPath`
- [ ] 2.3 Run `npx @11ty/eleventy` and verify:
  - [ ] 2.3.1 `_site/blog/2026-03-24-vibe-coding-vs-agentic-engineering/index.html` exists with correct meta-refresh
  - [ ] 2.3.2 `_site/blog/2026-03-16-soleur-vs-anthropic-cowork/index.html` exists with correct meta-refresh
  - [ ] 2.3.3 `_site/blog/2026-03-17-soleur-vs-notion-custom-agents/index.html` exists with correct meta-refresh
  - [ ] 2.3.4 `_site/blog/2026-03-19-soleur-vs-cursor/index.html` exists with correct meta-refresh
  - [ ] 2.3.5 No redirect page generated for non-date-prefixed posts (e.g., `what-is-company-as-a-service`)
  - [ ] 2.3.6 Redirect pages do NOT appear in sitemap.xml

## Phase 3: Validation Enhancement

- [ ] 3.1 Extend `scripts/validate-blog-links.sh` to check that date-prefixed blog filenames have corresponding redirect pages in the build output
  - [ ] 3.1.1 For each `.md` file in blog dir matching `YYYY-MM-DD-*.md`, check `_site/blog/<full-slug>/index.html` exists
  - [ ] 3.1.2 Verify the redirect page contains a meta-refresh tag pointing to the correct canonical URL
- [ ] 3.2 Run `bash scripts/validate-blog-links.sh _site` and verify it passes

## Phase 4: Testing

- [ ] 4.1 Run full Eleventy build: `npx @11ty/eleventy`
- [ ] 4.2 Run SEO validation: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] 4.3 Run blog link validation: `bash scripts/validate-blog-links.sh _site`
- [ ] 4.4 Verify no existing blog URLs are broken (spot-check canonical URLs in `_site/blog/`)
- [ ] 4.5 Verify redirect HTML content is correct (meta-refresh, canonical tag, fallback link)
