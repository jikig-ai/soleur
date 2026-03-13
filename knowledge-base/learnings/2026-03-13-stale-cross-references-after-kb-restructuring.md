# Learning: Stale cross-references after knowledge-base restructuring

## Problem
After #566 restructured `knowledge-base/` by domain taxonomy (moving files from `overview/` to `marketing/`, `product/`, etc.), 8 stale path references remained in `knowledge-base/product/pricing-strategy.md` and `knowledge-base/product/competitive-intelligence.md`. These pointed to `knowledge-base/overview/` paths that no longer existed at those locations.

## Solution
Direct string replacement of all 8 stale paths to their correct current locations. Three edit operations: one contiguous YAML `depends_on` block in pricing-strategy.md, two separate sections in competitive-intelligence.md. Verified with `grep -r 'knowledge-base/overview/' knowledge-base/product/` returning zero matches and all target files confirmed to exist.

## Key Insight
When restructuring directories that are cross-referenced by other documents, use `grep -r` to find all references to the old paths BEFORE merging the restructuring PR. The restructuring PR (#566) moved files but did not update all cross-references, creating broken paths discovered only during later code review (#569). A post-move grep sweep should be part of any directory restructuring checklist.

## Tags
category: integration-issues
module: knowledge-base
