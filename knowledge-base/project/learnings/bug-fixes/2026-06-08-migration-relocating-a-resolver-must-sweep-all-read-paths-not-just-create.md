---
title: A migration that relocates a resolution source must sweep ALL read paths, not just create/owner
date: 2026-06-08
category: bug-fixes
module: kb-share
tags: [adr-044, workspace-resolver, kb-share, shared-documents, migration-completeness, public-endpoint]
severity: high
---

# Learning: a relocation migration must migrate every consumer of the old source, not just the write path

## Problem

A user shared a KB document, copied the link (`/shared/<token>`), and opening it
returned **"Document not found"** — even though the share was freshly created and
the document existed. The share *created* fine but *read* as a 404.

A second, cosmetic issue was reported in the same screenshot: the Copy/"Copied!"
button overflowed the fixed-width share popup.

## Root cause

ADR-044 relocated KB-root resolution off the per-user `users.workspace_path` /
`users.workspace_status` columns onto a workspace-id-keyed layout
(`<WORKSPACES_ROOT>/<workspace_id>/knowledge-base`, via
`workspacePathForWorkspaceId`). The **create** path
(`app/api/kb/share/route.ts`) was migrated to `resolveActiveWorkspaceKbRoot`.

But the **read** paths were never migrated:
- `app/api/shared/[token]/route.ts` (`prepareSharedRequest`, feeds GET + HEAD)
- `server/kb-share.ts` (`previewShare`, also the `kb_share_preview` MCP tool)

Both still resolved kbRoot + a readiness gate from the owner's legacy `users`
columns, which are stale/empty for accounts provisioned after the
`users → workspaces` relocation. So a share created via the migrated write path
404'd on the unmigrated read path — either the `workspace_status !== "ready"`
gate tripped, or the empty `workspace_path` made the file unfindable.

The create route's own comment (`route.ts:34-40`) literally documented the
divergence ("stale/empty for users provisioned after the ADR-044 relocation …
the divergent failure surface that dead-ended Generate link") — but only the
write path had been fixed.

## Solution

Resolve the read-side kbRoot from the share row's stored `workspace_id` (NOT NULL
since migration 059, backfilled to the N2 invariant `workspace_id == user_id`
for solo users) via `workspacePathForWorkspaceId`, exactly matching create. Drop
the legacy owner-row readiness gate: a de-provisioned workspace still surfaces as
`KbNotFoundError → 404` at the file-read step, and the `content_sha256` hash gate
still guards the served bytes. Backward-compatible: for existing rows,
`workspacePathForWorkspaceId(workspace_id)` resolves to the byte-identical dir the
old `users.workspace_path` pointed at.

CSS fix: add `min-w-0` to the `flex-1 truncate` share-link input — the canonical
fix for the flexbox `min-width: auto` trap (a flex child won't shrink below its
intrinsic width, defeating `truncate` and shoving the `shrink-0` button out).

## Key Insight

When a migration **relocates a resolution source** (a column, a lookup table, an
ID key), the write path is the *most visible* consumer but rarely the only one.
Sweep every consumer of the old source in the same migration:

```
git grep -n '<old_column_or_join>'   # e.g. users!inner(workspace_path, workspace_status)
```

…and classify each hit as create / owner-read / anonymous-read / sync / export.
A create-path-only migration leaves read paths resolving against the now-stale
source — green CI, passing create, silent 404 on read. This is the read-side
analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`: **a relocation
needs a read-boundary sentinel sweep too.**

Create/read symmetry is the test that matters: does the read path resolve to the
exact dir the write path wrote to, for the same row? Prove it with a test where
the new key **diverges** from the old source (here: `workspace_id` ≠
`basename(workspace_path)`), so a regression that re-reads the old source fails.

## Session Errors

1. **Delegated exploration returned an over-confident wrong root cause.** An
   Explore subagent concluded ("BINGO!") that the `workspace_status` gate was THE
   cause; the actual cause was the entire read path never migrating to ADR-044.
   Recovery: read the create + read code directly and found the asymmetry.
   **Prevention:** treat a subagent's root-cause hypothesis as a lead, not a
   verdict — verify it against the code (especially the *symmetric* path) before
   acting. A single-branch explanation for a 404 is suspect when the same 404
   code has 3 reachable branches.
2. **Lint not runnable in the worktree.** `next lint` required interactive config
   setup; direct `eslint` failed (no v9 `eslint.config.js`). Recovery: `tsc
   --noEmit` + full share/shared test suite (clean); CI runs lint. **Prevention:**
   one-off/env — don't block a worktree ship on local lint; CI is the gate.
3. **Flat-layout share tests broke after the resolver change** (expected).
   Recovery: migrated 6 test files + the shared mock helper to the ADR-044 nested
   layout (`WORKSPACES_ROOT=dirname(tmpWorkspace)`, mock derives `workspace_id`
   from the workspace-path basename). **Prevention:** when a resolver's source
   changes, the test fixtures that model the OLD source must move with it — model
   the production `<WORKSPACES_ROOT>/<id>` layout, not a flat temp dir.

## Tags
category: bug-fixes
module: kb-share
