---
title: "chore: fix stale knowledge-base/overview references in product/ domain docs"
type: fix
date: 2026-03-13
semver: patch
closes: "#571"
---

# Fix Stale knowledge-base/overview References in product/ Domain Docs

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 3 (Problem Statement, Proposed Solution, Non-goals)
**Research method:** Local codebase verification (grep, file existence checks)

### Key Improvements
1. Verified all 6 target files exist at their new locations -- path mapping confirmed correct
2. Clarified that #569 is an open issue (not yet merged) -- the overview/ directory still exists; stale refs are exclusively from #566
3. Quantified out-of-scope stale references: 40+ additional stale refs exist in plans/, specs/, plugins/, and AGENTS.md -- filed as a follow-up concern

### New Considerations Discovered
- The `pricing-strategy.md` footer (line 208) also references source files by bare name without path -- these are not broken but could become ambiguous as files spread across domains
- The `competitive-intelligence.md` Cascade Results table (lines 213-214) records historical agent output paths -- updating these is technically a history rewrite, but the paths serve as current cross-references, not audit logs, so updating is correct

---

## Overview

After #566 restructured the knowledge-base by domain taxonomy, 8 stale references to `knowledge-base/overview/` remain in two active domain docs under `knowledge-base/product/`. These are broken paths that point to files moved to `knowledge-base/marketing/` and `knowledge-base/product/` by #566.

Note: #569 (rename `knowledge-base/overview/` to `knowledge-base/project/`) is still an open issue and has not been merged. The `knowledge-base/overview/` directory still exists with `README.md`, `components/`, and `constitution.md`. The stale references in this plan are exclusively from #566's file moves.

## Problem Statement

Two files contain outdated `knowledge-base/overview/` path references:

1. **`knowledge-base/product/pricing-strategy.md`** (4 stale refs in YAML frontmatter `depends_on` block, lines 6-9):
   - `knowledge-base/overview/brand-guide.md` -> `knowledge-base/marketing/brand-guide.md`
   - `knowledge-base/overview/marketing-strategy.md` -> `knowledge-base/marketing/marketing-strategy.md`
   - `knowledge-base/overview/competitive-intelligence.md` -> `knowledge-base/product/competitive-intelligence.md`
   - `knowledge-base/overview/business-validation.md` -> `knowledge-base/product/business-validation.md`

2. **`knowledge-base/product/competitive-intelligence.md`** (4 stale refs):
   - Line 154: `knowledge-base/overview/brand-guide.md` -> `knowledge-base/marketing/brand-guide.md` (Source documents section)
   - Line 155: `knowledge-base/overview/business-validation.md` -> `knowledge-base/product/business-validation.md` (Source documents section)
   - Line 213: `knowledge-base/overview/content-strategy.md` -> `knowledge-base/marketing/content-strategy.md` (Cascade Results table)
   - Line 214: `knowledge-base/overview/pricing-strategy.md` -> `knowledge-base/product/pricing-strategy.md` (Cascade Results table)

### Verification Results

All 6 target files confirmed to exist at their new locations:
- `knowledge-base/marketing/brand-guide.md` -- exists
- `knowledge-base/marketing/marketing-strategy.md` -- exists
- `knowledge-base/marketing/content-strategy.md` -- exists
- `knowledge-base/product/competitive-intelligence.md` -- exists
- `knowledge-base/product/business-validation.md` -- exists
- `knowledge-base/product/pricing-strategy.md` -- exists

## Proposed Solution

Direct string replacement of all 8 stale paths to their correct current locations. No structural changes, no new files, no deletions.

### Path Mapping

| Old Path | New Path | Files Affected |
|----------|----------|----------------|
| `knowledge-base/overview/brand-guide.md` | `knowledge-base/marketing/brand-guide.md` | pricing-strategy.md (L6), competitive-intelligence.md (L154) |
| `knowledge-base/overview/marketing-strategy.md` | `knowledge-base/marketing/marketing-strategy.md` | pricing-strategy.md (L7) |
| `knowledge-base/overview/content-strategy.md` | `knowledge-base/marketing/content-strategy.md` | competitive-intelligence.md (L213) |
| `knowledge-base/overview/competitive-intelligence.md` | `knowledge-base/product/competitive-intelligence.md` | pricing-strategy.md (L8) |
| `knowledge-base/overview/business-validation.md` | `knowledge-base/product/business-validation.md` | pricing-strategy.md (L9), competitive-intelligence.md (L155) |
| `knowledge-base/overview/pricing-strategy.md` | `knowledge-base/product/pricing-strategy.md` | competitive-intelligence.md (L214) |

### Implementation Approach

Use the Edit tool for each replacement. The `pricing-strategy.md` changes are in a contiguous YAML block (lines 6-9) so can be done in a single edit. The `competitive-intelligence.md` changes are in two separate sections (lines 154-155 and lines 213-214), requiring two edits.

Total edits: 3 (one for pricing-strategy.md, two for competitive-intelligence.md).

## Acceptance Criteria

- [x] All `knowledge-base/overview/` references in `knowledge-base/product/pricing-strategy.md` updated to correct current paths
- [x] All `knowledge-base/overview/` references in `knowledge-base/product/competitive-intelligence.md` updated to correct current paths
- [x] `grep -r 'knowledge-base/overview/' knowledge-base/product/` returns zero matches
- [x] Each updated path points to a file that exists on disk

## Test Scenarios

- Given `knowledge-base/product/pricing-strategy.md` with stale `depends_on` paths, when all 4 references are updated, then each path points to an existing file
- Given `knowledge-base/product/competitive-intelligence.md` with stale source document paths, when all 4 references are updated, then each path points to an existing file
- Given both files are updated, when running `grep -r 'knowledge-base/overview/' knowledge-base/product/`, then zero matches are returned

## Non-goals

- Fixing stale `knowledge-base/overview/` references outside the `knowledge-base/product/` directory. Deepening found 40+ additional stale refs in:
  - `knowledge-base/project/plans/` (historical plan documents referencing old paths)
  - `knowledge-base/project/specs/` (task files referencing old paths)
  - `plugins/soleur/skills/compound/SKILL.md` (references to constitution.md -- these are correct, constitution.md still lives in overview/)
  - `plugins/soleur/commands/sync.md` (references to overview/ structure -- partially correct, partially stale)
  - `AGENTS.md` (reference to constitution.md -- correct)
  - These should be tracked in a follow-up issue. Many are in archived/historical plans where updating would rewrite history.
- Renaming or restructuring any directories
- Updating `knowledge-base/overview/constitution.md` references (constitution.md still lives in `knowledge-base/overview/` and these references are correct)
- Implementing #569 (rename overview/ to project/) -- that is a separate issue

## Context

- Discovered during code review of #569
- These are pre-existing broken paths from #566, not regressions from #569
- #569 (rename overview/ to project/) is still OPEN -- the overview/ directory still exists
- Files that still legitimately live in `knowledge-base/overview/`: `README.md`, `components/`, `constitution.md`

## References

- Related PR: #566 (restructure knowledge-base by domain taxonomy)
- Related issue: #569 (rename knowledge-base/overview/ to knowledge-base/project/) -- OPEN, not yet implemented
- Issue: #571
