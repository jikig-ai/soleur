---
category: workflow
module: qa
created: 2026-05-11
related_pr: 3557
related_issue: 3562
---

# Learning: Pure-CSS fixes can degrade Playwright QA to unit-test className contracts when dev server is broken

## Problem

PR #3557 fixed two settings-sidebar UI bugs via a 2-line Tailwind utility class change. The plan's Phase 6 required Playwright `yDelta` measurement and screenshots across 4 toggle-state combinations. The dev server (`npm run dev` in `apps/web-platform/`) failed to start with:

```
ReferenceError: An error occurred while loading instrumentation hook: require is not defined in ES module scope
  at <unknown> (.next/server/instrumentation.js:425:27)
```

Root cause: Next.js compiles `instrumentation.ts` to CJS `require()` output, but `package.json` has `"type": "module"`. Pre-existing on `main` (verified via `git show main:apps/web-platform/package.json`). Filed as #3562.

## Solution

Accepted degraded QA: relied on the 17/17 passing vitest assertions in `apps/web-platform/test/settings-sidebar-collapse.test.tsx` to verify the className contract (`min-h-7` on header row, `md:pl-8` conditional on collapsed content area, locked-in classes from PR #2494/#2504 preserved). Filed #3562 with `pre-existing-unrelated` scope-out criterion citing PR #3557 as the discovery context.

The plan's own Risks section already justified the className-token approach:

> `getBoundingClientRect()` in JSDOM returns zeros. The numeric `yDelta` assertion is Playwright-only (real browser). The unit test asserts only the presence of `min-h-7`, NOT the computed pixel-level alignment — JSDOM cannot measure it. This is by design: classname tests are regression gates; Playwright is the alignment source of truth.

So the unit tests are not a substitute for pixel verification — they're the regression gate. The pixel verification is downgrade-tolerable for pure-CSS-utility-class fixes where the geometry math is in the plan and the classes are asserted.

## Key Insight

**When a Playwright QA gate is blocked by a pre-existing dev-server bug, escalate by criterion, not by hand-wringing.** The QA skill's graceful-degradation policy already allows skipping browser scenarios when the dev server times out. For pure-CSS-utility-class fixes whose `User-Brand Impact` threshold is `none` AND whose className contracts are unit-tested, the degraded QA path is sufficient. For functional/data/auth fixes, it is not — in those cases, fixing the dev-server bug becomes load-bearing before the original PR can merge.

The discriminator: **does the plan's geometry/contract reduce to "the right classes are present"?** If yes, vitest covers it. If no (interactive flows, OAuth, payments, data writes), Playwright is required and the dev-server bug becomes a blocker, not a sidequest.

## Session Errors

- **Dev server failed to start (pre-existing instrumentation.js ESM/CJS conflict)** — Recovery: filed #3562, degraded QA to unit-test className contract. Prevention: rename `instrumentation.ts` to `instrumentation.cts` OR remove the file (per its own comment, `register()` is never called by Next.js with a custom server).

## Tags

category: workflow
module: qa
