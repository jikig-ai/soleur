---
title: "Tasks — Durable workspace-binding resolver (AC4, #5240)"
plan: knowledge-base/project/plans/2026-06-15-fix-durable-workspace-binding-resolver-plan.md
branch: feat-one-shot-5240-durable-workspace-binding-resolver
lane: cross-domain
---

# Tasks — Durable workspace-binding resolver

Derived from `2026-06-15-fix-durable-workspace-binding-resolver-plan.md`. Ref #5240 (NOT Closes).

## Phase 0 — Preconditions
- [ ] 0.1 `grep -n "No workspace binding" apps/web-platform/server/ws-handler.ts` → exactly 2 hits (`:850`, `:1685`); re-locate if drifted.
- [ ] 0.2 Confirm `tenant` (`ws-handler.ts:840`) and `tenantResume` (`~:1627`) are in scope at the two consumer sites.
- [ ] 0.3 Confirm `resolveCurrentWorkspaceId` select shape at `workspace-resolver.ts:203-207` (mirror it in the db-reader closure; RLS `user_session_state_owner_select` self-scopes).
- [ ] 0.4 `cd apps/web-platform && ./node_modules/.bin/vitest --version`.

## Phase 1 — RED (failing test first)
- [ ] 1.1 Create `apps/web-platform/test/durable-workspace-binding-resolver.test.ts` (node project glob `test/**/*.test.ts`).
- [ ] 1.2 Test: Map hit → returns Map value, DB-read spy called 0 times.
- [ ] 1.3 Test: **Map miss + DB returns workspaceId (post-restart sim) → returns DB value, no throw, writeback into Map** (the load-bearing failing assertion).
- [ ] 1.4 Test: Map miss + DB returns null → throws fail-loud + `reportSilentFallback` once; return value NOT `userId`.
- [ ] 1.5 Test: Map miss + DB read error → throws + Sentry mirror; NOT `userId`.
- [ ] 1.6 Run → confirm RED (≥ test 1.3 fails).

## Phase 2 — GREEN
- [ ] 2.1 Add `resolveUserWorkspaceBinding(userId, readDbWorkspaceId)` to `agent-session-registry.ts` (shape A; Map-hit / rehydrate-writeback via `setUserWorkspace` / fail-loud-throw decision tree; `__test_only__` seam if needed).
- [ ] 2.2 Rewire `ws-handler.ts:847-852` (`createConversation`) → call resolver with db-reader bound to `tenant`.
- [ ] 2.3 Rewire `ws-handler.ts:1682-1687` (slot acquire) → call resolver with db-reader bound to `tenantResume`.
- [ ] 2.4 db-reader closure returns `data?.current_workspace_id ?? null` (NULL, not userId — fail-loud decision lives in the resolver).
- [ ] 2.5 Run new test → GREEN.

## Phase 3 — Regression + verification
- [ ] 3.1 Run: `ws-deferred-creation.test.ts`, `ws-start-session-cap-hit.test.ts`, `ws-resume-by-context-path.test.ts`, `concurrency-acquire-slot-workspace-id.integration.test.ts`, `api-conversations.test.ts`, `conversation-writer.test.ts` → all pass unchanged.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Phase 4 — AC verification (pre-ship)
- [ ] 4.1 AC1: `grep -c "No workspace binding for user" apps/web-platform/server/ws-handler.ts` → 0.
- [ ] 4.2 AC5: `grep -c "resolveUserWorkspaceBinding" apps/web-platform/server/ws-handler.ts` → ≥ 2; both consumers route through it.
- [ ] 4.3 AC2/AC3/AC4 satisfied by the new test file.
- [ ] 4.4 AC9: PR body uses `Ref #5240` (NOT `Closes`).

## Notes
- Out of scope (deferred under #5240): physical re-provision (#2), eager boot rehydration, in-flight-work preservation (#4), cross-tenant `/workspaces` boundary.
- No migration / no new infra / no new secret → no post-merge operator step.
