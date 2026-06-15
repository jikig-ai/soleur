---
title: "Tasks — fix: active conversation missing from Recent Conversations rail"
plan: knowledge-base/project/plans/2026-06-15-fix-active-conversation-missing-from-rail-plan.md
lane: single-domain
date: 2026-06-15
---

# Tasks — fix: active/in-progress conversation missing from rail

Derived from `2026-06-15-fix-active-conversation-missing-from-rail-plan.md` (deepened 2026-06-15). Runner: **vitest** (`apps/web-platform`). Single-file run: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

**Scope: hook-only on the client.** `conversations-rail.tsx` is NOT edited. Two forbidden actions carried from architecture review: (P1) do NOT add a `useParams`-based "refetch when active id unknown" trigger; (P0) do NOT change `createConversation`'s workspace resolution to a solo fallback (#5256).

## 1. Setup / RED

- [ ] 1.1 Verify the vitest component glob (`apps/web-platform/vitest.config.ts` `test/**/*.test.tsx`) before choosing the new test path.
- [ ] 1.2 Reuse the rail test's chainable `.on()`/`.subscribe()` channel mock; extract the registered INSERT callback AND the subscribe-status callback from the spy to drive synthetic `{ new: <row>, eventType: "INSERT" }` payloads.
- [ ] 1.3 Write failing AC1: rail mounts empty → INSERT (matching scope) → row renders, `conversations-rail-empty` gone. Confirm FAIL on `main` HEAD.
- [ ] 1.4 Stub AC2 (shared scope-guard: repo_url + visibility + archive), AC3 (fill-only de-dup), AC3b (system title), AC4 (limit), AC5 (SUBSCRIBED backfill, bounded) as RED.

## 2. Core implementation (GREEN)

- [ ] 2.1 Extract `shouldDropForScope(payload, { repoUrl, channel, archiveFilter })` (repo_url + visibility + archive) and `deriveRailTitle(conv, messages)` (incl. `system → "Project Analysis"`). Refactor the existing UPDATE handler to use both (no behavior change — locked by AC6 + existing tests).
- [ ] 2.2 Add `event: "INSERT"` to the existing own (`user_id`) and shared (`workspace_id`) channels (branch on event), routing through `shouldDropForScope`.
- [ ] 2.3 Implement the fill-only INSERT reducer: de-dup by id (at-least-once delivery); on collision keep existing populated title/preview; prepend; truncate to `limit`; placeholder enrichment via `deriveRailTitle(conv, [])`, `preview: null`. No per-INSERT messages fetch.
- [ ] 2.4 Add the `SUBSCRIBED`-status backfill `fetchConversations()` inside the `.subscribe((status) => …)` callback (fires once per subscribe transition, not per render).
- [ ] 2.5 Make AC1–AC6 pass.

## 3. Workspace-id asymmetry — verify + document (AC9), NO code change

- [ ] 3.1 Read `resolveUserWorkspaceBinding` (`server/agent-session-registry.ts:276-327`) + `readWorkspaceIdFromDb` (`server/workspace-resolver.ts:228-276`); confirm the fail-loud docblocks cite #5256 and the `resolveUserWorkspaceBinding.unresolvable` Sentry mirror exists (`:316-323`).
- [ ] 3.2 In the PR body, record the read-vs-durable-write rule (route may solo-fall-back; createConversation must fail-loud, #5256). Do NOT modify the resolvers.

## 4. Verification

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (AC7).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite green, incl. `test/conversations-active-repo-scope.test.tsx` (AC6) + new tests (AC8).
- [ ] 4.3 Post-merge (Playwright MCP): start a conversation with the rail empty, assert it appears without reload (AC10).
