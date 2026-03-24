# Learning: Eleventy `page.fileSlug` strips date prefixes from filenames

## Problem

Code constructing URLs from blog filenames (e.g., `2026-03-05-my-post.md`) produces paths like `/blog/2026-03-05-my-post/`, but Eleventy outputs `/blog/my-post/`. This mismatch causes 404s in any system that builds URLs from filesystem paths without accounting for date stripping.

## Root Cause

Eleventy's `TemplateFileSlug._stripDateFromSlug` (in `node_modules/@11ty/eleventy/src/TemplateFileSlug.js:33-38`) removes `YYYY-MM-DD-` prefixes:

```js
// Regex: /\d{4}-\d{2}-\d{2}-(.*)/
let defined = slug.match(/\d{4}-\d{2}-\d{2}-(.*)/);
if (defined) {
  return defined[1];
}
return slug;
```

## Key Behaviors

- Only matches dates at the **start** of the slug
- Returns slug unchanged if no date prefix found (safe for non-dated filenames)
- Applied to both `page.fileSlug` and `page.filePathStem`
- Does **not** validate dates -- `9999-99-99-` would match

## Impact

The `social-distribute` skill was affected: it constructed article URLs from filesystem paths without stripping the date prefix, producing 404 links in distribution content.

## Prevention

`scripts/validate-blog-links.sh` validates distribution content URLs against Eleventy build output, catching date-prefix mismatches before they reach production.

## Tags

category: build-errors
module: blog, social-distribute
