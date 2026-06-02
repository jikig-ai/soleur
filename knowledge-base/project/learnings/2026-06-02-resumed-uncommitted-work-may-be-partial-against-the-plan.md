---
title: "On resume, diff uncommitted prior-session work against every plan phase — interrupted work is partial, not done"
date: 2026-06-02
category: workflow-patterns
tags: [resume, crash-recovery, plan-verification, work-skill, marketing]
issue: 1051
pr: 4769
---

# Learning: resumed uncommitted work may be partial against the plan

## Problem

Resuming `feat-one-shot-1051-cloud-platform-positioning` after a laptop crash. The task framed
the on-disk uncommitted changes (4 modified files) as "at-risk work to commit first." The
natural move is to commit the on-disk diff verbatim and proceed to ship.

But the prior session had been interrupted **mid-phase**. The plan's M3 phase
(`marketing-strategy.md` rewrite) prescribed edits at five sites:

- Moat #1 terminal-first qualifier (line ~78) — **applied** on disk
- "What Is Broken" status row (line ~58) — **applied** on disk
- Notion-response "terminal-first vs workspace-first" (line ~387) — **NOT applied**
- plugin-registry channel lines (~144 / ~204-205 / ~337) — **NOT applied**

Had I committed the on-disk diff and shipped, AC2 ("terminal-first removed at line ~78 **AND**
line ~387; channel lines reframed") would have failed, and the CMO-gate reviewer would have
received a half-done M3.

## Solution

On resume, treat the on-disk uncommitted diff as a **claim of progress, not a record of
completion**. Before committing:

1. Read the plan's full phase/AC list.
2. For each phase, re-run its verification grep against the **current working tree** (not the
   diff) — e.g. `grep -n "terminal-first" marketing-strategy.md`, `grep -niE "plugin (registry|install)"`.
3. Compare the live grep result to the plan's enumerated edit sites. Any site the plan names
   that the grep still shows in its pre-edit form is **outstanding work**, regardless of what
   the on-disk diff already touched.
4. Finish the outstanding edits, then commit the whole phase as one unit.

Here that surfaced 4 unapplied M3 edits (line 387 + three channel lines), which I completed
before the first commit.

## Key Insight

A crash-interrupted session leaves a diff that is internally consistent (every applied edit is
correct) yet **incomplete against the plan**. The on-disk diff cannot tell you what is missing —
only the plan's phase list can. This is the non-contamination sibling of
[[2026-06-01-resumed-session-artifacts-from-contaminated-tool-layer-are-unverified]]: there the
prior artifacts were *wrong* (bad tool layer); here they are *partial* (interrupted). Both share
the remedy — re-derive completeness from the authoritative source (the plan / the file it
mirrors), never from the prior session's stopping point.

The plan's per-phase verification greps are the cheapest completeness check available; they exist
precisely so a fresh session can re-establish "what's left" in seconds.

## Session Errors

- **`git branch`/`git status` failed (exit 128, "must be run in a work tree")** — ran from the
  bare-repo root before locating the worktree. Recovery: `git worktree list` → `cd` into the
  worktree. **Prevention:** on resume in a `core.bare=true` repo, run `git worktree list` and
  enter the feature worktree before any working-tree git command. Already covered in spirit by
  `hr-when-in-a-worktree-never-read-from-bare`; no new rule needed.
- **brand-guide.md Edit rejected ("File has not been read yet")** — attempted Edit before Read.
  Recovery: Read then Edit. **Prevention:** already hook-enforced by
  `hr-always-read-a-file-before-editing-it`; no new rule needed.

## Tags
category: workflow-patterns
module: work-skill
