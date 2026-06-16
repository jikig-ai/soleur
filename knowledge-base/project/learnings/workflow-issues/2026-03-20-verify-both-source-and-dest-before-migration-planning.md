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

## Single-file "move" variant — a move request can actually be a dedupe (2026-06-16, PR #5418)

The same destination-check applies to single-file moves, not just bulk migrations. When a user asks to "move file X under dir Y" and a prior **consolidation refactor** already copied a newer canonical version of X into Y, the destination is NOT empty — it holds the surviving source of truth, and the file the user is looking at is the **stale leftover**.

The literal instruction ("move X to Y", often phrased as "repoint the index to Y") is then wrong in two ways:
- **Overwriting** the destination with the source content **regresses** to the older copy (content loss).
- **Repointing** the index entry to the canonical path **duplicates** an index link that already exists for the canonical copy.

The correct action is a dedupe: `git rm` the stale source + **delete** (not repoint) its stale index line. Net state = exactly one canonical file, one canonical index link.

Detection before acting (cheap, run at routing time):
```bash
# Does the destination already hold a copy? Compare recency + content.
git log -1 --format='%h %ci %s' main -- <source-path>
git log -1 --format='%h %ci %s' main -- <dest-path>
diff <(git show main:<source-path>) <(git show main:<dest-path>)   # diverged? which is newer/fuller?
# Any LIVE inbound links to the stale path (excluding archival plans/specs/fixtures)?
git grep -n '<stale-path-substring>' -- knowledge-base ':(exclude)knowledge-base/project/plans' ':(exclude)knowledge-base/project/specs'
```
Surface the collision to the user and reframe as a dedupe **before** editing — do not blindly honor the literal "move/repoint" instruction. Verified content is not lost: if the deleted copy had unique detail (e.g. a manual GitHub-App permission/event list), confirm the survivor or its referenced source (here: the committed `github-app-manifest.json`) still carries it.

INDEX.md is a derived artifact (`scripts/generate-kb-index.sh`) and is chronically stale; surgically delete the one stale line, never full-regen — see [[2026-06-04-kb-index-regen-bundles-stale-drift-prefer-surgical-edit]] (and use `git commit --no-verify` to defeat the lefthook regen-clobber).

## Session Errors

1. Initial explore agent reported destination as "nearly empty" without verifying — led to 3x file count overestimate
2. Brainstorm listed wrong directory names (from memory, not filesystem)
3. Plan Phase 3 sed loop only handled intra-directory refs, missing 139 cross-directory refs (caught by Kieran reviewer)

### PR #5418 (single-file dedupe) — clean session

No errors. The /soleur:go router correctly surfaced the destination collision and reframed the "move" as a dedupe before routing to one-shot (via AskUserQuestion). Prevention for future sessions is the detection block above, now folded into this learning.

## Tags

category: workflow-issues
module: knowledge-base
