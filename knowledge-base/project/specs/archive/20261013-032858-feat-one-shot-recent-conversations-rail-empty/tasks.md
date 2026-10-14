---
title: "Tasks — fix Recent Conversations rail empty (repo_url source divergence)"
plan: knowledge-base/project/plans/2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence-plan.md
branch: feat-one-shot-recent-conversations-rail-empty
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-06-15
---

# Tasks

Derived from the deepened plan. Single atomic PR. Test runner is **vitest**; typecheck is
in-package `tsc` (NOT `npm run -w` — repo root has no `workspaces` field).

## Phase 0 — Preconditions / verification

- [ ] 0.1 Open-code-review overlap: run the `gh issue list --label code-review` + per-path `jq`
  grep (plan §Open Code-Review Overlap) for `hooks/use-conversations.ts`,
  `test/conversations-rail.test.tsx`, and the new `test/*-active-repo-scope.test.tsx`. Fold-in /
  acknowledge / defer each match; record disposition in the PR body.
- [ ] 0.2 Re-confirm the active-repo route shape: `GET /api/workspace/active-repo` returns
  `{ workspaceId, repoUrl, repoName, repoStatus, fellBackToSolo }`
  (`apps/web-platform/app/api/workspace/active-repo/route.ts:80-86`).
- [ ] 0.3 Confirm no existing `test/use-conversations*.test.tsx` already covers the active-repo
  path: `git grep -l "use-conversations" apps/web-platform/test/`.

## Phase 1 — RED test (write failing test first; cq-write-failing-tests-before)

- [ ] 1.1 Add `apps/web-platform/test/<descriptive>-active-repo-scope.test.tsx` (`.tsx`, under
  `test/`). Mock `vi.stubGlobal("fetch", ...)` returning `{ ok: true, json: () => ({ workspaceId, repoUrl }) }`
  for `/api/workspace/active-repo` (precedent `test/live-repo-badge.test.tsx:34-46`); mock
  `vi.mock("@/lib/supabase/client", ...)` stubbing only `conversations` + `messages` + `channel`
  builders (precedent `test/command-center-repo-scope.test.tsx:118-145`). Do NOT stub
  `users`/`workspace_members`. `vi.restoreAllMocks()` in `beforeEach`.
- [ ] 1.2 Assert: a conversation row stamped with the route's `repoUrl` is surfaced by the hook.
- [ ] 1.3 Run the test against the **unmodified** hook → confirm it is RED
  (`cd apps/web-platform && ./node_modules/.bin/vitest run test/<...>-active-repo-scope.test.tsx`).

## Phase 2 — Core fix (use-conversations.ts)

- [ ] 2.1 Replace the `Promise.all([users, workspace_members])` block (`:121-141`) with
  `const res = await fetch("/api/workspace/active-repo")`; set `workspaceId` ← `repoUrl` ←
  response. On `!res.ok` set `error` + stop. Keep the `setConversations([])` null-repo
  early-return.
- [ ] 2.2 Remove the cross-tab `command-center-user` realtime channel (`:301-334`).
- [ ] 2.3 Remove the now-unused `normalizeRepoUrl` import (`:5`).
- [ ] 2.4 Add the drift-safeguard comment citing ADR-044 + this plan near the new fetch.
- [ ] 2.5 Leave list query (`.eq("repo_url", currentRepoUrl)`), `repoUrlRef` mirror, and the
  two conversation realtime channels unchanged in shape — only their source changes.

## Phase 3 — GREEN + regression coverage

- [ ] 3.1 Re-run the Phase 1 test → GREEN.
- [ ] 3.2 Verify/extend `test/conversations-rail.test.tsx`: rows render when populated; empty
  state only when empty.
- [ ] 3.3 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0
  (catches the unused-import removal via `noUnusedLocals`).
- [ ] 3.4 Targeted suite:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/conversations-rail.test.tsx test/<...>-active-repo-scope.test.tsx`
  → all pass.

## Phase 4 — Acceptance criteria sweep

- [ ] 4.1 AC1: `git grep -n 'from("users")' apps/web-platform/hooks/use-conversations.ts` has no
  `repo_url` line.
- [ ] 4.2 AC2: `git grep -n 'workspace/active-repo' apps/web-platform/hooks/use-conversations.ts` ≥1.
- [ ] 4.3 AC3: `git grep -n 'from("workspace_members")' apps/web-platform/hooks/use-conversations.ts` = 0.
- [ ] 4.4 AC8: `git grep -rn 'from("users")' apps/web-platform/hooks apps/web-platform/components | grep repo_url` = 0.
- [ ] 4.5 AC9: `git grep -n 'command-center-user' apps/web-platform/hooks/use-conversations.ts` = 0.
- [ ] 4.6 AC10: `git grep -n 'normalizeRepoUrl' apps/web-platform/hooks/use-conversations.ts` = 0
  (or annotated surviving use).

## Phase 5 — Post-merge (operator / automatable)

- [ ] 5.1 Merge to main path-filters `apps/web-platform/**` → `web-platform-release.yml`
  auto-restarts the container (no separate operator restart).
- [ ] 5.2 Live smoke via Playwright MCP (route through `/soleur:qa` / `test-browser` at ship):
  connected user, chat shell, active conversation appears in the rail.
