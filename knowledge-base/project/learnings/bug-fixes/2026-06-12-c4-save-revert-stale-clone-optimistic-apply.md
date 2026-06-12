---
title: "C4 Code-tab Save reverted because a React re-seed effect re-read a stale workspace clone — fix with optimistic apply"
date: 2026-06-12
category: bug-fixes
module: apps/web-platform/components/kb
tags: [react, useEffect, cache-coherence, c4, likec4, optimistic-update, workspace-sync]
pr: feat-one-shot-c4-save-not-persisting
related_issues: [4963, 4965, 4967, 4976, 4979, 5221]
---

# C4 Code-tab Save reverted: stale-clone re-seed → optimistic apply

## Problem

Editing a `.c4` source in the LikeC4 Code-tab editor (e.g. `Founder` → `Founder TEST`
in `model.c4`), clicking **Save**, and getting a **silent revert**: the editor snapped
back to the pre-edit text and the diagram did not change. The save *looked* like it did
nothing.

This was NOT the previously-fixed diagram-staleness bug (#4963 Layer-1 banner, #4965
Layer-2 re-render). Those kept the source and only the *diagram* lagged. Here the
**source itself** reverted.

## Root cause

The PUT **succeeded** (200): the `.c4` was committed to GitHub via the Contents API.
The revert was downstream, in the editor's read path:

1. `C4Workspace` `onSaved` calls `await reload()` → `useC4Project` re-fetches
   `GET /api/kb/c4/project`, which reads `sources` from the **on-disk workspace clone**.
2. `C4CodePanel` had an effect `useEffect(() => { if (activeFile) setDraft(data.sources[activeFile] ?? ""); }, [data, activeFile])` that **re-seeds the editor `draft` from `data.sources` on every `data` change**.
3. When the clone is **stale** — a diverged/un-fast-forwardable clone whose self-heal
   aborts to preserve un-pushed agent-session work (`workspace-sync.ts`), or a
   Contents-API→fetch replica that hasn't propagated yet — `data.sources[activeFile]`
   is the **pre-edit text**. The effect clobbers `draft` back to it → the revert.

The GitHub commit is the source of truth; the on-disk clone is a **cache**. A
cache-coherence lag was presenting as **data loss**.

## Solution (F-A1: optimistic apply)

Keep the just-saved content as the editor value until the reloaded clone catches up —
purely client-side in `c4-shared.tsx`, no server change:

- A `savedContentRef: useRef<Record<string,string>>` records per-file content on a
  **confirmed 200** (written AFTER the `if (!res.ok) throw` guard so a failed save can
  never show un-committed text as persisted).
- The re-seed effect prefers the optimistic value while `incoming !== optimistic`, and
  **clears the marker** once `incoming === optimistic` (clone caught up) so later
  external edits apply normally:

  ```ts
  const optimistic = savedContentRef.current[activeFile];
  if (optimistic !== undefined && incoming !== optimistic) { setDraft(optimistic); return; }
  if (optimistic !== undefined) delete savedContentRef.current[activeFile];
  setDraft(incoming);
  ```

- `dirty` compares against the optimistic baseline (falling back to `data.sources`) so
  the Save button correctly re-disables after a save.

The diagram half stays eventually-consistent and is surfaced honestly by the existing
Layer-1 staleness banner (#4963). The true root cause (the perpetually-diverged shared
clone + the working-tree git TOCTOU) is a workspace-wide liveness gap, deferred to
tracking issue **#5221** — `workspace-sync.ts` is deliberately untouched, preserving its
gated `@{u}..HEAD` self-heal (never destroy un-pushed work).

## Key insight

When a React component re-seeds local edit state from a server fetch (`useEffect(..., [data])`),
and that fetch reads a **cache that can lag the write's source of truth**, a successful
write can be silently clobbered by the next reload. The fix is the same one #4976 applied
to the diagram render: **don't depend on the reconcile pull to make just-saved content
visible** — hold the client's own just-written value until the cache demonstrably
catches up (`incoming === optimistic`), then release it. Optimistic apply must fire ONLY
on a confirmed 2xx, never on the error path.

## Session Errors

1. **Spec-dir name vs branch name drift** — the plan subagent created
   `knowledge-base/project/specs/feat-one-shot-c4-code-save-not-persisting/` (slug
   `c4-code-save`) while the branch is `feat-one-shot-c4-save-not-persisting` (slug
   `c4-save`). **Recovery:** co-located `session-state.md` in the same dir as the
   subagent's `tasks.md` (where the work phase looks), not the exact-branch-name dir.
   **Prevention:** one-shot's session-state.md step should locate the existing spec dir
   via `ls knowledge-base/project/specs/ | grep <slug-core>` rather than assuming
   `<exact-branch-name>`; the plan subagent's slug can differ from the branch slug.
   Low recurrence (cosmetic; co-location resolves it).
2. **Unused `waitFor` import** after removing a vacuous `waitFor(() => expect(...).not.toHaveBeenCalled())`. **Recovery:** removed the import same cycle. **Prevention:** when deleting the only consumer of a test util, drop its import in the same edit.
3. **Mangled `PIPESTATUS` in a compound bash command** printed `TSC_EXIT=` empty.
   **Recovery:** re-ran `tsc` standalone (`; echo "TSC_EXIT=$?"`). **Prevention:** capture
   exit codes with a standalone `; echo $?` rather than `${PIPESTATUS[0]}` inside a
   multi-stage `&&` chain.

All one-offs; none recurring-subsystem bugs warranting a fix or issue.
