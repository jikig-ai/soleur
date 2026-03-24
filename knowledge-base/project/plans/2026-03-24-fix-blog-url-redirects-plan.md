---
title: "fix: add redirects for date-prefixed blog URLs and prevent future link rot"
type: fix
date: 2026-03-24
semver: patch
deepened: 2026-03-24
---

# fix: Add Redirects for Date-Prefixed Blog URLs and Prevent Future Link Rot

## Enhancement Summary

**Deepened on:** 2026-03-24
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Implementation, Test Scenarios)
**Research sources:** Eleventy v3 official docs (Context7), project learnings, `validate-seo.sh` source analysis

### Key Improvements

1. Concrete Nunjucks template code for `redirects.njk` with verified Eleventy pagination API
2. Custom `dateSlug` filter implementation for `eleventy.config.js` -- Nunjucks lacks regex, so filename extraction must happen in JS
3. Discovered that `validate-seo.sh` already skips meta-refresh redirect pages (line 76-80) -- no SEO validator changes needed
4. Identified pagination gotcha: collection items expose `post.page.inputPath` (not `page.inputPath`) -- the `page` object in pagination context refers to the pagination template, not the collection item

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

**Implementation details:**

Two files need changes: a custom Eleventy filter in `eleventy.config.js` and a Nunjucks pagination template at `plugins/soleur/docs/blog/redirects.njk`.

**Why a custom filter is needed:** Nunjucks has no built-in regex support. Extracting the date-prefixed filename from `post.page.inputPath` (e.g., `./plugins/soleur/docs/blog/2026-03-24-vibe-coding-vs-agentic-engineering.md`) requires string parsing that Nunjucks cannot do natively. A custom `dateSlug` filter in `eleventy.config.js` handles this cleanly.

**Filter: `dateSlug` in `eleventy.config.js`:**

```javascript
// Return the full filename slug (with date prefix) if it has one, otherwise empty string.
// Input: collection item's page.inputPath (e.g., "./plugins/soleur/docs/blog/2026-03-24-slug.md")
// Output: "2026-03-24-slug" or "" if no date prefix
eleventyConfig.addFilter("dateSlug", (inputPath) => {
  const filename = inputPath.split("/").pop().replace(/\.md$/, "");
  return /^\d{4}-\d{2}-\d{2}-/.test(filename) ? filename : "";
});
```

**Template: `plugins/soleur/docs/blog/redirects.njk`:**

Uses Eleventy pagination with `size: 1` over `collections.blog`. For each blog post, checks if its filename has a date prefix via the `dateSlug` filter. If so, generates a redirect page at the date-prefixed path.

```nunjucks
---
pagination:
  data: collections.blog
  size: 1
  alias: post
eleventyExcludeFromCollections: true
permalink: "{% set slug = post.page.inputPath | dateSlug %}{% if slug %}blog/{{ slug }}/index.html{% else %}false{% endif %}"
---
{% set slug = post.page.inputPath | dateSlug %}{% if slug %}<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0;url=/blog/{{ post.page.fileSlug }}/">
<link rel="canonical" href="/blog/{{ post.page.fileSlug }}/">
<title>Redirecting...</title>
</head><body>
<p>Redirecting to <a href="/blog/{{ post.page.fileSlug }}/">/blog/{{ post.page.fileSlug }}/</a></p>
</body></html>{% endif %}
```

**Key Eleventy API details (verified via Context7 docs):**

- When paginating over `collections.blog` with `alias: post`, each item is a collection object with `post.page.inputPath`, `post.page.fileSlug`, `post.url`, `post.data`, and `post.content`
- `post.page.fileSlug` = Eleventy's date-stripped slug (the canonical URL segment)
- `post.page.inputPath` = full path including date prefix (e.g., `./plugins/soleur/docs/blog/2026-03-24-vibe-coding-vs-agentic-engineering.md`)
- Setting `permalink` to `false` (via the Nunjucks conditional) tells Eleventy to skip generating output for that pagination item -- this is how non-date-prefixed posts are filtered out
- `eleventyExcludeFromCollections: true` ensures redirect pages do not appear in the blog listing, sitemap, or RSS feed

**Nunjucks gotcha (from project learning):** When building URLs, `page.url` already includes a leading slash. Use `{{ site.url }}{{ page.url }}` not `{{ site.url }}/{{ page.url }}` to avoid double slashes. The redirect template uses root-relative paths (`/blog/...`) which avoids this issue entirely.

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
- **Build output size:** Each redirect page is ~200 bytes of HTML. 4 pages adds less than 1KB to the build. Future blog posts with date prefixes will automatically get redirect pages.
- **Existing pattern:** `plugins/soleur/docs/pages/articles.njk` already uses the same meta-refresh redirect technique. The new `redirects.njk` follows the same pattern.
- **Eleventy `page.fileSlug` behavior:** Confirmed via Context7 docs -- Eleventy v3 strips `YYYY-MM-DD-` prefixes from `page.fileSlug` when the filename starts with a date pattern. This is by design for blog-style content. The full filename is available via `page.inputPath`.
- **SEO validator compatibility:** The existing `validate-seo.sh` (line 76-80) already detects and skips meta-refresh redirect pages with `content="0"`. No changes needed to the SEO validator -- redirect pages will automatically pass validation.
- **Pagination `permalink: false`:** Eleventy supports `permalink: false` to suppress output for a pagination item. The Nunjucks conditional in the permalink expression evaluates to `false` for non-date-prefixed posts, meaning Eleventy generates no output file for those items. This is cleaner than generating empty files.
- **Collection item vs. page context:** When using pagination over `collections.blog`, the alias variable (e.g., `post`) provides the collection item object. The `page` variable refers to the pagination template itself, not the collection item. Always use `post.page.inputPath` (not `page.inputPath`) to access collection item metadata.

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

