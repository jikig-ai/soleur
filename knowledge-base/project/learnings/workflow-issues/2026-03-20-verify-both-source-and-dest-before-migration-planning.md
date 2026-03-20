---
title: Verify both source AND destination before migration planning
date: 2026-03-20
category: workflow-issues
tags: [migration, planning, knowledge-base, directory-structure]
module: knowledge-base
---

# Learning: Verify both source AND destination before migration planning

## Problem

When planning a directory migration (moving `knowledge-base/{brainstorms,specs,learnings,plans}/` into `knowledge-base/project/`), the initial explore agent only inspected the SOURCE directories. It reported `knowledge-base/project/` as nearly empty, leading the brainstorm to estimate ~870 files to move and ~1,181 path references to update.

In reality, `knowledge-base/project/` already had MORE files than the top-level dirs (the migration was partially completed months earlier). The actual scope was 291 files to move and only 4 source file lines to update — a 3x overestimate on files and 295x overestimate on reference updates.

## Solution

Before scoping any migration, always inspect BOTH the source and destination:

```bash
# Check source
for d in brainstorms learnings plans specs; do
  echo "SOURCE knowledge-base/$d: $(find "knowledge-base/$d" -type f | wc -l) files"
done

# Check destination
for d in brainstorms learnings plans specs; do
  echo "DEST knowledge-base/project/$d: $(find "knowledge-base/project/$d" -type f | wc -l) files"
done

# Check for collisions (files in BOTH)
for d in brainstorms learnings plans specs; do
  comm -12 \
    <(find "knowledge-base/$d" -type f -exec basename {} \; | sort) \
    <(find "knowledge-base/project/$d" -type f -exec basename {} \; | sort) | wc -l
  echo "collisions in $d"
done
```

Also grep source files separately from content files to get the true update scope:

```bash
# Source files (the ones that actually matter)
grep -rn "knowledge-base/$dir/" plugins/ scripts/ apps/ .github/ AGENTS.md | grep -v "project/" | wc -l

# Content files (best-effort, no runtime impact)
grep -rl "knowledge-base/$dir/" knowledge-base/project/ | wc -l
```

## Key Insight

Migration scope estimates are only accurate when you inspect the destination as well as the source. A partial migration means the destination already has content — checking only the source dramatically overestimates the remaining work. The SpecFlow analyzer caught this, but the brainstorm had already committed to a much larger scope.

## Session Errors

1. Initial explore agent reported destination as "nearly empty" without verifying — led to 3x file count overestimate
2. Brainstorm listed wrong directory names (from memory, not filesystem)
3. Plan Phase 3 sed loop only handled intra-directory refs, missing 139 cross-directory refs (caught by Kieran reviewer)

## Tags
category: workflow-issues
module: knowledge-base
