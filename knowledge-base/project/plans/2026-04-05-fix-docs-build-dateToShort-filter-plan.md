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

Add a `package.json` in `plugins/soleur/docs/` with a `docs:build` script that uses Eleventy's `--config` flag to point at the root config. This ensures builds from the docs subdirectory use the same single config file as root builds -- zero filter duplication, zero drift risk.

```json
{
  "scripts": {
    "docs:build": "npx @11ty/eleventy --config=../../../eleventy.config.js",
    "docs:dev": "npx @11ty/eleventy --config=../../../eleventy.config.js --serve"
  }
}
```

When an agent or developer is in the docs directory, `npm run docs:build` works. Running bare `npx @11ty/eleventy` from the wrong directory still fails -- but now there is an obvious correct command available.

[Updated 2026-04-05 -- plan review: replaced duplicate config file approach with `--config` flag. One source of truth for filters.]

## Acceptance Criteria

- [ ] `npx @11ty/eleventy` succeeds from the **repo root** (existing behavior preserved)
- [ ] `npx @11ty/eleventy` succeeds from `plugins/soleur/docs/` (currently fails -- this is the fix)
- [ ] `sitemap.xml` contains valid `<lastmod>` dates in `YYYY-MM-DD` format in both scenarios
- [ ] CI `deploy-docs.yml` workflow continues to pass
- [ ] No duplicate filter registration or second config file -- single source of truth

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
| `plugins/soleur/docs/package.json` | **New file** -- adds `docs:build` and `docs:dev` scripts using `--config` flag to point at root config |
| `eleventy.config.js` | No change needed -- root config already correct |
| `plugins/soleur/docs/sitemap.njk` | No change needed -- template already correct |

### Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Duplicate `eleventy.config.js` in docs directory | Two config files will drift; any new filter must be added in two places |
| Inline Nunjucks expression in sitemap.njk | Nunjucks cannot call `.toISOString()` on Date objects; no built-in date formatting |
| Move filter to `_data/*.js` data file | Data files export data, not template filters |
| Use RSS plugin's `dateToRfc3339` filter | Outputs full RFC 3339 (with time), not `YYYY-MM-DD`; would need post-processing |

## References

- Issue: #1531
- Learning: `knowledge-base/project/learnings/docs-site/footer-layout-redesign-flex-children-visual-verification-20260402.md` (Session Error #1)
- Learning: `knowledge-base/project/learnings/2026-03-26-seo-meta-description-frontmatter-coherence.md` (Session Error #3)
- Eleventy docs: custom config via `--config` CLI flag or `eleventy.config.js` auto-discovery
- Existing root config: `eleventy.config.js` (lines 26-28)
- Sitemap template: `plugins/soleur/docs/sitemap.njk` (line 11)
