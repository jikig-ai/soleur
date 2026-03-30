# Tasks: Frontend E2E Testing Coverage

**Issue:** #1217
**Plan:** `knowledge-base/project/plans/2026-03-29-feat-frontend-testing-coverage-plan.md`

## Phase 1: Playwright Setup + All E2E Tests

- [ ] 1.1 Fix `PUBLIC_PATHS` drift bug
  - [ ] 1.1.1 Create `apps/web-platform/lib/routes.ts` with exported `PUBLIC_PATHS`
  - [ ] 1.1.2 Import in `middleware.ts` (replace inline array)
  - [ ] 1.1.3 Import in `test/middleware.test.ts` (replace duplicated array)
- [ ] 1.2 Add `@playwright/test` to `apps/web-platform/package.json` devDependencies
- [ ] 1.3 Create `apps/web-platform/playwright.config.ts`
  - [ ] 1.3.1 Configure `testDir: "./e2e"`, Chrome only
  - [ ] 1.3.2 Configure `webServer`: `bun run build && bun run build:server && NODE_ENV=production node dist/server/index.js`
  - [ ] 1.3.3 Set `webServer.timeout: 60_000`
  - [ ] 1.3.4 Set absolute output paths for test artifacts
  - [ ] 1.3.5 Add `--no-sandbox` launch arg for Linux
  - [ ] 1.3.6 Set `use.trace: "on-first-retry"`
  - [ ] 1.3.7 Set env: `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co`, `NEXT_PUBLIC_SUPABASE_ANON_KEY=test-anon-key`
- [ ] 1.4 Create `apps/web-platform/e2e/smoke.spec.ts`
  - [ ] 1.4.1 CSP nonce: navigate `/login`, listen for `SecurityPolicyViolation` events
  - [ ] 1.4.2 CSP nonce: extract CSP header, parse nonce, verify `<script>` nonce values match
  - [ ] 1.4.3 CSP nonce: load second page, verify nonce differs
  - [ ] 1.4.4 Smoke: `/login` loads, no JS errors, form renders
  - [ ] 1.4.5 Smoke: `/signup` loads, no JS errors
  - [ ] 1.4.6 Smoke: `/health` returns JSON, no CSP header
  - [ ] 1.4.7 Redirect: `/dashboard` unauthenticated -> redirects to `/login`
  - [ ] 1.4.8 Redirect: `/setup-key` unauthenticated -> redirects to `/login`
- [ ] 1.5 Add `"test:e2e": "npx playwright test"` to package.json scripts
- [ ] 1.6 Run locally and verify green

## Phase 2: CI Integration

- [ ] 2.1 Add `e2e` job to `.github/workflows/ci.yml`
  - [ ] 2.1.1 Path filter: `apps/web-platform/**`
  - [ ] 2.1.2 Install Playwright chromium with `--with-deps`
  - [ ] 2.1.3 Cache `~/.cache/ms-playwright/` keyed by lockfile hash
  - [ ] 2.1.4 Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` as URL-shaped dummies
  - [ ] 2.1.5 Run `npx playwright test` in `apps/web-platform/`
  - [ ] 2.1.6 Pin all actions to commit SHAs
  - [ ] 2.1.7 Upload `test-results/` artifact on failure
- [ ] 2.2 Push and verify CI job passes

## Phase 3: Verification

- [ ] 3.1 Confirm E2E job passes on this PR
- [ ] 3.2 Confirm E2E job skipped on non-web-platform changes (path filter)
- [ ] 3.3 Confirm existing `test` job unaffected
