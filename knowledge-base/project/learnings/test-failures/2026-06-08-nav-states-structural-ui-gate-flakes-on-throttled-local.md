# Learning: discriminating nav-states structural-UI e2e flakes from real regressions on a throttled local machine

## Problem

During `/soleur:qa`'s Step 2.6 structural-UI visual gate (BLOCKING) on a presentational-only diff to `apps/web-platform/components/dashboard/workspace-context-band.tsx`, `playwright test nav-states --project=authenticated` reported **3 failed / 16 passed**. The failures (`Chat collapsed`, `expanded secondary-nav PRESENT`, `widenable-rail width-persist`) looked alarming on a gate whose whole purpose is to catch CSS regressions jsdom can't see.

## Root Cause

The failures were **local-environment browser-context crashes**, not a code regression:

- The persistent failure was `page.goto: Target page, context or browser has been closed` navigating to `/dashboard/chat` — a crash at the **navigation layer, before any band assertion ran** (the band-render assertion is several lines after `gotoOrSkip`).
- The first run showed a multi-test "Target page, context or browser has been closed" **cascade** — classic resource exhaustion. This machine has the documented BD_PROCHOT throttle (all cores pinned ~400-700MHz), which starves headless Chromium.
- CI runs the same e2e in a **resourced Playwright container** (`mcr.microsoft.com/playwright:v1.58.2-jammy`, `ci.yml` job `e2e`) — that container, not the local laptop, is the authoritative gate.

## Solution

Discrimination procedure (flake vs. regression) for the `nav-states` gate:

1. **Does the diff touch the failing tests?** `git diff origin/main...HEAD -- apps/web-platform/e2e/nav-states-shell.e2e.ts | grep -E '^[+-]'` and check the failing tests' line ranges. If untouched → strong flake signal.
2. **Do the tests that render the surface the diff *actually changed* pass?** Here the diff only swapped two collapsed `live-repo-dot` assertions for `workspace-identity-icon`; both those tests (collapsed top-level + collapsed Settings) passed, as did collapsed KB. The gate's real purpose was satisfied.
3. **Where does the failure occur?** A failure at `page.goto`/browser-close (before the assertion) is an infrastructure crash, not an assertion failure about your change.
4. **Re-run the failing tests in isolation.** Flakes that came from a cascade pass on isolated re-run (2 of 3 did here).
5. **Confirm the CI baseline.** CI runs e2e in a container; that's the authoritative gate the PR passes through.

If all of (1)-(3) point to "untouched + crash-at-navigation + changed-surface-passes", classify as a pre-existing local env flake, record it in the QA report, and proceed — do not block the pipeline or "fix" unrelated tests.

## Key Insight

A BLOCKING visual-regression gate can produce non-blocking failures when the *runner* is resource-starved. The discriminator is **provenance + failure-layer**: a failure in a test your diff never touches, occurring at the browser/navigation layer before any assertion, on a machine known to throttle, is an environment flake — the authoritative gate is CI's containerized e2e, not the local laptop.

## Addendum (2026-07-07): webServer-startup build race + kill-by-port

A second flake shape on the same throttled machine, distinct from the navigation-crash above — it fails **before any test runs**:

- `playwright test nav-states --project=authenticated` aborts with `Error: Process from config.webServer was not able to start. Exit code: 1`. The `playwright.config.ts` `webServer` array launches **two** `npm run dev` processes (public `3099` + auth `3100`) concurrently, and both build into the same `.next/dev-server.mjs` — a concurrent-build race that intermittently exits 1. `rm -rf .next` + retry does NOT fix it (the race is between the two servers, not stale artifacts).
- **Workaround:** pre-start both dev servers **sequentially** in the background (so the `.next` build happens once and the second server reuses it), wait for each port to answer, then run `playwright test` — with `reuseExistingServer: true` (the default when not CI) playwright reuses them and skips its own racing launch. Auth server env: `PORT=3100 NEXT_PUBLIC_SUPABASE_URL=http://localhost:54399 SUPABASE_URL=http://localhost:54399 SUPABASE_SERVICE_ROLE_KEY=test-service-role-key npm run dev`. A `307` on `/` is the expected auth redirect = ready.
- The custom `npm run dev` server spawns a child that **survives `kill <launcher-pid>`** — `kill` reports success but the port stays bound. Stop it by port: `lsof -ti tcp:3099 tcp:3100 | xargs kill -9`.
- Same discriminator applies: the 2 tests that still failed (`nav-states:600`/`:614`, chat conversation-rail) are on a component the diff never touched, are data-population/timing-bound, and one flipped FAIL→PASS on isolated re-run — flake, not regression. CI's containerized e2e is authoritative.

## Tags
category: test-failures
module: apps/web-platform/e2e (nav-states structural-UI gate)