## Edge Cases

- **Blog post filename with numbers but not a date:** A file like `42-reasons-to-use-soleur.md` should NOT trigger a redirect page. The regex `^\d{4}-\d{2}-\d{2}-` requires exactly the `YYYY-MM-DD-` format.
- **Redirect permalink collision:** If a date-prefixed filename's slug somehow collides with an existing page's permalink, Eleventy will error at build time. This is unlikely given the date prefix, but the build step catches it.
- **Blog post renamed after publication:** If a blog post's filename changes (e.g., fixing a typo in the slug), the old redirect page disappears and the new one is created. This is correct behavior -- the `validate-blog-links.sh` script would catch if a distribution content URL no longer resolves.
- **Empty blog collection:** If no blog posts exist, pagination produces zero items and no redirect pages are generated. No error.

## Test Scenarios

- Given a blog post with filename `2026-03-24-vibe-coding-vs-agentic-engineering.md`, when Eleventy builds, then `_site/blog/2026-03-24-vibe-coding-vs-agentic-engineering/index.html` exists and contains `<meta http-equiv="refresh" content="0;url=/blog/vibe-coding-vs-agentic-engineering/">`
- Given a blog post with filename `what-is-company-as-a-service.md` (no date prefix), when Eleventy builds, then NO redirect page is generated for this post (permalink evaluates to `false`)
- Given a new blog post with filename `2026-04-01-new-article.md`, when Eleventy builds, then a redirect page is automatically generated at `_site/blog/2026-04-01-new-article/index.html`
- Given the built site, when `validate-blog-links.sh` runs, then it passes (validates both canonical URLs and redirect pages)
- Given the redirect pages, when checking the sitemap, then redirect pages do NOT appear in `_site/sitemap.xml`
- Given the redirect pages, when `validate-seo.sh` runs, then redirect pages are detected as redirects and skipped (not flagged as missing canonical/OG/JSON-LD)
- Given the `dateSlug` filter receives a path like `./plugins/soleur/docs/blog/case-study-brand-guide-creation.md`, then it returns empty string (no redirect generated)
- Given the `dateSlug` filter receives a path like `./plugins/soleur/docs/blog/2026-03-24-vibe-coding-vs-agentic-engineering.md`, then it returns `2026-03-24-vibe-coding-vs-agentic-engineering`

## Implementation

### Files to Create

#### `plugins/soleur/docs/blog/redirects.njk`

Nunjucks pagination template that generates one redirect HTML page per date-prefixed blog post. See the concrete template code in the Proposed Solution Part 1 section above. The template:

1. Paginates over `collections.blog` with `size: 1`, `alias: post`
2. Uses `post.page.inputPath | dateSlug` filter to extract the date-prefixed filename
3. Sets `permalink` to `blog/<dateSlug>/index.html` for date-prefixed posts, `false` for others
4. Generates minimal HTML with meta-refresh redirect to `/blog/<post.page.fileSlug>/`
5. Has `eleventyExcludeFromCollections: true` to stay out of sitemap, RSS, and blog listing

### Files to Modify

#### `eleventy.config.js`

Add the `dateSlug` custom filter. Place it after the existing `readableDate` filter. The filter extracts the full filename (with date prefix) from a collection item's `page.inputPath` and returns it if it matches the `YYYY-MM-DD-` pattern, or empty string otherwise.

```javascript
// Date-prefixed slug for blog redirect pages
eleventyConfig.addFilter("dateSlug", (inputPath) => {
  const filename = inputPath.split("/").pop().replace(/\.md$/, "");
  return /^\d{4}-\d{2}-\d{2}-/.test(filename) ? filename : "";
});
```

#### `scripts/validate-blog-links.sh`

Add a second validation pass after the existing URL check. For each `.md` file in the blog directory whose filename starts with `YYYY-MM-DD-`, verify:

1. `_site/blog/<full-filename-slug>/index.html` exists
2. The file contains `meta http-equiv="refresh"`

```bash
# --- Redirect page validation ---
BLOG_DIR="<repo-root>/plugins/soleur/docs/blog"
for md_file in "$BLOG_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md; do
  [[ -f "$md_file" ]] || continue
  slug=$(basename "$md_file" .md)
  redirect_path="$SITE_DIR/blog/$slug/index.html"
  if [[ -f "$redirect_path" ]]; then
    if grep -q 'http-equiv="refresh"' "$redirect_path"; then
      pass "redirect: /blog/$slug/ -> valid"
    else
      fail "redirect: /blog/$slug/ exists but missing meta-refresh"
    fi
  else
    fail "redirect: /blog/$slug/ missing (expected for date-prefixed file)"
  fi
done
```

### Files Unchanged

- `plugins/soleur/docs/blog/blog.json` -- no changes needed; the permalink pattern is correct
- `knowledge-base/marketing/distribution-content/*.md` -- already use correct URLs
- `plugins/soleur/skills/social-distribute/SKILL.md` -- Phase 3 already strips date prefixes correctly
- `plugins/soleur/skills/content-writer/SKILL.md` -- filename convention is correct; this fix adds the missing redirect layer
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- already skips meta-refresh redirect pages (line 76-80), no changes needed

## References

- Existing redirect pattern: `plugins/soleur/docs/pages/articles.njk`
- Blog permalink config: `plugins/soleur/docs/blog/blog.json:4`
- URL generation in social-distribute: `plugins/soleur/skills/social-distribute/SKILL.md:86-94`
- Blog link validator: `scripts/validate-blog-links.sh`
- Eleventy config: `eleventy.config.js`
- Deploy workflow: `.github/workflows/deploy-docs.yml`
- SEO redirect audit: `knowledge-base/engineering/audits/2026-03-05-pr438-security-audit.md`
