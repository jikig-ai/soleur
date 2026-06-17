---
title: "Relocating a column's WRITES without sweeping its read FILTERS leaves a silently-stale predicate (a frozen WHERE, not an error)"
date: 2026-06-17
category: best-practices
module: apps/web-platform
tags: [adr-044, column-relocation, stale-filter, silent-staleness, cron, reader-sweep]
issue: 5437
pr: 5491
---

# Learning: a relocated column's leftover read-FILTER goes silently stale, not loud

## Problem

ADR-044 PR-2 (#5466) relocated the WRITES of `repo_status`/`repo_url` from `users.*`
to `workspaces.*`. The `users.*` columns became un-written (frozen at their last
pre-cutover value). But the `cron-workspace-sync-health` scan still **filtered** on
`users.repo_status='ready'` — `.from("users").select(...).eq("repo_status","ready")`.

This is NOT a crash and NOT a missing reader the prior reader-sweep (#5470/#5482, which
hunted `.select()` columns) would catch — it's a **frozen WHERE clause**. The cron kept
returning rows based on a value that no code updates anymore:
- **Direction A (false negatives):** a newly-connected user (workspaces-authoritative,
  `users.repo_status` never written → NULL) is silently MISSED — the health cron never
  scans them, so their KB sync can break with no alert.
- **Direction B (false positives):** a user with stale `users.repo_status='ready'` whose
  live `workspaces.repo_status` is now `'error'` is still scanned — wasted work / wrong
  signal.

Both are silent: tsc passes, the unit suite (mocking the old `users` shape) passes, and
the cron keeps "working." The defect surfaces only as degraded detection quality, which
nobody notices until a user's sync silently rots.

## Solution

When relocating a column's writes, the reader sweep must cover **read FILTERS
(`.eq()`/`.in()`/`.gt()` predicates), not just SELECT projections.** The grep that finds
stale SELECTs (`from("users")…select(…col…)`) does NOT find a stale `.eq("col", …)`
filter — add a predicate-shaped sweep:
```
rg -nU 'from\("users"\)[\s\S]{0,400}?\.(eq|in|gt|lt|match|filter)\([^)]*\b<relocated_col>\b' apps/web-platform
```
Then cut the filter to the authoritative table. Here: Shape-B two-query — scan
`workspaces` where `repo_status='ready'` (the live source), collect ids, then read the
users-only column (`kb_sync_history`, mig 017) via `.in("id", readyIds)` (solo
`workspaces.id == users.id`, ADR-038 N2). The cutover is a strict improvement (catches
Direction A, drops Direction B) — make BOTH directions explicit tests (a per-table eq
spy that pins the filter to the `workspaces` chain and asserts the `users` chain NEVER
receives the predicate).

**Corollary — the solo self-join silently drops team rows.** A `.in("id", workspaceIds)`
against `users` matches nothing for a TEAM workspace (fresh-uuid id ≠ any users.id), so
team workspaces are silently dropped. That's safe (no misattribution — uuids never
collide with user ids) but it IS a coverage decision — document it inline so the next
reader doesn't mistake the solo-only scan for a bug.

## Key Insight

A column relocation has THREE reader surfaces, not one: SELECT projections, JOIN/embed
targets, and **WHERE-clause filter predicates**. The first two fail loudly-ish (wrong
data shape, query error); a stale filter fails SILENTLY — it keeps matching a frozen
value and quietly shifts the scanned population. After moving a column's writes, sweep
all three surfaces and treat a leftover filter on the now-frozen column as a latent
silent bug, not dead code. Extends the #5482 lesson (multi-line SELECT sweep) to the
predicate case.

## Session Errors

1. **gh `--json merged` field unsupported** in this gh version (planning subagent) —
   Recovery: used `--json state`/`title`. **Prevention:** prefer `gh pr view --json
   state` (state ∈ MERGED/CLOSED/OPEN) over `--json merged`; the boolean field isn't in
   all gh builds.
2. **Read tool served a stale cached copy of the cron file in the worktree; an initial
   Write resolved to the main checkout (blocked)** (review-fix subagent) — Recovery:
   verified disk==HEAD via md5, worked from on-disk `nl` content, re-issued Write with
   the absolute worktree path. **Prevention:** covered by compound's existing "always use
   worktree-absolute paths for Write/Edit; verify with `git status --short`" guidance;
   tool/env quirk, not project debt.
3. **Fix prompt named `hashUserIdValue` but the export is `hashUserId`** — Recovery:
   subagent grepped + corrected; the cleanup (remove unused mock key) was right
   regardless. **Prevention:** grep the actual export name before citing it in a fix
   prompt; one-off.

## Tags
category: best-practices
module: apps/web-platform
