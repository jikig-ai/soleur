---
title: "feat: frontend E2E testing coverage"
type: feat
date: 2026-03-29
---

# Frontend E2E Testing Coverage

## Overview

Add Playwright E2E tests to the web platform to catch the class of bugs exemplified
by #1213 (CSP nonce propagation failure that broke sign-in in production). The existing
251 unit tests verify components in isolation but none test the end-to-end pipeline
from middleware through SSR to browser execution.

Closes #1217.

## Problem Statement

Three sign-in bugs reached production undetected by unit tests:

1. **CSP nonce propagation** (#1213) -- middleware generated the nonce correctly but it
   never reached `<script>` tags in rendered HTML
2. **TypeScript PromiseLike** -- type error only caught by `next build`, not `bun test`
3. **Cookie/redirect** -- auth callback set cookies but redirect dropped them

All three passed the 251-test unit suite because tests mock middleware and components
in isolation. No test exercises the assembled pipeline.

## Proposed Solution

Playwright E2E tests that load pages in a real browser against the production-mode
custom server, plus a CI job that blocks merge on failure.

CSP nonce generation in middleware happens before the auth check, so testing on public
pages covers the nonce pipeline completely. Auth E2E tests are deferred (YAGNI -- the
mock Supabase server adds significant complexity for no incremental CSP coverage).

## Technical Approach

### Architecture

```text
┌─────────────────────────────────────────────────────┐
│ CI Workflow (.github/workflows/ci.yml)               │
│                                                      │
│  ┌──────────────┐    ┌───────────────────────────┐  │
│  │ test (exists) │    │ e2e (new job)             │  │
│  │  bun test     │    │  bun run build            │  │
│  │  typecheck    │    │  bun run build:server     │  │
│  │              │    │  node dist/server/index.js │  │
│  │              │    │  playwright test           │  │
│  └──────────────┘    └───────────────────────────┘  │
│          │                       │                    │
│          └───────┬───────────────┘                    │
│                  ▼                                    │
│         Both must pass                               │
└─────────────────────────────────────────────────────┘
```

### File Structure

```text
apps/web-platform/
├── e2e/                          # NEW — Playwright E2E tests
│   └── smoke.spec.ts             # CSP nonce + public pages + redirects
├── lib/
│   └── routes.ts                 # NEW — shared route constants (PUBLIC_PATHS)
├── playwright.config.ts          # NEW
└── package.json                  # MODIFY — add @playwright/test
```

### Implementation Phases

#### Phase 1: Playwright Setup + All E2E Tests

Install Playwright, fix the `PUBLIC_PATHS` drift bug, write all E2E tests.

**Tasks:**

- [x] Fix pre-existing bug: export `PUBLIC_PATHS` from `apps/web-platform/lib/routes.ts`
  and import in both `middleware.ts` and `middleware.test.ts`. The test currently
  duplicates the array and is missing `/manifest.webmanifest`.
- [x] Add `@playwright/test` to `apps/web-platform/package.json` devDependencies
- [x] Create `apps/web-platform/playwright.config.ts` with:
  - `testDir: "./e2e"`
  - `webServer` command: `bun run build && bun run build:server && NODE_ENV=production node dist/server/index.js`
    on a random port (production mode -- dev mode includes `unsafe-eval` in CSP which
    hides real violations)
  - `webServer.timeout: 60_000` (build + cold start)
  - `use.baseURL` from webServer
  - Chrome only (`projects: [{ name: "chromium" }]`)
  - Absolute output paths for screenshots/traces (worktree safety)
  - `launchOptions: { args: ["--no-sandbox"] }` for Linux CI
  - `use.trace: "on-first-retry"` for failure debugging
  - Environment: `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` and
    `NEXT_PUBLIC_SUPABASE_ANON_KEY=test-anon-key` (URL-shaped values required --
    `csp.ts` parses the URL host for CSP directives and crashes on invalid URLs)
- [x] Create `apps/web-platform/e2e/smoke.spec.ts`:
  - **CSP nonce tests:**
    - Navigate to `/login` (public page, no auth needed)
    - Listen for `SecurityPolicyViolation` events (not just console -- CSP violations
      are not guaranteed to appear in console across all browsers)
    - Extract `Content-Security-Policy` response header
    - Parse nonce from CSP header
    - Query all `<script>` elements -- assert each has non-empty `nonce` attribute
    - Verify nonce **value** matches nonce in CSP header (not just attribute existence)
    - Load a second page -- verify nonce differs (not cached/static)
  - **Public page smoke tests:**
    - `/login` -- page loads, no JS errors, login form renders
    - `/signup` -- page loads, no JS errors
    - `/health` -- returns JSON `{ status: "ok" }` (custom server route, no CSP header)
  - **Auth redirect tests:**
    - `/dashboard` unauthenticated -- redirects to `/login`
    - `/setup-key` unauthenticated -- redirects to `/login`
- [x] Add `"test:e2e"`: "npx playwright test"` script to package.json
- [x] Run locally and verify green

**Success criteria:** All E2E tests pass locally. CSP nonce propagation verified.
Public pages load. Protected routes redirect.

#### Phase 2: CI Integration

Add E2E job to GitHub Actions, parallel with existing test job.

**Tasks:**

- [x] Add `e2e` job to `.github/workflows/ci.yml`:
  - Runs in parallel with existing `test` job (no dependency)
  - Path filter: triggers on `apps/web-platform/**` changes
  - Steps:
    1. Checkout (SHA-pinned action)
    2. Setup Bun (from `.bun-version`)
    3. Setup Node.js (for Playwright -- requires Node runtime)
    4. `bun install` (root + apps/web-platform)
    5. `npx playwright install --with-deps chromium`
    6. Set env: `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co`,
       `NEXT_PUBLIC_SUPABASE_ANON_KEY=test-anon-key`
    7. `cd apps/web-platform && npx playwright test`
  - Cache `~/.cache/ms-playwright/` keyed by
    `playwright-${{ hashFiles('apps/web-platform/bun.lock') }}`
  - Pin all actions to commit SHAs
  - Upload `test-results/` as GitHub Actions artifact on failure
    (screenshots, traces -- essential for debugging CI-only failures)
- [x] Verify CI job passes on PR

**Success criteria:** E2E job runs in CI, passes, and blocks merge on failure.
Failure artifacts downloadable.

#### Phase 3: Verification

- [x] Confirm E2E job passes on this PR
- [ ] Confirm E2E job is skipped on a PR that only modifies `plugins/` (path filter)
- [ ] Confirm existing `test` job is unaffected

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| Vitest integration tests | Duplicates Playwright E2E coverage with a second test runner. Every assertion covered by E2E or existing unit tests. |
| Auth E2E via mock Supabase server | CSP nonce is generated before auth check in middleware. Testing public pages covers nonce pipeline. Mock server adds ~150 LOC of fragile auth infrastructure for zero incremental CSP coverage. |
| `/ship` E2E gate | CI already blocks merge on E2E failure. Duplicated gate adds 60+ seconds to every ship cycle and must be kept in sync with CI job. |
| Chromatic/Percy for visual regression | $149-399/mo, premature for 15 components. Playwright `toHaveScreenshot()` at zero cost if needed later. |
| Storybook component tests | Only 15 `.tsx` files, mostly page-level routes with heavy server context. Defer to Phase 3 roadmap. |

## Acceptance Criteria

- [x] Playwright E2E tests verify CSP nonce propagation on a real page load
- [x] E2E tests verify unauthenticated redirect to `/login`
- [x] CI `e2e` job blocks merge on failure
- [x] All existing 251 unit tests continue to pass
- [x] Playwright browser binaries cached in CI
- [x] `PUBLIC_PATHS` exported from shared constants (drift bug fixed)

## Dependencies and Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Bun FPE crash if Playwright mixed with bun test | High | Separate CI job. Never mix Playwright spawns with Bun test runner. |
| Playwright browser cache mismatch in CI | Medium | Cache key includes `bun.lock` hash for exact version match |
| `NEXT_PUBLIC_` env vars missing or malformed in CI | Medium | URL-shaped dummy values set explicitly in CI job |

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** E2E only (integration tests cut as duplicate). Custom server requires
`bun run build && bun run build:server` before production-mode boot. Playwright in
separate CI job avoids Bun FPE crashes.

### Operations (COO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Skip paid vendors. Zero new recurring costs. Real cost risk is CI
minutes -- path-filter E2E job to `apps/web-platform/` changes only.

## References and Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-29-frontend-testing-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-frontend-testing/spec.md`
- Prevention strategies: `knowledge-base/project/learnings/2026-03-27-sign-in-bug-prevention-strategies.md`
- CSP nonce architecture: `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md`
- Playwright cache coupling: `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`
- Bun FPE crash: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`

### Key Implementation Files

- Custom server: `apps/web-platform/server/index.ts`
- Middleware: `apps/web-platform/middleware.ts`
- CSP builder: `apps/web-platform/lib/csp.ts`
- Root layout: `apps/web-platform/app/layout.tsx`
- CI workflow: `.github/workflows/ci.yml`
- App package.json: `apps/web-platform/package.json`

### Related Issues

- Root cause: #1213 (CSP nonce fix -- merged)
- Parent issue: #1217 (this feature)
