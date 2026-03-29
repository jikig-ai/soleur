# Frontend Testing Coverage Spec

**Issue:** #1217
**Branch:** frontend-testing
**Date:** 2026-03-29

## Problem Statement

The web platform has 251 unit tests that all pass in isolation, but zero tests verify
the end-to-end pipeline from middleware (CSP nonce generation) through SSR rendering
to browser execution. The CSP nonce propagation bug (#1213) broke sign-in in
production and was undetected by the entire test suite.

## Goals

- G1: Catch the #1213 class of bugs (middleware-to-browser pipeline failures) before
  they reach production
- G2: Verify CSP nonce propagation from middleware through `<script>` tag rendering
- G3: Validate auth flows (sign-in, sign-out, protected routes) in a real browser
- G4: Enforce E2E test passage as a merge gate via `/ship` and CI

## Non-Goals

- Visual regression testing (deferred to Phase 3 -- insufficient component count)
- Storybook component isolation testing (deferred to Phase 3)
- Post-deploy smoke tests against production (separate concern)
- Full browser matrix testing (Chrome only for now)

## Functional Requirements

- FR1: Playwright E2E test suite that boots the full custom server and loads pages in
  a real browser
- FR2: E2E tests verify no CSP console errors on page load
- FR3: E2E tests verify nonce attributes present on inline `<script>` tags
- FR4: E2E tests verify auth flow with cookie/storage injection (sign-in page loads,
  protected routes redirect, authenticated state works)
- FR5: Vitest integration tests that exercise the middleware-to-render nonce pipeline
  against the real Next.js request cycle
- FR6: Integration tests verify `x-nonce` header propagation through middleware exit
  paths
- FR7: CI workflow job that runs E2E tests with Playwright browser caching
- FR8: `/ship` gate that blocks merge when E2E tests fail

## Technical Requirements

- TR1: Tests boot the full custom server (`tsx server/index.ts`) on a random port
- TR2: Server lifecycle managed via shared fixture (`beforeAll`/`afterAll`)
- TR3: Auth handled via Playwright cookie/storage injection (no Docker, no network)
- TR4: Playwright browser binaries cached in GitHub Actions (~500MB)
- TR5: E2E tests path-filtered in CI (only run on `apps/web-platform/` changes)
- TR6: Tests run sequentially in CI (Bun FPE crash risk with parallel suites)
- TR7: `afterEach` cleanup for timers/subscriptions (Bun segfault prevention)
- TR8: Environment variables from Doppler `ci` config or test-specific values

## Acceptance Criteria

- [ ] Playwright E2E tests pass locally and in CI
- [ ] At least one E2E test loads a page and asserts no CSP violations in console
- [ ] At least one E2E test verifies nonce attribute on `<script>` tags
- [ ] At least one integration test exercises the middleware nonce pipeline
- [ ] CI workflow includes E2E job with browser caching
- [ ] `/ship` skill includes E2E gate
- [ ] All existing 251 unit tests continue to pass
