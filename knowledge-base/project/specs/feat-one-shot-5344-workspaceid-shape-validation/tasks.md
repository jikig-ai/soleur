---
title: "Tasks — validate workspaceId shape before join() (CWE-22 defense-in-depth)"
issue: 5344
lane: single-domain
plan: knowledge-base/project/plans/2026-06-15-fix-workspaceid-shape-validation-join-plan.md
---

# Tasks: workspaceId shape validation before join()

Derived from `knowledge-base/project/plans/2026-06-15-fix-workspaceid-shape-validation-join-plan.md`.

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 `grep -n 'UUID_RE' apps/web-platform/server/workspace.ts apps/web-platform/server/api-usage.ts` — capture the canonical regex literal to copy verbatim.
- [ ] 0.2 `git grep -nE 'workspacePathForWorkspaceId|resolveWorkspacePathForUser' -- apps/web-platform | grep -v workspace-resolver.ts` — confirm every caller passes a DB UUID or `user.id`.
- [ ] 0.3 Confirm test env glob `test/**/*.test.ts` (node) at `apps/web-platform/vitest.config.ts:44`.

## Phase 1 — RED (failing tests first)

- [ ] 1.1 Create `apps/web-platform/test/workspace-resolver-id-shape-guard.test.ts` (node env), importing `randomUUID` from `crypto` and the two functions from `../server/workspace-resolver`.
- [ ] 1.2 Add cases: valid UUID passes; `"../etc"`, `"a/b"`, `"/absolute"`, `""`, `"not-a-uuid"`, and the newline-suffix evasion `"<valid-uuid>\n../etc"` each throw `Invalid workspaceId format` (≥9 assertions total).
- [ ] 1.3 Add `resolveWorkspacePathForUser` cases with a recursive supabase chain mock (shape per `workspace-resolver.ts:597-627`): DB returns non-UUID → throws; DB returns valid UUID → returns joined path.
- [ ] 1.4 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts` → expect FAIL.

## Phase 2 — GREEN (add guards)

- [ ] 2.1 Add `UUID_RE` constant to `workspace-resolver.ts` near `getWorkspacesRoot` (mirror `workspace.ts:67` byte-for-byte) with a comment citing ADR-038 / CWE-22.
- [ ] 2.2 Add `if (!UUID_RE.test(workspaceId)) throw new Error(\`Invalid workspaceId format: ${JSON.stringify(workspaceId)}\`)` in `workspacePathForWorkspaceId` before the `join` (`:718-720`). Use `JSON.stringify(workspaceId)` to escape control chars in the Sentry-bound message (security-sentinel MEDIUM); the test asserts the `Invalid workspaceId format` prefix, not the exact tail, so sanitizing is compatible.
- [ ] 2.3 Add the same guard (with `JSON.stringify(workspaceId)` in the message) in `resolveWorkspacePathForUser` after `getDefaultWorkspaceForUser` and before the `join` (`:707-708`).
- [ ] 2.4 Add a one-line comment at `:481`/`:486` noting the `kbRoot` finding is covered by the guard in `workspacePathForWorkspaceId`.
- [ ] 2.5 Re-run the Phase 1 test → expect GREEN.

## Phase 3 — Verify (no regressions)

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → 0 errors.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-share.test.ts test/shared-token-c4.test.ts test/dsar-export-workspace-path-resolver.test.ts test/durable-workspace-binding-resolver.test.ts test/workspace-resolver-id-shape-guard.test.ts` → all GREEN.
- [ ] 3.3 Re-run `semgrep-sast` rule `path-join-resolve-traversal` against `workspace-resolver.ts` → 0 findings (down from 3).

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Closes #5344`.
- [ ] 4.2 No post-merge operator steps (pure code change; container restarts on merge via path-filtered `web-platform-release.yml`).
