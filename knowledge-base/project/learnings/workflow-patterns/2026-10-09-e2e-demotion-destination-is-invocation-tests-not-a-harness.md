# Learning: "Demote to integration layer" resolves to route/middleware-invocation tests, not a server-boot harness

## Problem

Issue #9855 scoped e2e pyramid inversions (Playwright files using only `request.get`, no browser) for "demotion to the integration layer." On inspection there is **no vitest-side harness that boots a Next server** — `test/helpers/bundled-server.ts` is an esbuild-fixture harness, and Playwright's `webServer` only exists inside the e2e runner. A literal reading of "demote" would have required building new infrastructure (machinery scope, owned by #9771).

## Solution

The repo's established pattern for HTTP-contract tests without a browser is **route/middleware invocation in vitest**: `apps/web-platform/test/e2e-oauth-tc-consent.test.ts` already invokes `GET /callback` directly with mocked deps and is named "E2E:" internally while classifying unit/integration by path. Demoted assertions land as:

- **Middleware invocation** for header/wiring assertions (CSP per-route presence, nonce rotation, `x-forwarded-host` connect-src) — call `middleware.ts` with a NextRequest-shaped arg; mock env the way the e2e public project does (fake unreachable Supabase URL).
- **Route-handler invocation** for redirect/status contracts (`/callback` 307s).
- **Deletion** wherever a lower layer already covers the assertion (`oauth-buttons.test.tsx`, `team-membership-resolver.test.ts`, `csp.test.ts` for header *content* vs. e2e's header *wiring*).

Result is better than the issue's target: invocation tests classify **unit**, not merely integration.

## Key Insight

"Integration layer" in the reviewer's classification table is defined by *signals* (real DB/service boot, booted local server — no browser), not by a directory. Before scoping a demotion, check whether a harness for the target signal exists; when it doesn't, invocation tests are the layer-drop that needs no new substrate. Separately: issue-body censuses are measured at write time and drift — `smoke.e2e.ts` was described as "3 tests" but carries 11 at the same SHA. Re-run per-file signal counts before scoping, never inherit them.

## Session Errors

- **Inherited stale census** — issue said "2 of 3 tests" in `smoke.e2e.ts`; actual is 11 (2 browser-needing). Recovery: re-ran per-file `test(`/`request.`/`page.` counts before scoping. Prevention: treat issue-body per-file test counts as stale-by-default; the signal census (`request.*`/`page.*` greps) is the cheap re-verify.
- **Devin harness lacks Soleur domain-leader subagent profiles** — brainstorm Phase 0.5's mandated CPO+CLO+CTO triad could not spawn as named agents (`run_subagent` exposes only `subagent_explore`/`subagent_general`); ran inline with documented substitution. Recovery: inline triad assessment against the verified census. Prevention: recurring on every Devin-side brainstorm until leaders ship as Devin profiles — the substitution must stay visible in the brainstorm doc, not silent.

## Tags

category: workflow-patterns
module: test-infrastructure
related: "#9855, #9762, #9771"
