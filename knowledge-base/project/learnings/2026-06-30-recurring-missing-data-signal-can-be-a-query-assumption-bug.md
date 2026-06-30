---
title: "A recurring 'X is missing' signal can be a query-assumption bug, not missing data — and a .git FILE strands the agent's in-bwrap rev-parse"
date: 2026-06-30
category: bug-fixes
issues: "#5733 #5591"
tags: [observability, supabase, maybeSingle, multi-owner, git-worktree, bwrap, investigation-first]
---

# Learning — #5733 owner-less-workspace strand

## Problem
Issue #5733 (continuation of #5591) reported the operator's `/soleur:go` Concierge
stranding on `not a git repository` after THREE merged server-side fixes, with a
headline signal: **"owner-less workspace reconciled" fired 28× on the operator's
workspace `754ee124`**. The plan (and issue) diagnosed this as a *missing owner
canary* — a data anomaly to remediate by INSERTING/restoring the owner row.

## Root cause — TWO independent findings, both refuting the plan's premise

### 1. The "owner-less ×28" signal was a `.maybeSingle()`-on-2-rows FALSE POSITIVE
Live read-only prod evidence (Phase 0) showed `754ee124` is the operator's own
user id → it is their **solo** workspace, the owner canary is **present**, and in
fact there are **TWO** legitimate owner rows (a second human co-owner). The
reconcile owner lookup used
`workspace_members.eq("role","owner").maybeSingle()`, and **PostgREST
`.maybeSingle()` ERRORS on >1 row** → `ownerId=null` → the false "owner-less"
warn every push. **The canary was not missing — it was duplicated, and the query
assumed ≤1 owner.** The remediation was the *inverse* of the plan: not "insert a
canary" but "tolerate N owners" (the founder confirmed **multi-owner is by
design**, superseding the migration-075/#4520 single-owner-strict model).

### 2. A `.git` FILE at a workspace root strands the agent's in-bwrap `git rev-parse`
The actual strand: `isValidGitWorkTree` (lstat-structural) returns `true` for a
`.git` **FILE** (a `gitdir:` pointer). The agent's Bash tool runs `git rev-parse
--is-inside-work-tree` INSIDE a bubblewrap sandbox with `denyRead:["/workspaces"]`.
A pointer whose `gitdir:` target ESCAPES the workspace (under `/workspaces`) is
unreadable in-sandbox → `rev-parse` fails → `/soleur:go` Step 0.0 self-stops with
**no server event** (the dark surface all three prior fixes missed).

## Solution
- **Reconcile attribution tolerates N owners**: select all owner rows, pick the
  self-row (`user_id==ws.id`) else earliest `created_at` (+`user_id` tiebreak);
  warn "owner-less" ONLY on genuinely zero rows; info breadcrumb on ≥2.
- **`isReadyGitWorkTree`** (rev-parse-AWARE): ready = a self-contained valid dir
  OR a non-escaping in-workspace pointer. Swept across ALL THREE readiness gates
  (cold dispatch, warm `cc-reprovision`, reconcile). An escaping pointer is
  unlinked (single-file `force` rm, NOT recursive) + re-cloned self-contained.
- **`agent-readiness-self-stop`** server-side Sentry event (own issue group,
  query-only-by-design) makes the strand observable; the workspace id is
  pre-hashed (for a solo workspace it == userId — ADR-029).

## Key Insights
1. **A recurring "X is missing / owner-less / not found" signal is a HYPOTHESIS
   about a mechanism, not a diagnosis.** Verify the signal's PRODUCING CODE
   against live evidence before treating the symptom as the data state. Here a
   `.maybeSingle()` that assumes ≤1 row mis-reported *duplicate* data as
   *missing* data — and the fix was the inverse of the plan's. (`.single()`/
   `.maybeSingle()` on a `role='owner'` lookup that does NOT pin `user_id` is the
   smell; pin the id or tolerate N.)
2. **Investigation-first plans can have their entire premise refuted by Phase-0
   live evidence.** When that happens, route the binding data-model decision to
   the CTO agent + the founder (single-vs-multi-owner is a product call), and
   DROP the now-moot deliverables (here: the owner-canary "restore").
3. **lstat-validity ≠ rev-parse-readiness.** A `.git` FILE passes lstat but can
   strand a sandboxed `git rev-parse` when its gitdir target is denyRead. Gate
   destructive heals on the ACTUAL strand predicate (escaping pointer), not the
   broad shape (any pointer).

## Session Errors
1. **Stray `lane` file** written by the plan subagent — Recovery: `rm` at work-start. Prevention: one-off; the Phase 0.5 `awk` that reads spec.md's `lane:` should redirect to a var, never a file.
2. **Wholesale-module-mock drops a named export (×2)** — the reconcile test mock lacked `isReadyGitWorkTree` after the predicate swap; two `cc-dispatcher` factory tests lacked `hashUserId` after the emit widened to reach `reportAgentReadinessSelfStop`. Both passed touched-file tests and FAILED only at the full-suite exit gate. Recovery: add the dropped export to each mock. Prevention: already-documented (`2026-06-29-wholesale-module-mock-drops-named-exports`); the full-suite exit gate is the catch — when a server fn reachable by many tests gains a new call into a wholesale-mocked module, run the FULL suite, never just touched-file tests.
3. **`cc-reprovision.test.ts` mock used the old `isValidGitWorkTree` name** after the source swapped to `isReadyGitWorkTree` — Recovery: rename the spy. Prevention: when renaming/swapping an imported predicate in source, grep `test/` for the old export name in the same edit cycle.
4. **ADR `Edit` failed (file not Read first)** — Recovery: Read then Edit. Prevention: Read before Edit (tool contract).
