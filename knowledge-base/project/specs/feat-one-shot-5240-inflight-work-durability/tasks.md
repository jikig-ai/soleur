---
title: Tasks — In-flight work durability (ref-based worktree checkpoint, #5275)
date: 2026-06-15
issue: 5275
refs: 5240
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-15-feat-inflight-work-durability-worktree-checkpoint-plan.md
---

# Tasks: In-flight work durability — ref-based worktree checkpoint (#5275)

Derived from the finalized (post-plan-review) plan. Build the PRESERVE half of #5240 design
item #4: checkpoint an interrupted turn's uncommitted git working-tree changes on grace-disconnect
abort and restore on resume only when safe. `Ref #5240` (NOT `Closes`). Build target = #5275.

## Phase 0 — Preconditions (no code; verify against worktree)
- [x] 0.1 Re-confirm `workspacePath` is NOT in closure at the abort catch (`agent-runner.ts:2263`
  outside the `runWithByokLease` callback closing at 2261) — checkpoint call must re-resolve via
  `resolveActiveWorkspacePath(userId, sessionTenant)` / `workspacePathForWorkspaceId(...)`.
- [x] 0.2 Confirm `classifyAbortReason` → `kind === "disconnected"` for the grace path
  (`abortSession(uid, convId)` no-reason default; `agent-session-registry.ts:196`,
  `abort-classifier.ts:24-31` = 6 kinds).
- [x] 0.3 Confirm restore hook ordering at `ws-handler.ts:1938` (after `set_current_workspace_id`
  RPC succeeds, before `session_started`; terminal catch ~1955).
- [x] 0.4 Confirm git plumbing runnable + NOT stash-blocked: `write-tree`, `commit-tree`,
  `update-ref`, `rev-parse --verify`, `read-tree`, `checkout-index`, `status --porcelain`.
- [x] 0.5 Confirm `withWorkspacePermissionLock(workspacePath, fn)` reusable
  (`workspace-permission-lock.ts:53`, imported `agent-runner.ts:86`).
- [x] 0.6 Pin the team-workspace-only liveness-filtered slot probe (mig 059 column / 093 writer):
  `select count(*) from user_concurrency_slots where workspace_id=$1 and conversation_id<>$2 and
  last_heartbeat_at >= now() - interval '120 seconds'`; confirm RLS passes under tenant client.
- [x] 0.7 Pin the account-deletion seam (`server/account-delete.ts`; confirm `deleteWorkspace`
  removes the clone+refs). No conversation hard-delete exists (soft-archive only).
- [x] 0.8 Greenfield sweep: `git grep -n "refs/checkpoints"` (expect 0);
  `git grep -n "workspacePathForWorkspaceId"` (enumerate shared-tree readers).
- [x] 0.9 Baseline `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 1 — RED (failing tests first, TDD)
- [x] 1.1 `test/inflight-checkpoint.test.ts` (synthesized temp git repo fixture):
  - [x] RED-A checkpoint of an allowlisted uncommitted file → ref exists, tree carries content,
    real index + HEAD unchanged (`git diff --cached` empty).
  - [x] RED-B safe restore (clean tree, no sibling slot) → file materialized, index unstaged, ref consumed.
  - [x] RED-C refuse-and-report (dirty tree OR sibling active) → no overwrite, ref retained, honest signal.
- [x] 1.2 Test path matches `vitest.config.ts include:` (`test/**/*.test.ts`, node project); runner `vitest`.

## Phase 2 — GREEN: checkpoint-on-abort (server)
- [x] 2.1 Create `server/inflight-checkpoint.ts`: `checkpointInflightWork(workspacePath, conversationId): void`
  + `restoreInflightCheckpoint(...)` + `checkpointRefName(conversationId)` + a private
  `runPlumbingGit` (model on `_cron-safe-commit.ts runGit`: async `promisify(execFile)`,
  `{ok,stdout,stderr}` no-throw, `GIT_CONFIG_GLOBAL=/dev/null`; the plumbing verbs are greenfield —
  NOT in any existing allowlist; do NOT reuse `runConnectedRepoGit`). Lock-wrapped entries.
- [x] 2.2 No-op if no change (`git status --porcelain=v1 -z`).
- [x] 2.3 Snapshot over a temp `GIT_INDEX_FILE` OUTSIDE the worktree (`os.tmpdir()`, `finally` cleanup):
  `read-tree HEAD` → `add -- <explicit paths>` (NOT `-A`; `hr-never-git-add-a-in-user-repo-agents`;
  reuse the porcelain-parse SHAPE of `getAllowlistedChanges` but a path predicate WIDER than
  `knowledge-base/**` so code edits are captured) → `write-tree` → `commit-tree <tree> -p HEAD` →
  `update-ref refs/checkpoints/<id>`.
- [x] 2.4 HEAD/real-index/worktree never mutated; no stash; no WIP branch commit.
- [x] 2.5 Failure → `reportSilentFallback(... op:"checkpoint-on-abort")`; must NOT break the abort path.
- [x] 2.6 Wire into `agent-runner.ts` disconnected-only abort arm (re-resolve `workspacePath` first);
  add `isDisconnected` to `classifyAbortReason` (enumerate all 6 kinds); checkpoint only on `disconnected`.

## Phase 3 — GREEN: gated restore-on-resume (server)
- [x] 3.1 `restoreInflightCheckpoint(workspacePath, conversationId, { siblingSlotActive })`, lock-wrapped.
- [x] 3.2 `rev-parse --verify --quiet` absent → no-op.
- [x] 3.3 Precondition: clean tree (PRIMARY) AND (solo: skip slot read; team: `siblingSlotActive===false`).
- [x] 3.4 Safe restore via temp `GIT_INDEX_FILE` outside worktree (`read-tree <ref>` → `checkout-index -a -f`),
  real index untouched; then consume ref (`update-ref -d`).
- [x] 3.5 Unsafe → refuse-and-report: no overwrite; ONE user message (reason only in Sentry op extra);
  reuse merged FR1 honest-status surface (no new component/`.pen`); message reads sensibly to a teammate.
- [x] 3.6 Hook at `ws-handler.ts:1938` using `workspacePathForWorkspaceId(resumeWorkspaceId)`; solo passes
  `siblingSlotActive=false`; team computes via 0.6 probe. Failure → honest client error via terminal catch.
- [x] 3.7 Three-way merge DEFERRED (no code).

## Phase 4 — GREEN: erasure cascade (minimal)
- [x] 4.1 On account deletion (`account-delete.ts`), delete user's `refs/checkpoints/*` (or confirm
  `deleteWorkspace` removes clone+refs). Orphan-TTL prune DEFERRED (no `cron-workspace-gc.ts` edit).

## Phase 5 — Verification
- [x] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/inflight-checkpoint.test.ts`.
- [x] 5.3 AC-obs greps: op slugs emitted; no `stash`; no `git add -A`/`.` in `inflight-checkpoint.ts`.
- [x] 5.4 Observability discoverability test (Sentry query, NO ssh).

## Deferred (tracked, not this PR)
- [ ] Orphan-TTL prune + ref-count gauge (build gauge first).
- [ ] Three-way merge of checkpoint vs newer state.

## PR-body reminders
- `Ref #5240` (NOT `Closes`); build target #5275.
- `requires_cpo_signoff: true` (single-user incident); `user-impact-reviewer` at review.
- No migration → no GDPR-gate; optional one-line `compliance-posture.md` Active-Items note.
