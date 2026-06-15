# Tasks — Fix: C4 Code-tab Save does not persist across a page refresh

Plan: `knowledge-base/project/plans/2026-06-15-fix-c4-code-save-not-persisting-across-refresh-plan.md`
Lane: cross-domain
Supersedes: the 2026-06-12 plan (#5220 shipped F-A1 client optimistic apply + F-B; this fix closes the deferred server-side slice).
Mandatory fix: **F-D — `GET /api/kb/c4/project` reads `.c4` sources + `model.likec4.json` from the GitHub source of truth (Contents listing for shas → Git Blobs API for bodies), removing the dependency on the stale on-disk clone.**
Brand-survival threshold: single-user incident (requires CPO sign-off before /work).

## Phase 0 — Preconditions (verify against installed code; one sweep)

- [x] 0.1 Confirm shapes: `resolveActiveWorkspaceRepoMeta` returns `{ repoUrl, githubInstallationId }` + accepts `preResolvedActiveWorkspaceId` (`server/workspace-resolver.ts:473`); owner/repo parse precedent `app/api/kb/upload/route.ts:198-201`; base64-decode read precedent `server/inngest/functions/cron-ruleset-bypass-audit.ts:100-120`; confirm whether `githubApiGet` returns the Git Blobs `{ content, encoding }` shape directly or needs a thin wrapper. Record in PR body.
- [x] 0.2 Open Code-Review overlap: NONE. `gh issue list --label code-review --state open --json number,title,body --limit 200` then `jq` for `project/route.ts` and `c4-project-route.test.ts`. Record in `## Open Code-Review Overlap`.
- [x] 0.3 Confirm CPO sign-off (auto-accepted in pipeline per plan §Product/UX Gate) on the GitHub-primary approach (single-user-incident threshold).

## Phase 1 — RED (failing tests first)

- [x] 1.1 APPEND F-D cases to the EXISTING `apps/web-platform/test/c4-project-route.test.ts` (do NOT create). Add a `githubApiGet`/Blobs mock per `c4-writer-rerender.test.ts` (`vi.hoisted` + `vi.mock("@/server/github-api", …)` + `vi.importActual`); it must coexist with the file's existing real-tmpfs suites. Mock GitHub to return the POST-edit `.c4` + `model.likec4.json`; assert the current on-disk-only route does NOT serve them → RED. (AC1)
- [x] 1.2 Test: a 1–4 MB `model.likec4.json` fetched via the Blobs API base64-decodes fully and serves the complete dump (fails on a Contents-`content` impl). (AC2)
- [x] 1.3 Tests: `dir` with `..` → 400 + zero GitHub fetch (AC3); invited member reads SHARED workspace repo (AC4); GitHub read throws → 503, no stale body (AC5); GitHub 404 on model → `MODEL_NOT_BUILT` 404 (AC6); >4 MB blob → 413 (AC7); op-contract slug `c4-project-read`/`github-read-failed` (AC8).

## Phase 2 — GREEN (minimal implementation)

- [x] 2.1 `app/api/kb/c4/project/route.ts`: resolve `activeWorkspaceId` (reuse existing `resolveActiveWorkspaceKbRoot`), then `resolveActiveWorkspaceRepoMeta(user.id, serviceClient, activeWorkspaceId)`; parse owner/repo from `repoUrl` (copy `upload/route.ts:198-201`).
- [x] 2.2 List the diagrams dir via the Contents API pinned to one HEAD `sha` (`?ref={sha}`) for per-file blob shas; fetch each body via `GET /repos/{owner}/{repo}/git/blobs/{sha}` (Blobs API), base64-decode, enforce `MAX_C4_BYTES`. Build `sources` (`.c4` + `README.md`, same filter as `project/route.ts:122-124`) and `dump` (`model.likec4.json`). Preserve `viewIds` + `Cache-Control: private, no-cache`.
- [x] 2.3 Map GitHub 404 on the model blob → `MODEL_NOT_BUILT` 404 (`project/route.ts:92-100`); any other GitHub-read failure → 503 + `reportSilentFallback(feature:"c4-project-read", op:"github-read-failed")`. Remove the on-disk `fs.open`/`O_NOFOLLOW` read blocks (no longer read by this route).
- [x] 2.4 Keep the `dir`-string guards before any GitHub path is built: `..`/NUL rejection (`project/route.ts:58-65`), `isPathInWorkspace`, 401 auth gate.

## Phase 3 — Guards & regression

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (AC9).
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` green (full suite 9881 passed) for `test/c4-project-route.test.ts` (existing + new) and the three existing C4 suites (`c4-code-panel.test.tsx`, `c4-writer-rerender.test.ts`, `c4-workspace.test.tsx`) (AC9).
- [x] 3.3 Filed #5309 (public shared/[token]/c4 stale-clone follow-up) (a #5221 sub-item or new issue) for the public `app/api/shared/[token]/c4/route.ts:85,123` stale-clone bug (identical root cause, external viewers). Do NOT leave as a soft note.

## Phase 4 — Tracking-issue update (NOT close)

- [x] 4.1 Commented on #5221 (scope-narrowing, NOT closed): (a) C4 read slice mitigated by F-D's GitHub-primary read; (b) `tree`/`content`/`search`/`share` + public `shared/[token]/c4` read the same stale clone and need the same policy (ideally a reusable helper) in the reconcile redesign; (c) write/reconcile liveness gap + `rev-list→reset` TOCTOU mutex remain the core open work. Use `Ref #5221` in the PR body, never `Closes #5221`. (AC10)

## Phase 5 — Post-merge (operator)

- [ ] 5.1 Live dogfood on the dev-cohort deployment: KB → C4 page → Code tab → edit a label in `model.c4` → Save → **refresh the page** → confirm the edit persists in BOTH the editor and the rendered diagram. (Automation not feasible — a permanently-diverged prod clone cannot be reproduced in synthetic CI; unit tests cover the route logic deterministically.) (AC11)
