---
title: "fix: docs build broken by missing dateToShort filter in sitemap.njk"
type: fix
date: 2026-04-05
---

# fix: docs build broken by missing dateToShort filter in sitemap.njk

## Overview

The Eleventy docs build fails with `filter not found: dateToShort` in `sitemap.njk` when run from the `plugins/soleur/docs/` subdirectory instead of the repository root. The `dateToShort` filter is registered in `eleventy.config.js` at the repo root, but Eleventy only loads this config when invoked from the root directory. Running from the docs subdirectory bypasses the config entirely, causing the filter to be undefined.

## Problem Statement

The `dateToShort` filter is used in `plugins/soleur/docs/sitemap.njk` (line 11):

```njk
<lastmod>{{ entry.date | dateToShort }}</lastmod>
```

This filter is defined in `eleventy.config.js` at the repo root (line 26-28):

```javascript
eleventyConfig.addFilter("dateToShort", (date) => {
  return new Date(date).toISOString().split("T")[0];
});
```

**Root cause:** Eleventy discovers its config file relative to the current working directory. When an agent or developer runs `npx @11ty/eleventy` from `plugins/soleur/docs/` (the input directory), Eleventy looks for `eleventy.config.js` in that directory, finds nothing, and proceeds with no custom filters registered. The sitemap template then crashes on the undefined `dateToShort` filter.

**Current state:**

- CI (`deploy-docs.yml`) runs from the repo root and succeeds
- Local builds from the repo root succeed
- Local builds from `plugins/soleur/docs/` fail with the filter error
- The `deploy-docs` skill and several learnings document this as a recurring friction point

**Evidence from learnings:**

- `knowledge-base/project/learnings/docs-site/footer-layout-redesign-flex-children-visual-verification-20260402.md` -- Session Error #1 documents the exact failure when building from the wrong directory
- `knowledge-base/project/learnings/2026-03-26-seo-meta-description-frontmatter-coherence.md` -- Session Error #3 documents the same pre-existing failure

## Proposed Solution

Make the docs build resilient to being run from either the repo root or the docs subdirectory. Two complementary approaches:

### Approach A: Add a local `eleventy.config.js` in the docs directory (Recommended)

Create `plugins/soleur/docs/eleventy.config.js` that re-exports the root config. This way, running Eleventy from the docs directory still picks up all filters, plugins, and passthrough copies.

However, Eleventy v3's config resolution with ESM modules does not support re-exporting cleanly when `dir.input` is set differently per location. A simpler and more robust variant:

### Approach B: Register the `dateToShort` filter inline in `sitemap.njk` using Nunjucks

Nunjucks does not support defining filters inline in templates. This approach is not viable.

### Approach C: Move the filter to a Nunjucks extension or data file

Eleventy data files (`_data/*.js`) can export computed data but cannot register template filters. This approach is not viable.

### Approach D: Add a guard script that detects wrong CWD (Recommended -- simplest)

The root cause is running from the wrong directory. Rather than trying to make it work from both directories, add a `package.json` in the docs directory with a build script that delegates to the root, and update the learning/documentation to be explicit. Additionally, ensure the sitemap template degrades gracefully if the filter is missing.

### Selected Approach: Hybrid (D + defensive template)

1. **Primary fix:** Replace the `dateToShort` filter usage in `sitemap.njk` with an inline Nunjucks expression that does not depend on a custom filter. Nunjucks has no built-in date formatting, but Eleventy provides `entry.date` as a JavaScript Date object. Use Eleventy's built-in `toISOString` approach via a computed data file or replace the filter call with a built-in alternative.

   Since Nunjucks templates cannot call `.toISOString()` on Date objects directly, the most robust fix is to use Eleventy's built-in `dateToRfc3339` filter from the RSS plugin (already installed as `@11ty/eleventy-plugin-rss`) and extract the date portion, OR keep the custom filter but ensure it is always available.

2. **Actual simplest fix:** The `dateToShort` filter IS defined in `eleventy.config.js` and works correctly when run from the repo root. The real fix is to ensure developers and agents always run from the repo root. But to make the template resilient, move the filter registration to a `.eleventy.js` plugin file that can be loaded from either location.

**Final recommended approach:** The simplest, most defensive fix:

1. Keep the `dateToShort` filter in `eleventy.config.js` (already works for CI and root builds)
2. Add a `plugins/soleur/docs/eleventy.config.js` that imports and re-applies the filter registration, so builds from the docs directory also work
3. Update the existing learning to note the fix

## Acceptance Criteria

- [ ] `npx @11ty/eleventy` succeeds from the **repo root** (existing behavior preserved)
- [ ] `npx @11ty/eleventy` succeeds from `plugins/soleur/docs/` (currently fails -- this is the fix)
- [ ] `sitemap.xml` contains valid `<lastmod>` dates in `YYYY-MM-DD` format in both scenarios
- [ ] CI `deploy-docs.yml` workflow continues to pass
- [ ] No duplicate filter registration warnings when running from the repo root

## Test Scenarios

- Given the repo root as CWD, when `npx @11ty/eleventy` is run, then the build succeeds and `_site/sitemap.xml` contains `<lastmod>` entries with `YYYY-MM-DD` dates
- Given `plugins/soleur/docs/` as CWD, when `npx @11ty/eleventy` is run, then the build succeeds and `_site/sitemap.xml` contains `<lastmod>` entries with `YYYY-MM-DD` dates
- Given the CI workflow runs on push to main, when the `deploy-docs.yml` workflow triggers, then it completes successfully

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

### Files to modify

| File | Change |
|------|--------|
| `plugins/soleur/docs/eleventy.config.js` | **New file** -- local Eleventy config that registers the `dateToShort` filter so builds from the docs directory work |
| `eleventy.config.js` | No change needed -- root config already correct |
| `plugins/soleur/docs/sitemap.njk` | No change needed -- template already correct |

### Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Inline Nunjucks expression in sitemap.njk | Nunjucks cannot call `.toISOString()` on Date objects; no built-in date formatting |
| Move filter to `_data/*.js` data file | Data files export data, not template filters |
| Use RSS plugin's `dateToRfc3339` filter | Outputs full RFC 3339 (with time), not `YYYY-MM-DD`; would need post-processing which is equally complex |
| Add `npm run docs:build` script in docs `package.json` | Only fixes the "how to build" question, doesn't fix `npx @11ty/eleventy` from wrong CWD |

## References

- Issue: #1531
- Learning: `knowledge-base/project/learnings/docs-site/footer-layout-redesign-flex-children-visual-verification-20260402.md` (Session Error #1)
- Learning: `knowledge-base/project/learnings/2026-03-26-seo-meta-description-frontmatter-coherence.md` (Session Error #3)
- Eleventy docs: custom config via `--config` CLI flag or `eleventy.config.js` auto-discovery
- Existing root config: `eleventy.config.js` (lines 26-28)
- Sitemap template: `plugins/soleur/docs/sitemap.njk` (line 11)
