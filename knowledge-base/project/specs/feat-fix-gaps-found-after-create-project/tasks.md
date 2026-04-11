# Tasks: Fix Gaps Found After Create Project

## Phase 1: Setup

### 1.1 Verify current behavior

- [x] Read `apps/web-platform/app/api/repo/setup/route.ts` from worktree
- [x] Confirm `isStartFresh` is already derived from `body.source === "start_fresh"`
- [x] Confirm `scanProjectHealth()` runs unconditionally after provisioning

## Phase 2: Core Implementation

### 2.1 Write failing test

- [x] Add test in `apps/web-platform/test/` verifying setup route does NOT store health_snapshot when `source` is `"start_fresh"`
- [x] Add test verifying setup route DOES store health_snapshot when `source` is `"connect_existing"` or missing

### 2.2 Conditionally skip health scanner for Start Fresh

- [x] In `apps/web-platform/app/api/repo/setup/route.ts`, wrap `scanProjectHealth()` call with `if (!isStartFresh)` guard
- [x] Ensure `health_snapshot: null` is stored in the DB update for Start Fresh projects
- [x] Verify existing tests pass

## Phase 3: Testing

### 3.1 Run test suite

- [x] Run `cd apps/web-platform && ./node_modules/.bin/vitest run` to verify all tests pass
- [x] Verify project-scanner tests unchanged and passing
- [x] Verify ready-state tests unchanged and passing
- [x] Run `npx markdownlint-cli2 --fix` on changed `.md` files
