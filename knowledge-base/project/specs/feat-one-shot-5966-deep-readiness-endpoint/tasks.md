# Tasks — feat(infra): deep-readiness endpoint `/internal/readyz` (#5966)

lane: single-domain
Plan: `knowledge-base/project/plans/2026-07-03-feat-deep-readiness-endpoint-workspaces-mount-plan.md`
Brand-survival threshold: single-user incident (fail-closed is load-bearing)

## Phase 1 — Readiness builder

- [ ] 1.1 Create `apps/web-platform/server/readiness.ts` with `ReadinessResponse` interface + `buildReadinessResponse()`.
- [ ] 1.2 Implement `isDistinctMountpoint(root)` via `statSync(root).dev !== statSync(dirname(root)).dev`; any stat error → `false` (fail-closed).
- [ ] 1.3 Resolve `WORKSPACES_ROOT` at call time (`process.env.WORKSPACES_ROOT || "/workspaces"`).
- [ ] 1.4 `workspaces_populated = getActiveWorkspaceCount() > 0` (reuse `session-metrics.ts`, do not re-implement the scan).
- [ ] 1.5 `git_data_consistent` compose-later slot: `true` when `isGitDataStoreEnabled()` off (pre-GA default).
- [ ] 1.6 `ready = workspaces_mounted && workspaces_populated && git_data_consistent`.

## Phase 2 — Route wiring

- [ ] 2.1 In `server/index.ts`, add `/internal/readyz` route directly after `/internal/metrics`.
- [ ] 2.2 Gate with existing `isLoopbackHost(req.headers.host)` → 403 on non-loopback (mirror metrics).
- [ ] 2.3 `res.writeHead(readiness.ready ? 200 : 503, ...)`; import `buildReadinessResponse` from `./readiness`.
- [ ] 2.4 Leave `/health` and `/internal/metrics` untouched.

## Phase 3 — Tests

- [ ] 3.1 Create `test/server/readiness.test.ts`; mock `fs.statSync` + `./session-metrics` before SUT import (health.test.ts pattern).
- [ ] 3.2 Case: mounted (dev≠parent) + count 5 → `ready:true`.
- [ ] 3.3 Case: mounted + count 0 (bare-host sim) → `ready:false`, `workspaces_populated:false`. (AC-required)
- [ ] 3.4 Case: unmounted (dev===parent) → `ready:false`, `workspaces_mounted:false`.
- [ ] 3.5 Case: `statSync` throws → `ready:false` (fail-closed).
- [ ] 3.6 Case: git-data flag off → `git_data_consistent:true`, does not block ready.
- [ ] 3.7 Case: `isLoopbackHost` contract — public Host → 403 path; `127.0.0.1`/`localhost`/`::1` → served.
- [ ] 3.8 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts test/server/health.test.ts` (both green).
- [ ] 3.9 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Phase 4 — ADR + C4

- [ ] 4.1 Add ADR-068 amendment (`## Decision`, dated) recording the readiness contract + mount+populated identity semantics + necessary-but-not-sufficient framing.
- [ ] 4.2 Confirm "no C4 impact" enumeration against `model.c4` / `views.c4` / `spec.c4` (no `.c4` edit needed).

## Phase 5 — Docs / runbook reference

- [ ] 5.1 Update blue-green plan Sharp Edge C1 (`2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` lines 273-277) → "delivered — `/internal/readyz` pre-pool gate".
- [ ] 5.2 `gh issue comment 5946` referencing `/internal/readyz` as the pre-pool readiness gate (post-merge / ship).
- [ ] 5.3 PR body `Closes #5966` + `Ref #5946`.
