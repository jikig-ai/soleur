# Tasks: fix: Blog URL Redirects

## Phase 1: Setup

- [ ] 1.1 Read existing redirect pattern in `plugins/soleur/docs/pages/articles.njk` as reference
- [ ] 1.2 Read `plugins/soleur/docs/blog/blog.json` to confirm permalink pattern uses `page.fileSlug`
- [ ] 1.3 Read `eleventy.config.js` to understand current filter configuration
- [ ] 1.4 Run `npm install` (worktrees do not share `node_modules/`)
- [ ] 1.5 Run `npx @11ty/eleventy` to verify clean baseline build

## Phase 2: Core Implementation

- [ ] 2.1 Add `dateSlug` custom filter to `eleventy.config.js` -- extracts full filename (with date prefix) from `page.inputPath`, returns empty string if no date prefix
  - Place after existing `readableDate` filter
  - Filter logic: `inputPath.split("/").pop().replace(/\.md$/, "")` then test against `/^\d{4}-\d{2}-\d{2}-/`
- [ ] 2.2 Create `plugins/soleur/docs/blog/redirects.njk` -- Nunjucks pagination template
  - [ ] 2.2.1 Pagination config: `data: collections.blog`, `size: 1`, `alias: post`
  - [ ] 2.2.2 `eleventyExcludeFromCollections: true` to keep redirects out of sitemap, RSS, and blog listing
  - [ ] 2.2.3 Permalink uses conditional: `dateSlug` result for date-prefixed posts, `false` for others (Eleventy skips output when permalink is `false`)
  - [ ] 2.2.4 Use `post.page.inputPath` (not `page.inputPath`) to access collection item metadata -- `page` in pagination context refers to the template, not the item
  - [ ] 2.2.5 Generate `<meta http-equiv="refresh" content="0;url=/blog/{{ post.page.fileSlug }}/">` redirect
  - [ ] 2.2.6 Include `<link rel="canonical" href="/blog/{{ post.page.fileSlug }}/">` for SEO
  - [ ] 2.2.7 Include visible fallback link text for clients that do not follow meta-refresh
- [ ] 2.3 Run `npx @11ty/eleventy` and verify:
  - [ ] 2.3.1 `_site/blog/2026-03-24-vibe-coding-vs-agentic-engineering/index.html` exists with correct meta-refresh
  - [ ] 2.3.2 `_site/blog/2026-03-16-soleur-vs-anthropic-cowork/index.html` exists with correct meta-refresh
  - [ ] 2.3.3 `_site/blog/2026-03-17-soleur-vs-notion-custom-agents/index.html` exists with correct meta-refresh
  - [ ] 2.3.4 `_site/blog/2026-03-19-soleur-vs-cursor/index.html` exists with correct meta-refresh
  - [ ] 2.3.5 No redirect page generated for non-date-prefixed posts (e.g., `_site/blog/what-is-company-as-a-service/` should have the actual article, no duplicate redirect)
  - [ ] 2.3.6 Redirect pages do NOT appear in `_site/sitemap.xml`
  - [ ] 2.3.7 Verify `validate-seo.sh` skips redirect pages automatically (line 76-80 already handles this)

## Phase 3: Validation Enhancement

- [ ] 3.1 Extend `scripts/validate-blog-links.sh` to check that date-prefixed blog filenames have corresponding redirect pages in the build output
  - [ ] 3.1.1 Add a redirect validation section after the existing URL check loop
  - [ ] 3.1.2 For each `.md` file in blog dir matching `[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md`, check `_site/blog/<full-slug>/index.html` exists
  - [ ] 3.1.3 Verify the redirect page contains `http-equiv="refresh"`
- [ ] 3.2 Run `bash scripts/validate-blog-links.sh _site` and verify it passes (both URL checks and redirect checks)

## Phase 4: Testing

- [ ] 4.1 Run full Eleventy build: `npx @11ty/eleventy`
- [ ] 4.2 Run SEO validation: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] 4.3 Run blog link validation: `bash scripts/validate-blog-links.sh _site`
- [ ] 4.4 Verify no existing blog URLs are broken (spot-check canonical URLs in `_site/blog/`)
- [ ] 4.5 Verify redirect HTML content: meta-refresh target, canonical tag, fallback link text
