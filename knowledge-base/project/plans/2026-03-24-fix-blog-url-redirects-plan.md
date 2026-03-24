---
title: "fix: add redirects for date-prefixed blog URLs and prevent future link rot"
type: fix
date: 2026-03-24
semver: patch
---

# fix: Add Redirects for Date-Prefixed Blog URLs and Prevent Future Link Rot

## Overview

Four blog articles with date-prefixed filenames produce URLs that 404 when accessed with the date prefix in the path. The blog's `blog.json` uses `{{ page.fileSlug }}` which strips the `YYYY-MM-DD-` prefix from filenames, producing URLs like `/blog/vibe-coding-vs-agentic-engineering/`. However, the date-prefixed URLs (`/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`) could be shared externally or bookmarked, and currently return 404.

**Verified live:**

| Date-Prefixed URL (404) | Correct URL (200) |
|---|---|
| `/blog/2026-03-16-soleur-vs-anthropic-cowork/` | `/blog/soleur-vs-anthropic-cowork/` |
| `/blog/2026-03-17-soleur-vs-notion-custom-agents/` | `/blog/soleur-vs-notion-custom-agents/` |
| `/blog/2026-03-19-soleur-vs-cursor/` | `/blog/soleur-vs-cursor/` |
| `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` | `/blog/vibe-coding-vs-agentic-engineering/` |

The distribution content files in `knowledge-base/marketing/distribution-content/` already contain the correct (non-date-prefixed) URLs. The `social-distribute` skill correctly strips date prefixes in Phase 3. However, date-prefixed URLs could still circulate through direct sharing, search engine indexing of the filesystem, or any future regression in the content pipeline.

## Problem Statement

1. **Immediate:** 4 date-prefixed blog URLs return 404. Anyone who shared or bookmarked these URLs (or who arrives via search engine cached results) sees a dead page.
2. **Structural:** There is no mechanism to automatically generate redirects when blog filenames contain date prefixes. Every future date-prefixed blog post will create the same gap.
3. **Social media update feasibility:** Once content is published on Discord, X, LinkedIn, and Bluesky, updating the URL in existing posts varies by platform API capability.

## Proposed Solution

### Part 1: Static HTML Redirects via Eleventy (Primary Fix)

Generate static HTML redirect pages at build time for every blog post whose filename starts with a date prefix. This is the same pattern already used by `plugins/soleur/docs/pages/articles.njk` (meta-refresh redirect from `/pages/articles/` to `/blog/`).

**Approach:** Add an Eleventy data file or template that iterates over the `blog` collection, detects date-prefixed source filenames, and generates a redirect page at the date-prefixed path pointing to the canonical (fileSlug-based) path.

**Implementation in `eleventy.config.js`:**

Add a collection or global data computation that:

1. Iterates all items in the `blog` collection
2. For each item whose `page.inputPath` filename matches `/^\d{4}-\d{2}-\d{2}-/`, computes the date-prefixed slug
3. Generates a redirect HTML page at `blog/<date-prefixed-slug>/index.html` with `<meta http-equiv="refresh" content="0;url=/blog/<fileSlug>/">` and a `<link rel="canonical">` tag

**File: `plugins/soleur/docs/blog/redirects.njk`**

A Nunjucks template that uses pagination over the blog collection to generate one redirect page per date-prefixed post. Each redirect page:

- Uses `meta http-equiv="refresh"` for instant client-side redirect (0-second delay)
- Includes `<link rel="canonical" href="...">` for SEO signal
- Includes a visible fallback link for clients that don't follow meta-refresh
- Is excluded from collections and sitemap via `eleventyExcludeFromCollections: true`

**Alternative considered:** An Eleventy plugin like `eleventy-plugin-redirects`. Rejected because: (a) adding a dependency for 4 static HTML files is overkill, (b) the meta-refresh pattern already exists in the codebase (`articles.njk`), (c) GitHub Pages does not support server-side redirects (301/302), so all redirects must be client-side HTML regardless.

### Part 2: Social Media Post Updates (Assessment)

| Platform | Edit API Available? | Action |
|----------|-------------------|--------|
| **Discord** | Yes -- webhook messages can be edited via `PATCH /webhooks/{id}/{token}/messages/{message_id}` | Requires storing message IDs. The content-publisher does not currently store them. **Skip for now** -- the redirect makes the URL work. |
| **X/Twitter** | No -- X API v2 does not support editing tweets for Basic/Pro tiers. Edit Tweet was briefly available but is not in the current API. | Not possible via API. |
| **LinkedIn** | Partial -- posts can be updated via `ugcPosts` API, but URL previews are cached by LinkedIn at post time and cannot be refreshed. | Editing the text would not change the link preview. Not useful. |
| **Bluesky** | No -- AT Protocol does not support post editing. Posts can only be deleted and re-created. | Deleting and re-posting loses engagement metrics and replies. Not recommended. |

**Decision:** Do not attempt to update existing social media posts. The redirect (Part 1) is the correct fix -- it makes all previously-shared URLs work regardless of platform. The distribution content already contains correct URLs, so future posts are unaffected.

### Part 3: Workflow Prevention (Future-Proofing)

Two changes to prevent this class of issue from recurring:

1. **Extend `validate-blog-links.sh`** to also check that date-prefixed variants of blog URLs resolve to redirect pages in the build output. Currently the script only validates URLs found in distribution content. Add a check: for every blog post with a date-prefixed filename, verify that `_site/blog/<date-prefixed-slug>/index.html` exists and contains a meta-refresh tag.

2. **Add a constitution learning** documenting that blog filenames with date prefixes generate URLs without the prefix (via `page.fileSlug`), and that `redirects.njk` handles the mapping. This prevents future developers from assuming the filename IS the URL slug.

