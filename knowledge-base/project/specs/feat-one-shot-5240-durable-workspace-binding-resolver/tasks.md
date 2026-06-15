---
title: "Tasks — Durable workspace-binding resolver (AC4, #5240)"
plan: knowledge-base/project/plans/2026-06-15-fix-durable-workspace-binding-resolver-plan.md
branch: feat-one-shot-5240-durable-workspace-binding-resolver
lane: cross-domain
---

# Tasks — Durable workspace-binding resolver

Derived from `2026-06-15-fix-durable-workspace-binding-resolver-plan.md`. Ref #5240 (NOT Closes).

## Phase 0 — Preconditions
- [x] 0.1 `grep -n "No workspace binding" apps/web-platform/server/ws-handler.ts` → exactly 2 hits (`:850`, `:1685`); re-locate if drifted.
- [x] 0.2 Conversation site: `tenant` (`:840`) in scope at `:847` ✅. **Slot site: `tenantResume` (`:1626`) is OUT of scope at `:1682`** (closes `:1670`) → slot edit mints its own `tenantSlot`. (verified deepen-pass)
- [x] 0.3 Confirm canonical read in `resolveCurrentWorkspaceId` (`workspace-resolver.ts:190-217`) + that `awaitChain` is file-private (`:531`) → shape B′ (new reader co-located in `workspace-resolver.ts`).
- [x] 0.4 `cd apps/web-platform && ./node_modules/.bin/vitest --version`.

## Phase 1 — RED (failing test first)
- [x] 1.1 Create `apps/web-platform/test/durable-workspace-binding-resolver.test.ts` (node project glob `test/**/*.test.ts`).
- [x] 1.2 Test: Map hit → returns Map value, DB-read spy called 0 times.
- [x] 1.3 Test: **Map miss + DB returns workspaceId (post-restart sim) → returns DB value, no throw, writeback into Map** (the load-bearing failing assertion).
- [x] 1.4 Test: Map miss + DB returns null → throws fail-loud + `reportSilentFallback` once; return value NOT `userId`.
- [x] 1.5 Test: Map miss + DB read error → throws + Sentry mirror; NOT `userId`.
- [x] 1.6 Run → confirm RED (≥ test 1.3 fails).

## Phase 2 — GREEN
- [x] 2.1 Add `readWorkspaceIdFromDb(userId, supabase): Promise<string|null>` to `workspace-resolver.ts` (shape B′; reuse `awaitChain`+`ChainShape`; return `?? null`, NOT `?? userId`).
- [x] 2.2 Add `resolveUserWorkspaceBinding(userId, readDbWorkspaceId)` to `agent-session-registry.ts` (Map-hit / rehydrate-writeback via `setUserWorkspace` / fail-loud-throw + `reportSilentFallback` from `./observability`; `__test_only__.clear()` already exists at `:299`).
- [x] 2.3 Rewire `ws-handler.ts:847-852` (`createConversation`) → `resolveUserWorkspaceBinding(userId, (uid)=>readWorkspaceIdFromDb(uid, tenant))` (`tenant` in scope at `:840`).
- [x] 2.4 Rewire `ws-handler.ts:1682-1687` (slot) → mint `tenantSlot = await tenantFor(userId, "handleMessage.slot-workspace-resolve")` with `:1630-1636` null-guard, then `resolveUserWorkspaceBinding(userId, (uid)=>readWorkspaceIdFromDb(uid, tenantSlot))`.
- [x] 2.5 Run new test → GREEN.

## Phase 3 — Regression + verification
- [x] 3.1 Run: `ws-deferred-creation.test.ts`, `ws-start-session-cap-hit.test.ts`, `ws-resume-by-context-path.test.ts`, `concurrency-acquire-slot-workspace-id.integration.test.ts`, `api-conversations.test.ts`, `conversation-writer.test.ts` → all pass unchanged.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Phase 4 — AC verification (pre-ship)
- [x] 4.1 AC1: `grep -c "No workspace binding for user" apps/web-platform/server/ws-handler.ts` → 0.
- [x] 4.2 AC5: `grep -c "resolveUserWorkspaceBinding" apps/web-platform/server/ws-handler.ts` → ≥ 2; both consumers route through it. Also `grep "?? userId" apps/web-platform/server/workspace-resolver.ts` shows the new `readWorkspaceIdFromDb` does NOT use it (only the pre-existing `resolveCurrentWorkspaceId` does).
- [x] 4.3 AC2/AC3/AC4 satisfied by the new test file.
- [x] 4.4 AC9: PR body uses `Ref #5240` (NOT `Closes`).

## Notes
- Out of scope (deferred under #5240): physical re-provision (#2), eager boot rehydration, in-flight-work preservation (#4), cross-tenant `/workspaces` boundary.
- No migration / no new infra / no new secret → no post-merge operator step.
