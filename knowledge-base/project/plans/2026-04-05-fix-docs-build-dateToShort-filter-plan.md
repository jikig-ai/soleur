---
title: "fix: docs build broken by missing dateToShort filter in sitemap.njk"
type: fix
date: 2026-04-05
---

# fix: docs build broken by missing dateToShort filter in sitemap.njk

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 3 (Proposed Solution, Acceptance Criteria, Test Scenarios)
**Research methods:** Eleventy Context7 docs, empirical testing of `--config` flag behavior

### Key Improvements

1. Invalidated the `--config` flag approach through empirical testing -- `dir.input` and passthrough copies resolve relative to CWD, not config file location
2. Identified `"type": "module"` requirement for docs-local `package.json` (data files use ESM imports)
3. Added explicit test scenario confirming bare `npx @11ty/eleventy` intentionally still fails from docs dir (the fix is the npm script, not universal invocation)

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

Add a `package.json` in `plugins/soleur/docs/` with build scripts that `cd` to the repo root before invoking Eleventy. This ensures builds from the docs subdirectory use the exact same config, input paths, and passthrough copies as root builds -- zero duplication, zero drift.

```json
{
  "type": "module",
  "scripts": {
    "docs:build": "cd ../../../ && npx @11ty/eleventy",
    "docs:dev": "cd ../../../ && npx @11ty/eleventy --serve"
  }
}
```

When an agent or developer is in the docs directory, `npm run docs:build` works. Running bare `npx @11ty/eleventy` from the wrong directory still fails -- but now there is an obvious correct command available, and the error message points to a known fix.

### Research Insights

**Eleventy path resolution (verified empirically):**

- `dir.input` in `eleventy.config.js` is resolved relative to CWD, not the config file location
- `--config=../../../eleventy.config.js` loads the root config (filters work) but `dir.input: "plugins/soleur/docs"` fails because that path is relative to the docs CWD, not the repo root
- `--config=../../../eleventy.config.js --input=.` partially works: templates render and filters resolve, but passthrough copies break because `addPassthroughCopy({ "plugins/soleur/docs/css": "css" })` also resolves relative to CWD
- The only approach that produces identical output to a root build is actually running from the root: `cd ../../../ && npx @11ty/eleventy`

**`"type": "module"` requirement:**

The docs data files (`_data/agents.js`, `_data/skills.js`, etc.) use ESM `import` statements. Without `"type": "module"` in the nearest `package.json`, Node.js treats `.js` files as CommonJS, causing `SyntaxError: Cannot use import statement outside a module`. The root `package.json` has `"type": "module"`, which covers all files when running from root. A docs-local `package.json` must also include this field.

**Edge case -- output directory:**

When running `cd ../../../ && npx @11ty/eleventy` from the docs `package.json`, the output goes to `<repo-root>/_site/` (not `plugins/soleur/docs/_site/`). This matches CI behavior exactly, which is correct.

[Updated 2026-04-05 -- plan review: replaced duplicate config file approach with `--config` flag.]
[Updated 2026-04-05 -- deepened: `--config` flag approach invalidated by empirical testing. `cd` to root is the only fully correct approach. Added `"type": "module"` requirement.]

## Acceptance Criteria

- [ ] `npx @11ty/eleventy` succeeds from the **repo root** (existing behavior preserved)
- [ ] `npm run docs:build` succeeds from `plugins/soleur/docs/` (new convenience script)
- [ ] `sitemap.xml` contains valid `<lastmod>` dates in `YYYY-MM-DD` format
- [ ] Passthrough copies (CSS, fonts, images, CNAME) present in `_site/` output
- [ ] CI `deploy-docs.yml` workflow continues to pass
- [ ] No duplicate config file -- single source of truth (`eleventy.config.js` at repo root)

## Test Scenarios

- Given the repo root as CWD, when `npx @11ty/eleventy` is run, then the build succeeds, `_site/sitemap.xml` contains `<lastmod>` entries with `YYYY-MM-DD` dates, and passthrough copies are present
- Given `plugins/soleur/docs/` as CWD, when `npm run docs:build` is run, then the build succeeds with identical output to the root build
- Given `plugins/soleur/docs/` as CWD, when bare `npx @11ty/eleventy` is run (without the script), it still fails -- the fix is the npm script, not making bare invocation work from the wrong directory
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
| `--config=../../../eleventy.config.js` flag only | `dir.input` resolves relative to CWD, not config location; fails with "input path must exist" |
| `--config` + `--input=.` | Templates and filters work, but passthrough copies break (paths still resolve from CWD) |
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
