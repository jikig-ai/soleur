---
title: "Pyramid audit remediation: e2e marker backfill, demotions (PR 1 of #9855)"
type: refactor
date: 2026-10-09
slug: test-pyramid-e2e-marker-backfill-demotion
branch: feat-9855-test-pyramid-cleanup
issue: 9855
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Pyramid audit remediation: e2e marker backfill, demotions

## Overview

PR 1 of issue #9855: backfill `pyramid-justified:` markers on the e2e files that survive the cleanup, demote or delete the three layer-inverted e2e files whose assertions need no browser, and route the machinery critiques to #9771 (comment posted). PR 2 of the issue — wiring the 7 dormant env-gated integration suites into CI — is out of scope for this plan and remains open on #9855.

## Problem Statement / Motivation

The test-design-reviewer's pyramid check FAILs any PR adding an e2e-layer test without a `pyramid-justified:` file marker or `## Test Pyramid` PR-body block. All 11 `apps/web-platform/e2e/*.e2e.ts` files predate the convention and carry zero markers (`git grep pyramid-justified apps/web-platform/e2e` → empty at origin/main 01d2b5a0d8) — the next unrelated PR touching any of them FAILs review. Three files additionally exercise no browser: `team-membership.e2e.ts` (2 `request.get` tests + 6 dead `describe.skip` stubs), `oauth.e2e.ts` (2 `request.get` `/callback` tests + 4 DOM-contract tests already covered at unit layer), and ~9 of 11 tests in `smoke.e2e.ts` (pure `request.get` CSP-header assertions).

## Proposed Solution

