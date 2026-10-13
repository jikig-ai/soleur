---
title: "fix: workspace re-provision ensure-dir before clone — tasks"
plan: knowledge-base/project/plans/2026-06-15-fix-workspace-reprovision-ensure-dir-plan.md
lane: single-domain
---

# Tasks — Re-provision self-heal must create the workspace dir before cloning

## Phase 1 — RED (failing test first)

- [x] 1.1 In `apps/web-platform/test/ensure-workspace-repo-graft-race.test.ts`, add `mockMkdir: vi.fn()` to the `vi.hoisted` block.
- [x] 1.2 Add `mkdir: mockMkdir` to the `vi.mock("node:fs/promises", …)` factory (alongside `readdir, cp, rename, rm`).
- [x] 1.3 Add `mockMkdir.mockResolvedValue(undefined)` to `beforeEach`.
- [x] 1.4 Add ONE "creates the workspace dir (recursive) BEFORE cloning" test asserting both `mkdir(WS, {recursive:true})` AND `invocationCallOrder` of mkdir < clone in a single `it` block (deepen: collapsed from two tests).
- [x] 1.5 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/ensure-workspace-repo-graft-race.test.ts` — confirm RED.

## Phase 2 — GREEN (the fix)

- [x] 2.1 In `apps/web-platform/server/ensure-workspace-repo.ts`, add `mkdir` to the `node:fs/promises` import (line 2).
- [x] 2.2 Add `await mkdir(workspacePath, { recursive: true });` as the FIRST statement in `realGraftRepoClone` (before `const tmp = …`), outside the `try`.
- [x] 2.3 Re-run the graft-race suite — confirm GREEN.

## Phase 3 — Verify (resolver preserved + typecheck)

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts test/workspace-resolver.test.ts test/ensure-workspace-repo.test.ts test/ensure-workspace-repo-graft-race.test.ts` — all green.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
