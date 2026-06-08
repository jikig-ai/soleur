---
title: "Tasks — converge users.workspace_path/workspace_status readers onto the resolver"
issue: 5005
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-08-refactor-converge-workspace-path-status-readers-plan.md
date: 2026-06-08
---

# Tasks: #5005 converge workspace_path/workspace_status readers

Derived from the finalized plan. 5 genuine latent-bug readers (not 19 — see plan
Research Reconciliation). Each reader: RED divergent-id test → GREEN resolver swap.
Runner: `cd apps/web-platform && ./node_modules/.bin/vitest run test/<file>.test.ts`.

## 1. Setup / Preconditions

- [ ] 1.1 Re-run classification grep on branch; confirm the 5 reader file set matches the plan.
- [ ] 1.2 Confirm resolver signatures unchanged (`resolveActiveWorkspacePath`,
      `resolveActiveWorkspaceKbRoot`, `resolveWorkspacePathForUser`, `workspacePathForWorkspaceId`,
      `resolveActiveWorkspaceRepoMeta`).
- [ ] 1.3 Read each target's existing test; reuse the `<WORKSPACES_ROOT>/<id>` nested-mock convention.

## 2. Core Implementation (per reader, RED → GREEN)

### 2.1 `server/dsar-export.ts` (GDPR-completeness — highest stakes)
- [ ] 2.1.1 RED: stale-`workspace_path` subject, on-disk workspace exists → assert workspace files
      included in export (fails today).
- [ ] 2.1.2 GREEN: `runExport` resolves path via `workspacePathForWorkspaceId(expectedUserId)`;
      `buildArchiveToDisk`/`enumerateWorkspaceFiles` arg contract unchanged; keep `exportSqlTable`
      `users` read for the export table itself.
- [ ] 2.1.3 Update the "single source of truth" comment.

### 2.2 `app/api/kb/sync/route.ts` (readiness + path + installation)
- [ ] 2.2.1 RED: new `test/kb-sync-route.test.ts`; divergent stale-own-row caller syncs (no 409/404).
- [ ] 2.2.2 GREEN: swap tenant `users` read + gates for `resolveActiveWorkspaceKbRoot` +
      `resolveActiveWorkspaceRepoMeta` (mirror kb-route-helpers/kb-upload). Preserve `KbSyncStatus`
      response-code/message contract; verify client discrimination before any code change.
- [ ] 2.2.3 Preserve server-side-path Sharp Edge (never from request body).

### 2.3 `server/attachment-pipeline.ts` (active-workspace path)
- [ ] 2.3.1 RED: stale own-row → attachments written under resolver active path (not skipped).
- [ ] 2.3.2 GREEN: swap `users` read for `resolveActiveWorkspacePath(userId, supabase)`; confirm the
      in-scope client satisfies `SupabaseLike` and is self-scoped.

### 2.4 `app/api/vision/route.ts` (active-workspace path)
- [ ] 2.4.1 RED: stale own-row → `vision.md` created under active path (not 503).
- [ ] 2.4.2 GREEN: swap `users` read for `resolveActiveWorkspacePath`; resolve "not provisioned"
      semantics (resolver always returns a path) via downstream FS check or drop; document.

### 2.5 `app/api/repo/status/route.ts` (cosmetic hasKnowledgeBase)
- [ ] 2.5.1 RED: post-relocation account → `hasKnowledgeBase` from active path.
- [ ] 2.5.2 GREEN: resolve the existence-check path via `resolveActiveWorkspacePath`.
- [ ] 2.5.3 Scope guard: do NOT touch `repo_url`/`repo_status` `users` reads (ADR-044 repo-column
      drift gate, out of scope); note adjacency in PR body.

## 3. Testing / Verification

- [ ] 3.1 Each reader has a divergent-id regression test (`workspace_id ≠ basename(workspace_path)`).
- [ ] 3.2 Active-workspace readers (sync/attachment/vision) have a member-with-non-solo-active fixture
      asserting fail-closed-to-solo (never sibling).
- [ ] 3.3 `./node_modules/.bin/vitest run` full suite green (≥ the 5 reader suites + share/dsar).
- [ ] 3.4 `./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.5 Re-run Phase 0 grep: no caller-keyed own-row path/readiness reads remain in the 5 files.
- [ ] 3.6 `git diff --stat`: only 5 readers + tests + plan/spec touched; no migration; column live.
