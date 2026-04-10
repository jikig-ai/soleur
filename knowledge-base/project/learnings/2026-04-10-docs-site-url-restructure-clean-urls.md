---
title: Docs site URL restructure from /pages/*.html to clean URLs
date: 2026-04-10
category: seo
tags: [eleventy, clean-urls, redirects, google-search-console, 404, permalink]
symptoms: [GSC "Not found (404)" preventing indexing, broken internal links with trailing slashes, missing slash in blog post URLs]
module: docs-site
root_cause: 'Eleventy pages used explicit permalink with .html extensions and /pages/ prefix, producing non-standard URLs that 404 at expected root-level paths'
---

# Docs Site URL Restructure: Clean URLs

## Problem

Google Search Console reported "Not found (404)" as a new reason preventing pages from being indexed on soleur.ai. Investigation revealed three issues:

1. **Broken internal link** -- `newsletter-form.njk` and `pricing.njk` linked to `/pages/legal/privacy-policy/` (trailing slash instead of `.html`), producing a 404 on every page with the newsletter form.
2. **Non-standard URL pattern** -- All page URLs used `/pages/*.html` (e.g., `/pages/agents.html`), meaning expected root-level URLs like `/agents/` returned 404.
3. **Pre-existing blog post bug** -- `{{ site.url }}pages/agents.html` was missing the `/` separator, producing `https://soleur.aipages/agents.html`.

## Solution

Full URL restructure from `/pages/*.html` to clean URLs:

- Updated `permalink:` frontmatter in all 18 page files (9 main + 9 legal) to use `/<slug>/` format
- Updated all navigation links in `site.json` (nav, footer, footerLegal)
- Fixed broken internal links across 15 source files (templates, blog posts, legal cross-references)
- Fixed pre-existing `{{ site.url }}pages/` to `{{ site.url }}/slug/` bug in 3 blog posts
- Created `pageRedirects.js` data file + `page-redirects.njk` template to generate 17 meta-refresh redirect pages from old `/pages/*.html` URLs to new clean URLs
- Updated `llms.txt.njk` with new URL patterns

## Prevention

When creating Eleventy pages:

1. Always use `permalink: <slug>/` format (generates `<slug>/index.html`, served as `/<slug>/`). Never use `.html` extensions or path prefixes like `/pages/`.
2. When restructuring URLs, always create redirect pages from old paths to preserve Google index equity and avoid breaking external links.
3. Use `{{ site.url }}/` (with trailing slash on the variable reference) before path segments to avoid missing-separator bugs.
4. Check existing `_data/*.js` files for the export pattern before writing new data files -- this project uses ESM (`export default`), not CommonJS (`module.exports`).

## Session Errors

1. **Worktree auto-cleanup after cd into _site/** -- First worktree creation succeeded but the worktree was auto-cleaned (likely because the bare repo detected no changes). When attempting to `cd` back, the directory was gone. **Prevention:** Avoid `cd` into build output directories inside worktrees; use absolute paths instead.

2. **ESM vs CommonJS module export** -- Created `pageRedirects.js` with `module.exports` but the project uses `"type": "module"` in `package.json`. Eleventy build failed with "module is not defined in ES module scope". **Prevention:** Check existing `_data/*.js` files for the export pattern before writing new data files.

3. **Cloudflare blocked WebFetch of sitemap.xml** -- `https://soleur.ai/sitemap.xml` returned 403 when fetched via WebFetch tool. **Prevention:** When Cloudflare is in front of a site, expect automated fetches to be blocked. Build locally first, then verify live URLs with `curl`.

## Key Insight

Clean URLs (`/agents/` instead of `/pages/agents.html`) are the SEO standard. When Eleventy pages use explicit `permalink:` with `.html` extensions and a `/pages/` prefix, the URLs look non-standard to both users and search engines, and expected paths return 404. Always use `permalink: <slug>/` format, which generates `<slug>/index.html` and serves cleanly as `/<slug>/`. When restructuring URLs, always create redirect pages from old paths to preserve Google index equity.
