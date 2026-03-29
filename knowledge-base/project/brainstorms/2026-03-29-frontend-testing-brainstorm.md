# Frontend Testing Coverage Brainstorm

**Date:** 2026-03-29
**Issue:** #1217
**Branch:** frontend-testing
**Status:** Decided

## What We're Building

E2E and integration test coverage for the web platform to catch the class of bugs
exemplified by #1213 (CSP nonce propagation failure that broke sign-in). The existing
251 unit tests all pass in isolation but none verify the end-to-end pipeline from
middleware through SSR to browser execution.

Two test layers:

1. **Playwright E2E tests** -- Load pages in a real browser, check for CSP console
   errors, verify nonce attributes on `<script>` tags, test auth flows with cookie
   injection. Boots the full custom server (`tsx server/index.ts`).
2. **Vitest integration tests** -- Exercise the middleware-to-render nonce pipeline,
   SSR correctness, and middleware contracts against the real Next.js request cycle
   (not mocked).

Both layers share the custom server boot logic. A `/ship` gate enforces E2E pass
before merge.

## Why This Approach

- **E2E first:** A Playwright test loading the page would have caught #1213 directly.
  The 2026-03-27 prevention strategies doc (Strategy 1) prescribes this exact approach.
- **Skip paid vendors:** COO assessment: Chromatic ($149+/mo) and Percy ($399+/mo) are
  premature for 15 components with no design system. Playwright's built-in
  `toHaveScreenshot()` covers visual regression at zero cost if needed later.
- **Defer Storybook:** Only 15 `.tsx` files, mostly page-level routes with heavy
  server context dependencies. Poor candidates for isolated stories. Revisit in
  Phase 3 when component count grows.
- **Cookie injection for auth:** Fastest E2E auth approach, no Docker dependency in
  CI, no external network dependency. Fragile if cookie format changes but acceptable
  at current scale.
- **Custom server as test target:** The full custom server is the production path.
  Testing bare `next start` would leave WebSocket upgrade and auth proxy code paths
  untested.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth strategy | Cookie/storage injection | No Docker or network deps in CI. Fastest. |
| Server target | Full custom server | Tests the real production path. |
| Scope | E2E + Integration only | Layers 3 (visual regression) + 4 (Storybook) deferred to Phase 3. |
| Visual regression tool | Deferred (Playwright `toHaveScreenshot()` when needed) | Zero cost, baselines in git, no vendor lock-in. |
| Ship gate | E2E must pass before merge | Prevents #1213 class from recurring. |
| Implementation order | Playwright E2E first, then Vitest integration | E2E delivers immediate value for the exact bug class. |

## Open Questions

- **CI minutes budget:** 30 existing GitHub Actions workflows. Need to verify current
  monthly consumption before adding Playwright CI job. Path-filtered triggers
  recommended.
- **Playwright browser caching in CI:** ~500MB cache. Need to set up GitHub Actions
  cache for browser binaries to avoid re-downloading on every run.
- **`next/test` stability:** Next.js test utilities are still experimental in v15.3.
  May need thin abstraction layer to insulate from API changes.
- **Custom server boot in tests:** Need reliable start/stop lifecycle. `beforeAll` to
  boot server on random port, `afterAll` to tear down. Shared fixture across test
  files.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance,
Support

### Engineering (CTO)

**Summary:** Implement Layers 1 + 2 only. The custom server architecture complicates
the test harness -- tests must boot the full `tsx server/index.ts`, not bare `next
start`. Auth strategy (cookie injection) and CI browser caching are blocking
prerequisites. `next/test` API instability is a medium risk. Existing unit tests
duplicate middleware routing constants (drift risk) that integration tests would
eliminate.

### Operations (COO)

**Summary:** Skip paid vendors entirely (Chromatic, Percy). Playwright's built-in
`toHaveScreenshot()` has zero snapshot limits, baselines live in git, consistent with
the project's "knowledge in committed files" philosophy. Real cost risk is CI minutes,
not vendor fees. Current expense ledger shows ~$32/mo recurring. Free tier snapshot
math: 20 components x 3 viewports x 3 PRs/day = ~5,400 snapshots/month, exceeding
Chromatic's 5,000 free tier.

## References

- Root cause: #1213 (CSP nonce fix)
- Prevention strategies: `knowledge-base/project/learnings/2026-03-27-sign-in-bug-prevention-strategies.md`
- CSP nonce architecture: `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md`
- Negative-space test pattern: `knowledge-base/project/learnings/2026-03-20-csrf-prevention-structural-enforcement-via-negative-space-tests.md`
- Playwright cache coupling: `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`
- Bun test runner gotchas: learnings from 2026-03-18 through 2026-03-20 (segfaults, FPE, timer leaks)