Verify coverage assertion-by-assertion, then: delete `team-membership.e2e.ts` and `oauth.e2e.ts`; split `smoke.e2e.ts` so its `request.get`-only assertions become middleware-invocation vitest tests (`test/csp-middleware.test.ts`, modeled on `test/e2e-oauth-tc-consent.test.ts`'s route-invocation pattern) while its browser-needing residue stays under a marker; backfill `pyramid-justified:` on every surviving e2e file. No new test harness — "demotion" means invocation tests, which classify unit/integration by path, not a booted-server substrate (that is #9771 machinery).

## Research Insights

**Premise Validation (Phase 0.6):** All cited issues verified live — #9855 OPEN, #9762 CLOSED (machinery shipped via #9766, squash 23aa2aaf86), #9771 OPEN (owns machinery critiques — comment posted), #9763 referenced as budget boundary. All cited files exist on origin/main (11 e2e files, `test/team-membership-resolver.test.ts`, `test/oauth-buttons.test.tsx`, `test/e2e-oauth-tc-consent.test.ts`, `test/conversation-names-settings.test.tsx`, `test/csp.test.ts`, `middleware.ts`, `lib/csp.ts`). ADR corpus grep for `pyramid` → no governing ADR. No stale premises; one stale census number (see Research Reconciliation).

**Property List (Phase 0.6b):** (a) no ambient pyramid-check FAIL on unrelated PRs; (b) browser-free assertions live at their correct layer; (c) zero net coverage loss. **Cut List:** none — the plan proposes no new machinery; markers are an existing convention and invocation tests an existing pattern.

**Key findings (inline census, 2026-10-09):**
- `team-membership.e2e.ts`: 2 active `request.get` tests (flag-off 404; conversation-names reachability) + 6 empty `test()` stubs under `describe.skip`. Flag-off 404 covered by `test/team-membership-resolver.test.ts` AC-A.
- `smoke.e2e.ts`: 11 tests total — `request.*` signals = 10, `page.*` ≈ 6. ~8–9 request-only CSP tests vs 2–3 browser-needing (nonce-matches-script-tag `page.evaluate`, console-CSP-violation `page.on("console")`, `/dashboard` redirect check).
- `oauth.e2e.ts`: 6 tests — 2 `request.get` `/callback` 307-redirect tests (route logic already covered by `test/e2e-oauth-tc-consent.test.ts`'s invocation suite); 4 `page` DOM-contract tests (provider buttons visible/enabled, "or" divider, disabled-until-checkbox on /signup) covered by `test/oauth-buttons.test.tsx` + consent suite.
- `test/csp.test.ts` covers `buildCspHeader` *content* exhaustively; e2e's unique residue is middleware *wiring* (per-route header presence, nonce rotation, `x-forwarded-host` connect-src, `/health` absence) — middleware-invokable without a server.
- No vitest Next-server-boot harness exists; `test/helpers/bundled-server.ts` is an esbuild-fixture harness.
- All 8 surviving e2e files carry heavy real-browser signals (`page.locator`/`page.route`/ws-injector/`browser.newContext`/`getByRole`), so every marker is an honest justification, not a rubber stamp.
- 7 dormant env gates confirmed absent from `.github/` and `scripts/` (`TENANT_INTEGRATION_TEST` is the only wired one, `tenant-integration.yml:715`) — PR 2 scope, not this plan.
- Convention: marker format `pyramid-justified: <reason>` per `plugins/soleur/agents/engineering/review/test-design-reviewer.md` §Justification marker.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `smoke.e2e.ts` "2 of 3 tests are `request.get("/login")` CSP-header assertions" (issue) | 11 tests total; ~8–9 are request-only header/wiring assertions | Split sized against the real count; the demotion volume is ~3× the issue's characterization |
| "Demote … to the integration layer" (issue, implies a home exists) | No booted-server vitest harness exists | Demotion = route/middleware invocation tests (classify unit/integration); a server-boot harness is #9771 machinery |
| Flag-off 404 "already unit-covered" (issue) | Confirmed — `team-membership-resolver.test.ts` AC-A | Delete that assertion; conversation-names reachability re-verified in Phase 1 before file deletion |

## Files to Edit

- `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` — add `pyramid-justified:` marker (ws-injector + `browser.newContext` + `page.locator` DOM assertions)
- `apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts` — add marker (same family; `page.route` interception + ws)
- `apps/web-platform/e2e/cc-soleur-go-security.e2e.ts` — add marker (`browser.newContext` isolation + ws-injector)
- `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts` — add marker (`page.route` timing interception, `waitForURL`, `goBack`)
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — add marker (`page.route` interception, `page.mouse`, `page.evaluate`)
- `apps/web-platform/e2e/otp-login.e2e.ts` — add marker (full OTP login flow through rendered UI)
- `apps/web-platform/e2e/start-fresh-conversations-rail.e2e.ts` — add marker (authenticated project + `page.route`)
- `apps/web-platform/e2e/start-fresh-onboarding.e2e.ts` — add marker (authenticated onboarding flow through rendered UI)
- `apps/web-platform/e2e/smoke.e2e.ts` — remove demoted request-only tests; keep browser-needing residue under marker
- `apps/web-platform/e2e/team-membership.e2e.ts` — **delete** (after Phase 1 coverage ledger is fully green)
- `apps/web-platform/e2e/oauth.e2e.ts` — **delete** (after Phase 1 coverage ledger is fully green)

## Files to Create

- `apps/web-platform/test/csp-middleware.test.ts` — middleware-invocation tests for the demoted `smoke.e2e.ts` assertions (new file; vitest; modeled on `test/e2e-oauth-tc-consent.test.ts`)
- `apps/web-platform/test/<conditional>` — only if Phase 1 finds an assertion with no lower-layer equivalent: demote to an invocation/component test named at that point. Not created pre-emptively.

## Implementation Phases

### Phase 1 — Coverage ledger (precondition for all deletions)

For every active test in `team-membership.e2e.ts`, `oauth.e2e.ts`, and every `request`-only test in `smoke.e2e.ts`: enumerate the assertion, name its lower-layer equivalent (`covered-by`), or mark it `demote-to` a named new test. Output: a per-assertion ledger in the PR description. Also verify `middleware.ts` imports and invokes cleanly in vitest offline (fake/unreachable Supabase env, mirroring the e2e public project). If middleware proves un-invocable for a specific assertion, that assertion stays in e2e under a marker — recorded as a deviation, not silently dropped.

### Phase 2 — Demotions

- Write `test/csp-middleware.test.ts` covering: CSP header present on `/login` + `/signup` responses; `strict-dynamic` + nonce in header; nonce rotates across invocations; `x-forwarded-host` connect-src behavior (accepted + spoofed, the #1075 regression); no CSP header on `/health`; `/dashboard` unauthenticated → `/login` redirect.
- Write any conditional demotions the ledger requires (FR3).
- Delete `team-membership.e2e.ts` and `oauth.e2e.ts` only when their ledger rows are all `covered-by` or `demote-to`-landed.

### Phase 3 — Split + markers

- Edit `smoke.e2e.ts`: remove the demoted tests; keep only browser-needing residue; add its `pyramid-justified:` marker (nonce-on-script-tag DOM evaluation + console CSP-violation listener require real rendering).
- Add `pyramid-justified:` markers to the 8 untouched e2e files, each naming its file-specific browser need (see Files to Edit).

### Phase 4 — Bookkeeping

- Final comment on #9855 recording PR-1 landed state and that PR 2 remains open (Artifacts section already records the scope decision).

## User-Brand Impact

- **If this lands broken, the user experiences:** a regression that deleted e2e coverage used to catch — e.g. a CSP header silently dropped from a public route, or a `/callback` redirect breaking login — reaching production undetected.
- **If this leaks, the user's [data / workflow / money] is exposed via:** workflow — weaker CSP wiring (connect-src spoof acceptance) widening the app's connect surface.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the blast radius of a coverage hole is per-request, so one affected user's login or CSP posture is the unit of harm — but the Phase-1 coverage ledger makes the failure loud (every deleted assertion must name its substitute), keeping this from `aggregate pattern`.

CPO sign-off: brainstorm `## Domain Assessments` carried forward — the CPO assessment confirmed no user-facing surface and named the coverage check as the brand-survival control. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering | none beyond triad (brainstorm carry-forward)

### Engineering (CTO — brainstorm carry-forward)

**Summary:** PR 1 is mechanical — markers, splits, deletions gated on coverage checks. The one architectural call is invocation-test demotion over a new server-boot harness (deferred to #9771 machinery). PR 2 (deferred) holds the real decisions: secrets, cadence, flake budget.

### Product (CPO — mandatory triad, brainstorm carry-forward)

**Summary:** No user-facing surface — test files and CI only. The assertion-coverage ledger before deletion is the brand-survival control.

### Legal (CLO — mandatory triad, brainstorm carry-forward)

**Summary:** No legal/compliance surface; no PII, auth-flow, or regulated-data changes.

**Brainstorm-recommended specialists:** none
**Agents invoked:** none (domain-leader fan-out ran inline on this harness — Devin exposes only generic subagent profiles)

## Open Code-Review Overlap

- #2591 `docs(security): document CSP middleware + route intersection for binary types` — **acknowledge**: a docs issue about the same middleware surface the demoted tests will exercise; different concern (documentation vs. test layer). No fold-in. Note for the work phase: the demoted middleware-invocation tests become executable documentation of the same intersection — a one-line pointer in the new test file's header comment satisfies the adjacency without scope creep.
- All other planned paths: no matches across 88 open `code-review` issues.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Backfill `pyramid-justified:` comments on 10 of 11 `apps/web-platform/e2e/*.e2e.ts` files (all except `team-membership.e2e.ts`)" [issue #9855] | Phase 3; Files to Edit (8 untouched + smoke remnant) | mapped |
| 2 | "Demote or delete `apps/web-platform/e2e/team-membership.e2e.ts`" [issue #9855] | FR1-equivalent Phase 1–2; delete `team-membership.e2e.ts` | mapped |
| 3 | "Split `apps/web-platform/e2e/smoke.e2e.ts` … Move header-only assertions to the integration layer; keep the nonce-on-script-tag DOM check in e2e." [issue #9855] | Phase 2 (`test/csp-middleware.test.ts`) + Phase 3 (smoke split) | mapped |
| 4 | "Evaluate `apps/web-platform/e2e/oauth.e2e.ts` — … Demote what's duplicated, marker what genuinely needs a browser." [issue #9855] | Phase 1 ledger + Phase 2 delete `oauth.e2e.ts` | mapped |
| 5 | "Wire the orphaned env gates into CI." [issue #9855 — PR 2] | — | descoped — justification: operator chose PR-1-only scope; PR 2 needs Doppler dev-Supabase secrets + per-suite cost/flake decisions, remains open on #9855 |
| 6 | "Input to #9771 — machinery critiques … fix there or inline if trivial" [issue #9855] | #9771 comment (posted 2026-10-09) | mapped — deferred to #9771 per the ask's own routing |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `pyramid-justified:` markers on 9 surviving e2e files | "Backfill `pyramid-justified:` comments on 10 of 11 `apps/web-platform/e2e/*.e2e.ts` files" | asked |
| Delete `team-membership.e2e.ts` | "Demote or delete `apps/web-platform/e2e/team-membership.e2e.ts`" | asked |
| Delete `oauth.e2e.ts` | "Demote what's duplicated, marker what genuinely needs a browser" | asked — evaluation concluded all 6 tests duplicated at lower layer |
| `test/csp-middleware.test.ts` | "Move header-only assertions to the integration layer" | asked — mechanism (middleware-invocation vitest) inferred — justification: no booted-server harness exists; invocation tests are the repo's established browser-free HTTP-contract pattern (`e2e-oauth-tc-consent.test.ts`) |
| Phase-1 coverage ledger | — | inferred — justification: the brand-survival control; G3 (zero net coverage loss) is unverifiable without a per-assertion accounting |
| #9771 machinery comment | "Input to #9771 — machinery critiques" | asked |
| #9855 wrap-up comment | — | inferred — justification: records PR-1-done/PR-2-open state on the tracking issue the PR references |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` test files (`e2e/` + `test/`)
- Planned files: ~12 | Estimated changed lines: ~350 (deletions dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] `git grep pyramid-justified apps/web-platform/e2e` returns a `pyramid-justified:` comment in every surviving `.e2e.ts` file (9 files: 8 untouched + smoke remnant)
- [ ] `apps/web-platform/e2e/team-membership.e2e.ts` and `apps/web-platform/e2e/oauth.e2e.ts` are deleted; every removed assertion is accounted `covered-by` or `demote-to` in the PR-body coverage ledger
- [ ] `apps/web-platform/e2e/smoke.e2e.ts` retains only browser-needing tests (no `request`-only test remains) and carries a marker
- [ ] New `apps/web-platform/test/csp-middleware.test.ts` passes locally and covers each demoted CSP-wiring assertion named in Phase 2
- [ ] `test/team-membership-resolver.test.ts`, `test/oauth-buttons.test.tsx`, `test/e2e-oauth-tc-consent.test.ts`, `test/csp.test.ts`, `test/conversation-names-settings.test.tsx` pass unchanged (coverage claims verified, not assumed)
- [ ] No `@playwright/test` import exists outside `apps/web-platform/e2e/` (`git grep -l "@playwright/test" -- apps/web-platform/test` → empty)
- [ ] The `#9771` machinery comment is posted (done) and a wrap-up comment on #9855 records PR-1-landed/PR-2-open
- [ ] PR body uses `Ref #9855`, never `Closes #9855` (PR 2 keeps the issue open)

```yaml
founder_check:
  kind: command
  text: "grep finds a marker in every e2e file"
  command: "git grep -l pyramid-justified -- apps/web-platform/e2e"
  expected: "smoke.e2e.ts"
  pins: {}
  approved_by: "Yes, approve this form"
  approved_at: "2026-10-09"
  hash: "dcd5b396b713cb931a50b6735b5994049cd9c0c55285feb9ec115f41ce00f98e"
```

## Test Scenarios

- Given the 8 surviving e2e files, when any future PR adds a case to them, then the pyramid check finds a marker and does not FAIL for marker absence (`unit` — grep assertion)
- Given `test/csp-middleware.test.ts`, when middleware is invoked with a request for `/login`, then the response carries `content-security-policy` with `strict-dynamic` and a nonce (`unit`)
- Given two consecutive middleware invocations, when the CSP header is read from each response, then the nonces differ (`unit`)
- Given a request carrying a spoofed `x-forwarded-host`, when middleware builds connect-src, then the spoofed host does not appear (regression for #1075) (`unit`)
- Given a `/health` request, when middleware processes it, then no CSP header is attached (`unit`)
- Given `/dashboard` unauthenticated, when invoked, then the response redirects to `/login` (`unit`)
- Given the demoted oauth/team-membership assertions, when the coverage ledger is complete, then each row names `covered-by <test>` or `demote-to <test>` and the e2e files are deleted only afterward (`unit` — ledger review)
- Given the surviving `smoke.e2e.ts` residue, when the e2e job runs, then nonce-DOM + console-violation tests still execute (`e2e` — existing tests, unchanged)

## Success Metrics

- Zero `pyramid-justified` absence FAILs attributable to pre-existing e2e files on subsequent PRs
- e2e file count drops 11 → 9; every deleted assertion has a named lower-layer home
- New middleware-invocation suite runs in the unit/integration CI leg, not the 20-min e2e job

## Dependencies & Risks

- **Risk:** `middleware.ts` may not invoke cleanly in vitest (env/Supabase coupling at import). Mitigation: Phase 1 verifies invocability first; fallback is keeping the assertion in e2e under a marker with a recorded deviation.
- **Risk:** a "covered" claim proves false at work time (unit test asserts something subtly different). Mitigation: the ledger is per-assertion, not per-file — a false claim blocks that row's deletion, not the whole PR.
- **Risk:** Playwright e2e job runtime changes after splits — acceptable; direction is strictly downward.
- **Dependency:** none external. `Ref #9855` (PR 2 open), `Ref #9771` (machinery), `Ref #9762`/`#9763` (classification rules + budget boundary).

## References & Research

- Marker convention + classification table: `plugins/soleur/agents/engineering/review/test-design-reviewer.md` §Pyramid & Fast-Feedback Check
- Invocation-test pattern: `apps/web-platform/test/e2e-oauth-tc-consent.test.ts`
- Issue + census: #9855 (Artifacts section links brainstorm + spec)
- Brainstorm: `knowledge-base/project/brainstorms/2026-10-09-test-pyramid-cleanup-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-9855-test-pyramid-cleanup/spec.md`
- Learning: `knowledge-base/project/learnings/workflow-patterns/2026-10-09-e2e-demotion-destination-is-invocation-tests-not-a-harness.md`
