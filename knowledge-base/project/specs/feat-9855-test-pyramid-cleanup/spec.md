---
title: "Test-pyramid marker backfill + e2e layer cleanup (#9855 PR 1)"
date: 2026-10-09
issue: 9855
lane: cross-domain
brand_survival_threshold: single-user incident
status: captured
brainstorm: knowledge-base/project/brainstorms/2026-10-09-test-pyramid-cleanup-brainstorm.md
---

# Spec — Test-Pyramid Marker Backfill + e2e Layer Cleanup (#9855 PR 1)

## Problem Statement

The test-design-reviewer's pyramid check FAILs any PR that adds an e2e-layer test without a `pyramid-justified:` marker or `## Test Pyramid` PR-body block. The convention postdates all 11 existing `apps/web-platform/e2e/*.e2e.ts` files, so zero markers exist — the next unrelated PR touching any e2e file produces ambient review failures. Separately, three e2e files exercise no browser at all (`request.get`-only assertions): they are pyramid inversions — coverage achievable at a lower layer exercised only at e2e.

## Goals

- G1: Every surviving `apps/web-platform/e2e/*.e2e.ts` file carries a `pyramid-justified:` marker naming its browser need.
- G2: e2e-only assertions that need no browser are either demoted to vitest layer or deleted where unit coverage already exists — assertion-by-assertion, never file-by-file.
- G3: No net loss of behavioral coverage: every deleted/demoted assertion has a verified equivalent at a lower layer before removal.

## Non-Goals

- PR 2 of #9855 (wiring the 7 dormant env-gated integration suites into CI) — deferred; needs Doppler dev-Supabase secrets + cost/flake decisions.
- Machinery-shape changes (named-dir precedence, `*.test.sh` ratchet, `hasTests` regex, `mu1-integration` naming, unweighed e2e layer) — routed to #9771 via issue comment, unless a fix is truly trivial.
- A booted-server vitest harness for Next — no such harness exists; building one is #9771 machinery scope.

## Functional Requirements

- **FR1** — `team-membership.e2e.ts` deleted. Preconditions verified at plan/work time: the flag-off 404 assertion is covered by `test/team-membership-resolver.test.ts` (AC-A); the conversation-names reachability assertion is either covered by `test/conversation-names-settings.test.tsx` or demoted as a route-invocation test; the 6 `describe.skip` stubs are dead spec text.
- **FR2** — `smoke.e2e.ts` split: the ~8–9 `request.get`-only CSP-header/wiring assertions move to a new vitest file (e.g. `test/csp-middleware.test.ts`) invoking `middleware.ts` directly — header presence per route, nonce rotation across invocations, `x-forwarded-host` connect-src handling, `/health` header absence. The browser-needing residue (nonce-matches-script-tag DOM check, console-CSP-violations listener, and anything else using `page`) stays in `smoke.e2e.ts` under a `pyramid-justified:` marker.
- **FR3** — `oauth.e2e.ts` kept trimmed + marked after a per-test coverage check [Updated 2026-10-09: operator merge call — served-page wiring is browser-level]: `/callback` 307-redirect cases against `test/e2e-oauth-tc-consent.test.ts` (route-invocation suite already covers callback redirects incl. `next`-param handling); DOM-contract cases against `test/oauth-buttons.test.tsx` + the consent suite. Any assertion without a lower-layer equivalent is demoted to a route-invocation or component test, not dropped.
- **FR4** — `pyramid-justified:` marker backfilled on every surviving e2e file (the 8 untouched files + the `smoke.e2e.ts` remnant), each naming its file-specific browser need (e.g. `nav-states-*` intercept `page.route` timing; `cc-soleur-go-*` use ws-injector + `browser.newContext`; `start-fresh-*` need the authenticated project).
- **FR5** — A comment on #9771 enumerates the 5 machinery critiques from #9855 (named-dir precedence, `*.test.sh` ratchet, `hasTests` regex vs `*.e2e-utils`/`setup.e2e.config`, `mu1-integration` spelling, unweighed e2e layer); a comment on #9855 records that PR 1 landed and PR 2 remains open.

## Technical Requirements

- **TR1** — Demoted tests use route/middleware invocation, following the `test/e2e-oauth-tc-consent.test.ts` pattern (direct handler/middleware call with mocked deps). No `@playwright/test` import may enter a file outside `apps/web-platform/e2e/`.
- **TR2** — Verify `middleware.ts` is invocable in vitest offline before writing FR2 tests; if it requires Supabase env, mock or shim it the way the e2e public project does (fake unreachable URL). If invocation proves infeasible for a specific assertion, that assertion stays in e2e under a marker — recorded as a plan deviation.
- **TR3** — Marker comment format is `pyramid-justified: <reason>` placed near the top of each file, matching the `test-design-reviewer.md` convention.
- **TR4** — No changes outside `apps/web-platform/e2e/` and `apps/web-platform/test/`; no CI workflow edits (PR 2 scope).

## Acceptance Criteria

- [ ] `git grep pyramid-justified apps/web-platform/e2e` returns a marker in every surviving `.e2e.ts` file.
- [ ] `team-membership.e2e.ts` no longer exists and `oauth.e2e.ts` is reduced to browser-required tests under a marker; each removed assertion is accounted for (unit-covered or demoted).
- [ ] `smoke.e2e.ts` retains only browser-needing tests; the moved assertions live in a vitest file that passes locally.
- [ ] `test/e2e-oauth-tc-consent.test.ts`, `test/oauth-buttons.test.tsx`, `test/csp.test.ts`, `test/team-membership-resolver.test.ts`, `test/conversation-names-settings.test.tsx` still pass (coverage claims re-verified, not assumed).
- [ ] Comments posted on #9855 (PR 1 landed / PR 2 open) and #9771 (machinery critiques enumerated).

## User-Brand Impact

Artifact: the e2e test layer of `apps/web-platform`. Worst-case vector: deleted e2e coverage masking a real regression (CSP header silently dropped, `/callback` redirect broken) reaching a user. Control: the per-assertion coverage check in G3 gates every deletion. Threshold: `single-user incident`.

## Domain Assessments (carry-forward from brainstorm)

- Product: no user-facing surface; the coverage check is the brand-survival control.
- Legal: no regulated-data surface; `soleur:gdpr-gate` not triggered.
- Engineering: mechanical scope; the only architectural call is invocation-test demotion over a new harness (deferred to #9771).
