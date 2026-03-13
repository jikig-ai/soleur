---
title: README self-references missed in directory rename
date: 2026-03-13
category: implementation-patterns
tags: [rename, git-mv, self-references, review]
module: knowledge-base
---

# Learning: README self-references missed in directory rename

## Problem

When renaming `knowledge-base/overview/` to `knowledge-base/project/`, the plan enumerated self-references in `constitution.md` and `components/knowledge-base.md` but missed `README.md`. The README contained a directory tree showing `overview/` and prose references to "consolidate into overview" that were stale after the rename.

## Solution

Review agents (pattern-recognition-specialist) caught the gap. Fixed by updating the directory tree on line 136 and prose on line 162 of `knowledge-base/project/README.md`.

## Key Insight

When planning a directory rename, enumerate ALL files in the directory being renamed as potential self-reference holders — not just the files that are known to contain path references. Directory tree diagrams and conceptual prose derived from the directory name are easy to miss because they don't match a simple `grep` for the path pattern.

## Tags
category: implementation-patterns
module: knowledge-base