## Technical Considerations

- **GitHub Pages limitation:** No server-side redirect support. All redirects must be client-side HTML files. Meta-refresh with `content="0"` is the standard pattern. Search engines treat `content="0"` meta-refresh as equivalent to a 301 redirect.
- **SEO impact:** The `<link rel="canonical">` tag tells search engines to index the canonical URL, not the redirect page. This is important if any search engine has indexed the date-prefixed URL.
- **Build output size:** Each redirect page is ~200 bytes of HTML. 4 pages adds <1KB to the build. Future blog posts with date prefixes will automatically get redirect pages.
- **Existing pattern:** `plugins/soleur/docs/pages/articles.njk` already uses the same meta-refresh redirect technique. The new `redirects.njk` follows the same pattern.
- **Eleventy `page.fileSlug` behavior:** Confirmed -- Eleventy v3 strips `YYYY-MM-DD-` prefixes from `page.fileSlug` when the filename starts with a date pattern. This is by design for blog-style content. The full filename is available via `page.filePathStem`.

## Acceptance Criteria

- [ ] Visiting `https://soleur.ai/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` redirects to `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`
- [ ] Visiting `https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/` redirects to `https://soleur.ai/blog/soleur-vs-anthropic-cowork/`
- [ ] Visiting `https://soleur.ai/blog/2026-03-17-soleur-vs-notion-custom-agents/` redirects to `https://soleur.ai/blog/soleur-vs-notion-custom-agents/`
- [ ] Visiting `https://soleur.ai/blog/2026-03-19-soleur-vs-cursor/` redirects to `https://soleur.ai/blog/soleur-vs-cursor/`
- [ ] Future blog posts with date-prefixed filenames automatically get redirect pages (no manual intervention)
- [ ] Redirect pages include `<link rel="canonical">` pointing to the correct URL
- [ ] Redirect pages are excluded from sitemap and collections
- [ ] `validate-blog-links.sh` checks for redirect page existence for date-prefixed blog posts
- [ ] Eleventy build passes (`npx @11ty/eleventy`)
- [ ] SEO validation passes (`bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`)
- [ ] No existing blog URLs are broken by the change

## Domain Review

**Domains relevant:** Marketing, Engineering

### Marketing

**Status:** reviewed
**Assessment:** The fix restores link equity for 4 published URLs. The distribution content already uses correct URLs, so no content changes are needed. The redirect approach (meta-refresh + canonical tag) is SEO-safe and preserves any link juice from external backlinks. No marketing action required beyond the engineering fix. Future content pipeline is already correct (social-distribute Phase 3 strips date prefixes).

### Engineering

**Status:** reviewed
**Assessment:** The implementation follows the existing `articles.njk` meta-refresh pattern. The Nunjucks pagination approach automatically handles future date-prefixed posts without per-file configuration. The `validate-blog-links.sh` extension adds CI-time verification. No architectural concerns -- this is a standard Eleventy build-time generation pattern.

## Test Scenarios

- Given a blog post with filename `2026-03-24-vibe-coding-vs-agentic-engineering.md`, when Eleventy builds, then `_site/blog/2026-03-24-vibe-coding-vs-agentic-engineering/index.html` exists and contains `<meta http-equiv="refresh" content="0;url=/blog/vibe-coding-vs-agentic-engineering/">`
- Given a blog post with filename `what-is-company-as-a-service.md` (no date prefix), when Eleventy builds, then NO redirect page is generated for this post
- Given a new blog post with filename `2026-04-01-new-article.md`, when Eleventy builds, then a redirect page is automatically generated at `_site/blog/2026-04-01-new-article/index.html`
- Given the built site, when `validate-blog-links.sh` runs, then it passes (validates both canonical URLs and redirect pages)
- Given the redirect pages, when checking the sitemap, then redirect pages do NOT appear in sitemap.xml

## Implementation

### Files to Create

#### `plugins/soleur/docs/blog/redirects.njk`

Nunjucks template using Eleventy pagination over the `blog` collection. For each post whose input filename matches a date prefix pattern, generates a redirect HTML page at the date-prefixed path.

### Files to Modify

#### `scripts/validate-blog-links.sh`

Add a second validation pass: for each `.md` file in `plugins/soleur/docs/blog/` whose filename starts with `YYYY-MM-DD-`, verify the corresponding redirect page exists in `_site/blog/<full-filename-slug>/index.html` and contains a meta-refresh tag.

#### `eleventy.config.js`

If the Nunjucks pagination approach requires additional Eleventy configuration (e.g., a custom filter to extract the full filename slug from `page.inputPath`), add it here. The `page.filePathStem` property may be sufficient without configuration changes.

### Files Unchanged

- `plugins/soleur/docs/blog/blog.json` -- no changes needed; the permalink pattern is correct
- `knowledge-base/marketing/distribution-content/*.md` -- already use correct URLs
- `plugins/soleur/skills/social-distribute/SKILL.md` -- Phase 3 already strips date prefixes correctly
- `plugins/soleur/skills/content-writer/SKILL.md` -- filename convention is correct; this fix adds the missing redirect layer

## References

- Existing redirect pattern: `plugins/soleur/docs/pages/articles.njk`
- Blog permalink config: `plugins/soleur/docs/blog/blog.json:4`
- URL generation in social-distribute: `plugins/soleur/skills/social-distribute/SKILL.md:86-94`
- Blog link validator: `scripts/validate-blog-links.sh`
- Eleventy config: `eleventy.config.js`
- Deploy workflow: `.github/workflows/deploy-docs.yml`
- SEO redirect audit: `knowledge-base/engineering/audits/2026-03-05-pr438-security-audit.md`
