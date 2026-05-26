---
title: "Parallel agent fan-out for batch Inngest migrations"
date: 2026-05-26
category: best-practices
tags: [inngest, migration, parallel-agents, tier-b, workflow]
module: apps/web-platform/server/inngest/functions
---

# Learning: Parallel agent fan-out for batch Inngest migrations

## Problem

TR9 Phase 2 required migrating 22 GHA scheduled workflows to Inngest functions in a single PR. Each migration follows a mechanical pattern (read GHA → write test → write implementation → delete GHA → register in route.ts) but the volume makes sequential execution prohibitively slow.

## Solution

Group migrations by archetype similarity and spawn parallel agents (Tier B fan-out), each handling 2-3 functions with non-overlapping file scopes:

- **Group by pattern:** claude-spawn (C1-C5), pure-TS simple (T1/T4/T5, T8/T9/T10), pure-TS medium (T3/T11/T13), pure-TS complex with bot-PR (T6/T7/T12)
- **Each agent gets:** the template file to follow, exact business logic per function (extracted from GHA workflow analysis), file naming conventions, and test pattern
- **Coordinator handles:** route.ts registration (single file, must be sequential), full test suite verification, incremental commits

Four parallel agents completed 12 pure-TS ports in ~6 minutes wall-clock (vs ~45 minutes sequential estimate). Two parallel agents handled 5 claude-spawn crons in ~5 minutes.

## Key Insight

Batch migrations with a shared template are ideal for Tier B fan-out: each function is independent (different files), the template is well-established (agents copy it), and integration (route.ts) is a cheap sequential step at the end. The critical precondition is a thorough template read by the coordinator before spawning — agents that invent their own patterns create integration headaches.

## Session Errors

1. **`git add` on already-staged `git rm` file** — `git rm` stages the deletion automatically; a subsequent `git add <deleted-path>` fails with `pathspec did not match`. Recovery: checked `git status` and found the file was already staged. Prevention: after `git rm`, skip explicit `git add` for that path.

2. **Source-grep regex matches comments + code** — test assertion `expect(matches).toHaveLength(3)` failed because the regex `cron\/[\w-]+\.manual-trigger` also matched the same event names in the file's header comment (6 total, not 3). Recovery: switched to individual `toContain` assertions. Prevention: when asserting counts on source-grep matches, account for the same string appearing in comments; prefer existence assertions over count assertions for source anchors.

## Tags

category: best-practices
module: apps/web-platform/server/inngest/functions
