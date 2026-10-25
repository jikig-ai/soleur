# Learning: issue-filing gate wants bare measured numbers in Fix-Size, and a surface literal in User-Impact

## Problem

`gh issue create` was refused twice by the issue-filing gate on the same exit-2 attempt:

1. `User-Impact: <route> readability + <skill> output quality` — the line carried the surface but trailed into a capability claim; `Fix-Size: ~12 files` had no `N lines / M files` shape at all.
2. After fixing to `User-Impact: /dashboard/kb/product/competitive-intelligence.md` + `Fix-Size: ~600 lines / ~15 files` — still refused. The `~` estimates fail the "measured, not estimated" predicate; the gate wants bare integers.

Accepted on third attempt: `Fix-Size: 569 lines / 14 files` (the real line count of the doc being split, a real file count from the plan).

## Solution

Measure both fields before filing: `User-Impact:` = one named route/page/CLI/doc literal, nothing else on the line; `Fix-Size:` = `N lines / M files` with bare integers — count the artifact being changed (`wc -l`) and the touched-file list, never `~` approximations.

## Key Insight

The gate's refusal message says "measured, not estimated" but its examples don't show that `~N` is itself the rejection trigger — an approximation *reads* like a measurement and still fails. When a format gate refuses a seemingly-compliant body, strip decorations (`~`, `≈`, words like "about") before restructuring the content. Discovered via the gate's own error — clear-error path, learning file only.

## Session Errors

1. First `gh issue create` refused: `User-Impact:` trailed into capability prose and `Fix-Size:` lacked the `N lines / M files` shape. **Prevention:** write both fields as bare literals on their own lines before invoking.
2. Second `gh issue create` refused: `~` decorations made both numbers estimates. **Prevention:** run `wc -l` on the real artifact and count the planned touched files; use bare integers.

## Tags
category: workflow-patterns
module: issue-filing-gate
