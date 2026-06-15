---
title: "Tasks — fix: active conversation missing from Recent Conversations rail"
plan: knowledge-base/project/plans/2026-06-15-fix-active-conversation-missing-from-rail-plan.md
lane: single-domain
date: 2026-06-15
---

# Tasks — fix: active/in-progress conversation missing from rail

Derived from `2026-06-15-fix-active-conversation-missing-from-rail-plan.md`. Runner: **vitest** (`apps/web-platform`). Single-file run: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## 1. Setup / RED

- [ ] 1.1 Verify the vitest component glob (`apps/web-platform/vitest.config.ts` `test/**/*.test.tsx`) before choosing the new test path (existing `test/conversations-rail.test.tsx` vs. a sibling `test/conversations-rail-insert.test.tsx`).
- [ ] 1.2 Write failing AC1 regression test: rail mounts empty → Realtime INSERT (matching scope) → rail renders the conversation row and hides `data-testid="conversations-rail-empty"`. Confirm it FAILS on `main` HEAD.
- [ ] 1.3 Stub AC2–AC5 tests (scope guard, de-dup, limit, secondary refetch) as RED.

## 2. Core implementation (GREEN)

- [ ] 2.1 In `apps/web-platform/hooks/use-conversations.ts`, factor the shared client-side scope-guard predicate (repo_url equality vs `repoUrlRef.current`; `visibility === "workspace"` on the shared channel) used by the existing UPDATE handler.
- [ ] 2.2 Add `event: "INSERT"` subscriptions on the own (`user_id`) and shared (`workspace_id`) channels, applying the shared scope guard.
- [ ] 2.3 Implement the insert reducer: upsert-by-id (no duplicate), prepend (new row is most-recent), truncate to the hook's `limit`. Synthesize placeholder enrichment via `deriveTitle([], id, domain_leader)`, `preview: null`. No per-INSERT messages fetch.
- [ ] 2.4 In `apps/web-platform/components/chat/conversations-rail.tsx`, add the secondary trigger: when `useParams().conversationId` is set but absent from `conversations`, fire one `refetch()`; guard against re-fire loops.
- [ ] 2.5 Make AC1–AC6 pass.

## 3. Workspace-id divergence decision (AC9)

- [ ] 3.1 Re-read `resolveUserWorkspaceBinding` (`server/agent-session-registry.ts:288`) + `readWorkspaceIdFromDb` (`server/workspace-resolver.ts:248`) vs. `route.ts:44` solo fallback.
- [ ] 3.2 Decide and record: (a) align creation to solo fallback (+ test) OR (b) keep fail-loud with documented rationale + confirm the `resolveUserWorkspaceBinding.unresolvable` Sentry mirror fires. Write the decision into the PR body.

## 4. Verification

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (AC7).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite green, including `test/conversations-active-repo-scope.test.tsx` (AC6) and the new tests (AC8).
- [ ] 4.3 Post-merge (Playwright MCP): start a conversation with the rail empty, assert it appears without reload (AC10).
