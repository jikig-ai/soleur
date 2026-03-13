---
title: "chore: fix stale knowledge-base/overview references in product/ domain docs"
type: fix
date: 2026-03-13
semver: patch
closes: "#571"
---

# Fix Stale knowledge-base/overview References in product/ Domain Docs

## Overview

After #566 restructured the knowledge-base by domain taxonomy and #569 renamed `knowledge-base/overview/` to `knowledge-base/project/`, 8 stale references to `knowledge-base/overview/` remain in two active domain docs under `knowledge-base/product/`. These are broken paths that point to files that were moved to `knowledge-base/marketing/` and `knowledge-base/product/` by #566.

## Problem Statement

Two files contain outdated `knowledge-base/overview/` path references:

1. **`knowledge-base/product/pricing-strategy.md`** (4 stale refs in YAML frontmatter `depends_on` block):
   - `knowledge-base/overview/brand-guide.md` -> `knowledge-base/marketing/brand-guide.md`
   - `knowledge-base/overview/marketing-strategy.md` -> `knowledge-base/marketing/marketing-strategy.md`
   - `knowledge-base/overview/competitive-intelligence.md` -> `knowledge-base/product/competitive-intelligence.md`
   - `knowledge-base/overview/business-validation.md` -> `knowledge-base/product/business-validation.md`

2. **`knowledge-base/product/competitive-intelligence.md`** (4 stale refs in Source documents and Cascade Results sections):
   - `knowledge-base/overview/brand-guide.md` -> `knowledge-base/marketing/brand-guide.md`
   - `knowledge-base/overview/business-validation.md` -> `knowledge-base/product/business-validation.md`
   - `knowledge-base/overview/content-strategy.md` -> `knowledge-base/marketing/content-strategy.md`
   - `knowledge-base/overview/pricing-strategy.md` -> `knowledge-base/product/pricing-strategy.md`

## Proposed Solution

Direct string replacement of all 8 stale paths to their correct current locations. No structural changes, no new files, no deletions.

### Path Mapping

| Old Path | New Path |
|----------|----------|
| `knowledge-base/overview/brand-guide.md` | `knowledge-base/marketing/brand-guide.md` |
| `knowledge-base/overview/marketing-strategy.md` | `knowledge-base/marketing/marketing-strategy.md` |
| `knowledge-base/overview/content-strategy.md` | `knowledge-base/marketing/content-strategy.md` |
| `knowledge-base/overview/competitive-intelligence.md` | `knowledge-base/product/competitive-intelligence.md` |
| `knowledge-base/overview/business-validation.md` | `knowledge-base/product/business-validation.md` |
| `knowledge-base/overview/pricing-strategy.md` | `knowledge-base/product/pricing-strategy.md` |

## Acceptance Criteria

- [ ] All `knowledge-base/overview/` references in `knowledge-base/product/pricing-strategy.md` updated to correct current paths
- [ ] All `knowledge-base/overview/` references in `knowledge-base/product/competitive-intelligence.md` updated to correct current paths
- [ ] `grep -r 'knowledge-base/overview/' knowledge-base/product/` returns zero matches

## Test Scenarios

- Given `knowledge-base/product/pricing-strategy.md` with stale `depends_on` paths, when all 4 references are updated, then each path points to an existing file
- Given `knowledge-base/product/competitive-intelligence.md` with stale source document paths, when all 4 references are updated, then each path points to an existing file
- Given both files are updated, when running `grep -r 'knowledge-base/overview/' knowledge-base/product/`, then zero matches are returned

## Non-goals

- Fixing stale `knowledge-base/overview/` references outside the `knowledge-base/product/` directory (there are ~30 more in plans, specs, plugins, and AGENTS.md -- these are out of scope for #571 and should be tracked in a separate issue if needed)
- Renaming or restructuring any directories
- Updating `knowledge-base/overview/constitution.md` references (constitution.md still lives in `knowledge-base/overview/` and these references are correct)

## Context

- Discovered during code review of #569
- These are pre-existing broken paths from #566, not regressions from #569
- Files that still legitimately live in `knowledge-base/overview/`: `README.md`, `components/`, `constitution.md`

## References

- Related PR: #566 (restructure knowledge-base by domain taxonomy)
- Related PR: #569 (rename knowledge-base/overview/ to knowledge-base/project/)
- Issue: #571
