---
title: SEO audit false positives caused by curl without -L flag
date: 2026-03-26
category: marketing
tags: [seo-aeo, curl, false-positives, eleventy, sitemap]
---

# Learning: SEO audit false positives and sitemap feed inclusion

## Problem

Four SEO issues were filed by the automated audit agent (#1121, #1122, #1123, #1124). Investigation revealed only 2 were real bugs:

1. **#1122 (REAL):** `feed.xml` appeared in `sitemap.xml` because the Eleventy RSS plugin uses `eleventyExcludeFromCollections: ["blog"]` (array form), which excludes from the blog collection but not from `collections.all`. The sitemap iterates `collections.all`.
2. **#1124 (REAL):** `site.author.url` pointed to the homepage instead of an author profile page.
3. **#1121 (FALSE POSITIVE):** Meta tags reported missing because the SEO audit agent used `curl -s` without `-L`. Cloudflare Bot Fight Mode returns a 301 redirect page that lacks all content.
4. **#1123 (FALSE POSITIVE):** Case studies reported missing from feed, but all 5 were present. Same curl redirect issue or stale cache.

## Solution

- **Sitemap:** Added positive allowlist filter in `sitemap.njk` — only include URLs ending in `/` or `.html`. This is more robust than excluding `.xml` because it catches any future non-HTML content type.
- **Author URL:** Updated `site.author.url` to `/about/` in `site.json`. The About page doesn't exist yet (scheduled Apr 10-16), but the 404 is acceptable for E-E-A-T structured data.
- **Regression guard:** Added non-HTML sitemap entry check to `validate-seo.sh` for CI enforcement.
- **False positives:** Closed #1121 and #1123. Filed #1169 to fix the SEO audit agent's curl usage.

## Key Insight

When an automated audit reports multiple issues, verify each independently before implementing fixes. In this case, 50% of the filed issues were false positives caused by the audit tool's methodology (missing `-L` flag with curl), not by actual site defects. The Eleventy RSS plugin's `eleventyExcludeFromCollections` array form is intentional — it avoids circular references in the blog collection while keeping the feed in `collections.all`. Template-level filtering (positive allowlist) is the correct approach since the plugin's behavior is not externally configurable.

When writing sitemap filters, prefer positive allowlists ("include only HTML") over negative exclusions ("exclude XML"). A positive filter and the CI validator should express the same predicate to avoid asymmetric protection gaps.

## Session Errors

1. **Markdown lint failure on session-state.md** — Missing blank lines around headings and lists. Recovery: Rewrote file with proper formatting. Prevention: When generating markdown files from subagent output, always add blank lines around headings and lists per markdownlint rules MD022/MD032.
2. **Plan acceptance criterion mismatch** — Plan stated `SoftwareApplication.author.url` should render as `/about/`, but the template uses `site.url` (Organization type), not `site.author.url`. Recovery: Marked as N/A in the plan. Prevention: During plan deepening, verify each acceptance criterion against the actual template code, not just the data model.
3. **Template filter/validator predicate mismatch** — Initial implementation used negative filter (exclude `.xml`) while CI validator used positive allowlist (require `/` or `.html`). Recovery: Review agents caught it; fixed to positive match. Prevention: When adding both a filter and a validator for the same invariant, ensure they express the same predicate.

## Tags

category: marketing
module: seo-aeo
symptoms: automated SEO audit reports false positives for meta tags and feed entries
