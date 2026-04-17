---
title: Next.js 15 App Router rejects non-HTTP-method exports from route.ts (production outage class)
date: 2026-04-15
category: runtime-errors
tags:
  - nextjs
  - app-router
  - route-handlers
  - typescript
  - docker-build
  - ci-gap
  - production-outage
module: apps/web-platform
---

# Learning: Next.js 15 App Router rejects non-HTTP-method exports from `route.ts`

## Problem

PR #2347 (KB chat sidebar) merged to main green — 1463 vitest tests,
clean `tsc --noEmit`, all PR checks passing. Web Platform Release fired
on the merge commit and failed inside the Docker build step ~1 minute
after merge with:

```text
Type error: Route "app/api/analytics/track/route.ts" does not match
the required types of a Next.js Route.

ERROR: failed to build: failed to solve:
process "/bin/sh -c npm run build" did not complete successfully: exit code: 1
```

Production stayed on the previous version while new merges kept
landing. Hotfix PR #2401 was opened, auto-merged, and the next release
run succeeded — total window ~15 minutes.

## Root cause

The Next.js 15 App Router's route-file validator only allows a
fixed set of exports from any file matching `app/**/route.{ts,tsx,js,jsx}`:

- HTTP method handlers: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`
- Framework-recognized config exports: `runtime`, `dynamic`, `revalidate`,
  `fetchCache`, `dynamicParams`, `preferredRegion`, `maxDuration`,
  `generateStaticParams`, `metadata`/`generateMetadata`

Anything else triggers a build-time type error. My route file exported
two additional symbols — a stateful `SlidingWindowCounter` instance and
a test-only reset helper:

```ts
// app/api/analytics/track/route.ts
export const analyticsTrackThrottle = new SlidingWindowCounter({...});
export function __resetAnalyticsTrackThrottleForTest(): void {
  analyticsTrackThrottle.reset();
}
```

The throttle is genuinely stateful (in-memory per-IP counter) and the
test helper resets it between vitest runs. Both are legitimate, but
they cannot live in the route file.

## Why tests missed it

Vitest imports the module as a plain ES module. It does **not** run
the Next.js route-file validator — that validator only fires during
`next build` (or `next lint`). So every local test passed:

- `tsc --noEmit` — PASS (TypeScript alone accepts the exports)
- `vitest run` — PASS (10/10 analytics tests green, no direct import of
  the private helper; tests isolate via env vars + `vi.resetModules()`)
- `next build` — **never run in PR CI** for this repo

The outage was latent on the branch from Phase 5 (the route landed in
commit `7306aae9` in PR #2347). It sat green through the full review +
preflight + ship pipeline and only surfaced when `next build` ran inside
the Docker image during the post-merge release workflow.

## Solution

Move the non-HTTP exports into a sibling module:

```text
app/api/analytics/track/
├── route.ts       # exports only GET + POST (HTTP handlers)
└── throttle.ts    # exports analyticsTrackThrottle + __reset...
```

`route.ts` imports from `./throttle`. No behavior change, no state
relocation — the singleton still lives at module scope, still shared
across all requests in the instance. Test imports didn't need updating
because the tests used `vi.resetModules()` + env-var reset rather than
directly calling the helper.

```ts
// app/api/analytics/track/throttle.ts (new)
import { SlidingWindowCounter } from "@/server/rate-limiter";

const RATE_PER_MIN = parseInt(
  process.env.ANALYTICS_TRACK_RATE_PER_MIN ?? "120",
  10,
);

export const analyticsTrackThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: RATE_PER_MIN,
});

export function __resetAnalyticsTrackThrottleForTest(): void {
  analyticsTrackThrottle.reset();
}
```

```ts
// app/api/analytics/track/route.ts
import { analyticsTrackThrottle } from "./throttle";
// ... GET + POST handlers use the throttle as before ...
```

Verification:

- `npx next build` → `✓ Compiled successfully in 55s`
- `vitest run test/api-analytics-track.test.ts` → 10/10 pass
- Post-hotfix release run 24478421955 completed `success`; context_path
  column live in prod (REST API returns 200).

## Key Insight

**CI must run the same build command the deploy step runs.** PR #2347
had vitest, tsc, lint, lockfile-sync, CodeQL, dependency-review, and
readme-counts all running in PR CI — a comprehensive gate — but NOT
`next build`. The Docker image's `RUN npm run build` step was the only
caller of `next build` in the entire pipeline, and it only ran post-merge.

This is a specific instance of a general rule: **every command that
gates production must also gate the PR**. If `npm ci` decides merge
readiness in Docker, then `npm ci` belongs in PR CI. If `next build`
decides merge readiness in Docker, then `next build` belongs in PR CI.
The symmetry isn't optional — any asymmetry is latent production risk.

A narrower companion check: an ESLint rule or a custom script that
scans `apps/*/app/**/route.ts` for non-HTTP-method exports catches
this specific class in milliseconds instead of the full 55s `next build`
cost. File #2402 tracks adding both.

### Corollary rules for future work

1. **When writing an App Router route file, keep only HTTP method
   handlers and Next.js-recognized config exports in it.** Any other
   export — a singleton, a helper, a constant — goes in a sibling
   module. Tests import from the sibling; the route file stays minimal.
2. **When authoring a CI pipeline, list every command that runs in the
   deploy path and mirror it in the PR pipeline.** The deploy-only gaps
   are where latent outages live. If a command is too slow for every PR,
   gate it on path filters (`paths: apps/web-platform/**`) so it at
   least fires on the PRs that can break it.
3. **When a production outage is resolved, file the pre-merge guard as
   a follow-up issue in the same commit window as the hotfix.** The
   outage fix is necessary but not sufficient — the guard closes the
   class. Issue #2402 tracks the pre-merge `next build` gate.

## Session Errors

1. **`next build` was not run in the local verification step of the
   /work or /ship pipelines for PR #2347.** The ship skill's Phase 4
   runs `scripts/test-all.sh` (which itself doesn't invoke `next build`
   because web-platform uses vitest under happy-dom, a different test
   stack). Preflight checks security headers on prod and migrations via
   Supabase REST, but doesn't build the app.
   - **Prevention:** Add a `next build` step to the web-platform PR CI
     workflow gated on `paths: apps/web-platform/**`. Also consider a
     lint rule scanning route files for non-HTTP exports. Tracked in
     #2402.

## Related Learnings

- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` —
  companion learning for the same PR. Multi-agent review caught three
  P1 bugs that tests missed, but **didn't catch this one** because
  review agents also don't run `next build`. The outage class is
  "latent in shipped code that passes every pre-merge gate" — both
  learnings document different failure modes with the same shape.
- `2026-03-26-nextjs-15-middleware-cookie-api-breaking-change.md` —
  prior Next.js 15 gotcha (cookies API change). Same theme: silent
  build-time / runtime validator changes that only fire on a specific
  command.

## Related Issues + PRs

- Originating PR: #2347 (kb-chat-sidebar, merged commit `e3a2acc3`)
- Failing release run: [24477947581](https://github.com/jikig-ai/soleur/actions/runs/24477947581)
- Hotfix PR: #2401 (merged commit `1f8ebc96`)
- Passing release run: 24478421955
- Follow-up guard: #2402 (add `next build` to PR CI + route-export lint) — resolved by PR #2444 which adds the `web-platform-build` job to `.github/workflows/ci.yml` running `next build` on every PR.
