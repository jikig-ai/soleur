---
status: pending
priority: p3
issue_id: "807"
tags: [code-review, simplification]
dependencies: []
---

# Reduce comment bloat in .dockerignore

## Problem Statement

The `.dockerignore` has 8 section header comments for 13 patterns — nearly 1:1 ratio. Most patterns are self-explanatory (e.g., `node_modules`, `.git`, `*.pem`). Comments like "# Dependencies (installed fresh via npm ci in Dockerfile)" restate what the pattern already conveys.

## Findings

- Simplicity reviewer identified this as the main area for improvement
- File is 39 lines but could be ~17 lines with same coverage
- Keep comments only where the "why" is genuinely non-obvious (infra/, supabase/)

## Proposed Solutions

### Option A: Keep only non-obvious comments (Recommended)
Remove comments that restate what patterns already convey. Keep comments for `supabase/` and section breaks.
- Pros: Cleaner, less maintenance burden, matches typical .dockerignore style
- Cons: Slightly less self-documenting for Docker beginners
- Effort: Small
- Risk: Low

## Technical Details

- Affected files: `apps/web-platform/.dockerignore`
- Remove redundant comments, keep logical grouping with blank lines

## Acceptance Criteria

- [ ] Comments reduced to only non-obvious explanations
- [ ] File still reads clearly with logical grouping
