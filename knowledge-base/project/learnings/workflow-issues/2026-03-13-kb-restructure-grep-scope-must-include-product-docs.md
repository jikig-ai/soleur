---
title: KB restructure grep scope must include product docs
date: 2026-03-13
problem_type: logic_error
severity: low
module: knowledge-base
component: path-references
tags: [refactoring, grep, path-references, knowledge-base]
---

# KB Restructure Grep Scope Must Include Product Docs

## Problem

During the knowledge-base directory restructure (#568), the plan's exhaustive grep scoped to `plugins/`, `scripts/`, `.github/`, and `AGENTS.md` — the "executable code" boundary. This missed a stale path reference in `knowledge-base/product/business-validation.md`, which contains actionable cross-references that agents follow.

## Solution

The code-reviewer agent caught the missed reference during review. Fixed by adding `knowledge-base/product/` to the grep scope.

## Key Insight

When restructuring knowledge-base paths, the grep scope must include ALL of `knowledge-base/` except the directories being moved. Product docs, domain docs, and project docs all contain cross-references that agents treat as navigation instructions. The "executable code" boundary is too narrow — any file an agent reads is effectively executable.

## Prevention

For future path restructures, use this grep scope:

```bash
grep -r 'old-path/' plugins/ scripts/ .github/ AGENTS.md knowledge-base/ --exclude-dir=archive
```

Then filter out matches in the moved directories themselves (those are self-referential and don't need updating).

## Tags

category: workflow-issues
module: knowledge-base
