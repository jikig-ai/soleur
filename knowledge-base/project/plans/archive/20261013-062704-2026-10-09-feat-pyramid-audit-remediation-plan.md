---
title: "Pyramid audit remediation: e2e marker backfill, demotions, machinery fixes"
date: 2026-10-09
slug: feat-pyramid-audit-remediation
branch: feat-9855-pyramid-audit-remediation
issue: 9855
type: chore
lane: single-domain
---

# Pyramid audit remediation: e2e marker backfill, demotions, machinery fixes

## Overview

The read-only pyramid audit against the #9766 machinery (`test-design-reviewer.md`
§Pyramid & Fast-Feedback Check; squash `23aa2aaf86`, audit base `origin/main`
`01d2b5a0d8`) found the corpus upright by file count (~98/1.5/0.5%) but carrying a
complete `pyramid-justified:` marker backlog on the e2e layer, two clear
e2e→lower-layer inversions, and five machinery critiques. This plan implements
issue #9855's **PR 1** scope: backfill markers, demote or delete the inverted
files, and land the trivially-small machinery fixes inline. The
dormant-integration CI work (#9855 PR 2) and the non-trivial machinery items are
explicitly out of scope — see Non-Goals.

Every audit claim was re-verified against the worktree at `ceb1c6c1ba` before
planning; findings below cite the measured file, not the brief.

## Research Insights

**Premise Validation (Phase 0.6).** Cited references verified: #9766 is MERGED,
#9771 OPEN (deferred-skill issue), #9763 CLOSED, #9804 MERGED, #9855 OPEN and
carries this work verbatim as its "PR 1" checklist. `test-design-reviewer.md`
§Pyramid & Fast-Feedback Check exists with the layer table + marker semantics
the audit describes. All 11 `apps/web-platform/e2e/*.e2e.ts` files lack a
`pyramid-justified:` comment (`grep -rn pyramid-justified apps/web-platform/e2e`
→ zero). Per-file signal censuses re-measured: `team-membership.e2e.ts` has
`page.`=0 / `browser.`=0 / `request.`=2 plus six empty `test()` stubs under one
`describe.skip`; `smoke.e2e.ts` has `request.`=10 / `page.`=6 (9 of 11 tests are
request-only — the brief's "2 of 3" understated the inversion); `oauth.e2e.ts`
has `request.`=2 / `page.`=22 across 7 tests. The seven env gates
(`SUPABASE_DEV_INTEGRATION` ×5 files, `WORKTREE_LEASE_INTEGRATION_TEST`,
`ACQUIRE_SLOT_WS_INTEGRATION_TEST`, `BYOK_INTEGRATION_TEST`,
`SLOT_TRIGGER_INTEGRATION_TEST`, `WORKSPACE_BINDING_INTEGRATION_TEST`,
`MU1_INTEGRATION`) appear nowhere in `.github/` or `scripts/` — confirmed unset.
Machinery items verified: four pure-unit `*.test.ts` files sit under the
`rls-fuzz/` named-dir (`verdict`, `local-dsn-guard`, `harness-fixture`,
`rls-fuzz-census`); `review.workflow.js:152` carries an unanchored `\.e2e`;
`mu1-integration.test.ts` is hyphen-named and escapes `*.integration.test.*`;
`scripts/suite-durations.tsv` covers scripts-group `*.test.sh` only.

**Property List (Phase 0.6b).**

- P1 — every remaining `apps/web-platform/e2e/*.e2e.ts` file carries a
  `pyramid-justified: <reason>` marker so the next add-case diff cannot FAIL on
  an ambient backlog.
- P2 — coverage exercised at the lowest feasible layer: pure HTTP/middleware
  assertions demoted to vitest, pure-duplication cases deleted, only genuine
  browser-required assertions remain at e2e.
- P3 — no assertion deleted without a named covering test or a recorded
  reason.
- P4 — machinery critiques either fixed inline (small, mechanical) or routed
  to #9771 with the finding text.

**Cut List (Phase 0.6b).** No mechanism the ask proposes is redundant — markers,
deletions, and the two one-line machinery edits buy properties nothing on
`origin/main` covers (the reviewer check *consumes* markers; nothing writes
them).

**Coverage-mapping evidence (gathered inline; no subagents — Devin harness):**

- `team-membership.e2e.ts` flag-OFF 404 logic: covered by
  `test/team-membership-resolver.test.ts`; route existence is structural
  (`app/(dashboard)/dashboard/settings/team/page.tsx`,
  `.../conversation-names/page.tsx` both exist);
  `conversation-names-settings.test.tsx` covers the settings component.
- `smoke.e2e.ts` request assertions: CSP directive content is unit-covered by
  `test/csp.test.ts`; origin allowlist/spoof rejection by
  `lib/auth/resolve-origin.test.ts` + `test/callback.test.ts`; the
  every-exit-carries-CSP + `/health`-is-CSP-free invariant is source-scanned by
  `test/middleware.test.ts` (CSP coverage invariant describe). The genuinely
  un-covered-behavioral slice is *middleware() emits the CSP response header
  with a per-request nonce* — which is directly invocable in vitest (mock
  recipe: `test/middleware.fail-closed.test.ts`).
- `oauth.e2e.ts`: both `/callback` redirect cases are covered by
  `test/app/auth/callback-route-branches.test.ts` (bare `/callback` →
  `/login?error=auth_failed`, invalid-code → login). The signup T&C-gate flow
  is covered by `test/signup-helper-hint.test.tsx`, which renders the real
  `SignupPage` and asserts checkbox→disabled/enabled transitions.
  `test/oauth-buttons.test.tsx` covers component render/disabled/click. The
  only browser-only residue is real-page mount + CSS visibility on `/login`.
- No vitest "booted Next server" harness exists; `*.integration.test.ts` in
  this repo means env-gated real-Supabase suites. Playwright `webServer` is
  the only booted-server substrate, so "demote to integration" here means
  *middleware-level vitest* (invoke `middleware()` with `NextRequest`), which
  is a true demotion — no server boot at all.

## Research Reconciliation — Audit vs. Worktree

| Audit claim | Reality at ceb1c6c1ba | Plan response |
|---|---|---|
| "2 of 3 smoke.e2e.ts tests are CSP-header assertions" | 9 of 11 tests are request-only (2 nonce-header + 5 public-page + 2 auth-redirect); only 2 use `page` | Demote all 9 request-only cases; keep the 2 browser tests |
| "team-membership.e2e.ts: two request.get + 6 describe.skip stubs" | Accurate (6 empty `test()` in one `describe.skip`) | Delete file outright |
| "oauth.e2e.ts: static DOM contract on /login + /signup" | Also holds 2 request-only `/callback` tests + the T&C interaction; all unit-covered | Delete `/callback` + T&C cases; keep+marker the real-page render block |
| env gates "set nowhere in .github/ or scripts/" | Confirmed | Deferred to #9855 PR 2 (CI scope) |

## Decisions (open questions resolved)

- **team-membership.e2e.ts → delete, not convert.** Both live assertions are
  HTTP-status checks already covered at lower layers (resolver unit test +
  middleware redirect coverage); the `describe.skip` block is dead spec text
  whose ACs name living unit/integration suites. A conversion to a booted-server
  integration file would create a one-off harness for two assertions that add
  nothing over existing coverage.
- **smoke.e2e.ts → split at the middleware layer.** Create
  `apps/web-platform/test/middleware.csp.test.ts` (vitest, `middleware()`
  invoked with `NextRequest` + the `@supabase/ssr` mock recipe from
  `middleware.fail-closed.test.ts`) covering: CSP response header present on
  `/login` with `nonce-` + `strict-dynamic` + the hardening directives; nonce
  differs across two invocations; trusted `x-forwarded-host` lands in
  `connect-src`, spoofed does not; `/health` returns without CSP;
  unauthenticated `/dashboard` and `/setup-key` → 307→`/login` (verify against
  existing middleware suites first — delete without re-adding whatever is
  already asserted). Keep the two browser tests (nonce-on-script-tag DOM match,
  zero-CSP-violations console) with a marker.
- **oauth.e2e.ts → demote the duplicated, marker the remainder.** Delete the
  `/callback` describe (covered by `callback-route-branches.test.ts`) and the
  T&C-gate describe (covered by `signup-helper-hint.test.tsx` rendering the
  real page). Keep "OAuth buttons on login page" (real served page, hydration,
  CSS visibility — the only browser-only signal left) with a marker.
- **6a rls-fuzz named-dir → fix inline.** One-sentence clarification in the
  layer table: a `*.test.*` inside a named fixture dir whose SUT is the
  fixture's own modules classifies by framework/API signals.
- **6b `*.test.sh` cost ratchet → declared exception, not new machinery.**
  Add a note to the unit row's cost cell: `*.test.sh` suites may carry real
  subprocess cost; committed weights (#9763/`suite-durations.tsv`) own runtime
  enforcement. New cost signals are #9771 scope.
- **6c hasTests regex → fix inline.** Narrow `\.e2e` to `\.e2e\.[jt]sx?$`
  (terminal extension); `(^|\/)e2e\/` stays — dir-level trigger is deliberately
  broader than the classifier.
- **6d mu1-integration.test.ts → rename** to `mu1.integration.test.ts` so the
  `*.integration.test.*` path signal reaches it. Update the WAIVED entry in
  `plugins/soleur/test/fixture-env-adoption.test.sh:400`, the path comment in
  `apps/web-platform/infra/mu1-cleanup-guard.mjs`, and the file's own header
  comment. The `mu1-integration-*@soleur-test.invalid` synthetic-email prefix
  is a data pattern — it does NOT change.
- **6e weight-manifest boundary → formally stays #9763's scope.** No code.
- **Item 5 (dormant integration) → stays in #9855 as PR 2.** Per-PR vs
  scheduled selection is a cost decision recorded in the issue; not this PR.
- **Feed #9771:** comment on the issue summarizing 6a–6e with the resolution
  taken (fixed inline / declared exception / boundary).

## Files to Edit

- `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` — add marker (ws-injector + `page.route` `**/ws` interception + reducer-via-real-hook)
- `apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts` — add marker (same ws-injector surface; lifecycle-bar DOM signals)
- `apps/web-platform/e2e/cc-soleur-go-security.e2e.ts` — add marker (two `browser.newContext` isolation assertions; injection-render canaries)
- `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts` — add marker (`page.route` hold-and-release timing of soft nav)
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — add marker (real-CSS layout invariant jsdom cannot see)
- `apps/web-platform/e2e/otp-login.e2e.ts` — add marker (route interception of `**/auth/v1/otp*` + real form DOM)
- `apps/web-platform/e2e/smoke.e2e.ts` — delete the 9 request-only tests; add marker covering the 2 remaining browser tests
- `apps/web-platform/e2e/oauth.e2e.ts` — delete `/callback` + T&C-gate describes; add marker covering the real-page button-render block
- `apps/web-platform/e2e/start-fresh-conversations-rail.e2e.ts` — add marker (authenticated project + storageState + app-route mocks)
- `apps/web-platform/e2e/start-fresh-onboarding.e2e.ts` — add marker (authenticated onboarding flow)
- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` — 6a clarification + 6b declared exception
- `plugins/soleur/skills/review/workflows/review.workflow.js` — 6c regex narrowing (`\.e2e` → `\.e2e\.[jt]sx?$`) + the two `hasTests` docstrings
- `plugins/soleur/test/fixture-env-adoption.test.sh` — update WAIVED path for the mu1 rename

## Files to Create

- `apps/web-platform/test/middleware.csp.test.ts` — demoted CSP/redirect assertions from smoke.e2e.ts

## Files to Delete

- `apps/web-platform/e2e/team-membership.e2e.ts`

## Files to Rename

- `apps/web-platform/test/mu1-integration.test.ts` → `apps/web-platform/test/mu1.integration.test.ts` (+ self-references inside it)

## Implementation Phases

### Phase 1 — Marker backfill (10 files)

Add a one-line `// pyramid-justified: <reason>` comment near the top of each
retained e2e file, naming the browser need from the file's own header
comment (measured above — never invent the reason). smoke.e2e.ts and
oauth.e2e.ts get their markers in Phase 2/3 after demotion, naming only what
remains.

### Phase 2 — smoke.e2e.ts split

1. Write `test/middleware.csp.test.ts` (RED first per cq-write-failing-tests —
   the file is new coverage at a lower layer; existing suites cover the rest).
   Verify each candidate assertion against existing middleware suites to avoid
   re-asserting covered ground.
2. Delete the 9 request-only tests from `smoke.e2e.ts` (the two nonce-header
   tests, the five public-page header/status tests, the two auth-redirect
   tests); keep the nonce-on-script-tag and no-CSP-violations page tests.
3. Add the marker naming: CSP nonce reaches rendered `<script>` tags + console
   CSP-violation scan require a real browser DOM.

### Phase 3 — oauth.e2e.ts demotion + team-membership deletion

1. Delete `team-membership.e2e.ts`.
2. In `oauth.e2e.ts` delete the `/callback` describe and the T&C-gate
   describe; keep the login-page button-render describe; add marker (real
   served page + CSS visibility on `/login`).

### Phase 4 — Machinery fixes

1. `test-design-reviewer.md`: 6a + 6b edits (layer-table clarifications only).
2. `review.workflow.js`: narrow `hasTests` regex; sync the two docstrings.
3. `git mv` the mu1 file; update `fixture-env-adoption.test.sh` WAIVED entry,
   `mu1-cleanup-guard.mjs` comment, in-file header comment.
4. Comment on #9771 summarizing 6a–6e dispositions.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "all 11 files under apps/web-platform/e2e/ … lack a `pyramid-justified:` comment. Add a one-line marker per file" | Phase 1 | mapped |
| 2 | "DEMOTE team-membership.e2e.ts … Either delete the file or convert … Deleting stale stubs is preferred" | Phase 3 (delete) | mapped |
| 3 | "DEMOTE smoke.e2e.ts partially … Move header assertions to integration layer; keep the nonce-on-script-tag page.goto test in e2e" | Phase 2 | mapped |
| 4 | "EVALUATE oauth.e2e.ts … Demote what's duplicated, keep browser-only behavior, add pyramid-justified marker" | Phase 3 | mapped |
| 5 | "INTEGRATION DORMANCY … Extend that workflow … it's a PR+CI change" | Non-Goal — stays in #9855 PR 2 | mapped (out) |
| 6 | "MACHINERY FIXES — feed #9771 or fix inline if small" | Phase 4 (6a–6d inline; 6b declared exception; 6e boundary) + #9771 comment | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| middleware.csp.test.ts creation | "Move header assertions to integration layer" | asked |
| team-membership deletion | "Deleting stale stubs is preferred" | asked |
| #9771 disposition comment | "feed #9771" | asked |
| mu1 rename (over pattern-widening) | "decide if the pattern should accept `-integration.test.*` or the file renamed" | asked — decision: rename |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` tests, `plugins/soleur` review machinery
- Planned files: ~15 edited + 1 created + 1 deleted + 1 renamed | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong pyramid verdict on a
  future PR — an ambient `FAIL` on an unrelated diff (marker missing) or a
  silently-misclassified file. Internal tooling surface; no end-user artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — test files and reviewer-machinery text only; no secrets,
  no production code, no data paths.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches only test files,
  a review-agent spec, and a trigger regex — no production behavior, auth,
  data, or payment path changes, so a broken landing costs a wrong review
  verdict at worst.

## Observability

```yaml
liveness_signal:
  what: "marker backfill presence — count of pyramid-justified markers under apps/web-platform/e2e"
  cadence: "per-run (read at review/ship; enforced going forward by the reviewer check itself)"
  alert_target: "test-design-reviewer Pyramid verdict on any future e2e-touching PR"
  configured_in: "plugins/soleur/agents/engineering/review/test-design-reviewer.md §Justification marker"

error_reporting:
  destination: "soleur:review Pyramid verdict block"
  fail_loud: "FAIL verdict on added unmarked e2e test"

failure_modes:
  - mode: "marker missing on a retained e2e file"
    detection: "grep census of pyramid-justified under apps/web-platform/e2e returns < file count"
    alert_route: "PR-time review FAIL"
  - mode: "hasTests regex re-widens to match e2e-utils/e2e.config names"
    detection: "test-pyramid-fixtures.test.sh + a classifier unit row on the new pattern"
    alert_route: "plugin test suite RED"

logs:
  where: "review agent output / plugin test output"
  retention: "session transcript"

discoverability_test:
  command: "grep -rl pyramid-justified apps/web-platform/e2e | wc -l"
  expected_output: "10"
```

## Guard Contract

### Guard 1 — hasTests trigger narrowing

**Property.** `hasTests` fires the test-design reviewer seat on files that are
e2e tests (`*.e2e.ts`) or live under an `e2e/` directory, and NOT on
non-test names carrying an `e2e` infix (`*.e2e-utils.ts`, `*.e2e.config.ts`,
`e2e-oauth-*.test.ts` rely on other alternatives).

**Assembly.** `plugins/soleur/skills/review/workflows/review.workflow.js` →
`MECHANICAL_SURFACE_RE.hasTests`, consumed by `mechanicalSurfaces(files)`
which feeds conditional-seat selection; docstrings at the schema + prompt
lines must restate the same surface.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Path `x/foo.e2e-utils.ts` in diff set | `hasTests` unset by the `\.e2e` alternative (unit row asserts) |
| 2 | Path `x/setup.e2e.config.ts` in diff set | `hasTests` unset by the `\.e2e` alternative |
| 3 | Path `apps/web-platform/e2e/new.e2e.ts` in diff set | `hasTests` still true (dispatch alive) |
| 4 | Regex reduced to never-match (`/$.^/`) | a suite row on a real `*.e2e.ts` path goes RED (vacuity row) |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-file reorganization + reviewer
machinery text. Product/UX mechanical override scanned the Files lists: no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` paths. The
Devin harness subagent restriction (no subagents unless operator-requested)
means the domain-leader fan-out, SpecFlow analyzer, and plan-review panel were
assessed inline rather than spawned — recorded here so the deviation is
visible, not silent.

## GDPR / Compliance

Canonical-regex check against the file lists: no path matches
`apps/web-platform/supabase/migrations/`, `apps/web-platform/lib/auth/`,
`apps/web-platform/server/*auth*`, `apps/web-platform/app/api/*`, or `*.sql`.
Auth-flow test *assertions* are edited, not auth flows themselves. No (a)–(d)
expansion trigger fires. Gate does not apply.

## Acceptance Criteria

- [ ] `grep -rl "pyramid-justified" apps/web-platform/e2e/*.e2e.ts | wc -l` == 10
      (every retained e2e file marked; team-membership deleted)
- [ ] `apps/web-platform/e2e/team-membership.e2e.ts` does not exist; its two
      live assertions are mapped to existing coverage in the PR body
- [ ] `apps/web-platform/e2e/smoke.e2e.ts` contains zero `request.` fixtures;
      the two `page.` tests remain
- [ ] `apps/web-platform/e2e/oauth.e2e.ts` contains zero `request.` fixtures;
      the login-page button-render describe remains with a marker
- [ ] `apps/web-platform/test/middleware.csp.test.ts` exists, is GREEN, and
      each assertion maps to a deleted smoke.e2e.ts case or is recorded as
      already-covered-and-dropped
- [ ] `test-design-reviewer.md` carries the 6a named-dir clarification and the
      6b `*.test.sh` cost-cell exception note
- [ ] `review.workflow.js` `hasTests` does not fire on `foo.e2e-utils.ts` or
      `foo.e2e.config.ts`, still fires on `foo.e2e.ts` and `e2e/…` paths
- [ ] `apps/web-platform/test/mu1.integration.test.ts` exists under the new
      name; `grep -rn "mu1-integration.test" --exclude-dir=node_modules .`
      returns zero outside the synthetic-email prefix
- [ ] `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` and
      `fixture-env-adoption.test.sh` pass
- [ ] A comment on #9771 records the 6a–6e dispositions; #9855's PR-1
      checkboxes are ticked via `Ref #9855` (not `Closes` — PR 2 remains)

## Test Scenarios

- `unit`: `middleware.csp.test.ts` — Given a `/login` NextRequest, when
  `middleware()` runs, then the response CSP header contains `nonce-` and
  `strict-dynamic`; two invocations mint different nonces; trusted
  `x-forwarded-host` lands in `connect-src`, `evil.com` does not; `/health`
  carries no CSP; unauthenticated `/dashboard`/`/setup-key` → 307→`/login`
  (add only what existing suites do not already assert).
- `unit`: hasTests regex — `foo.e2e-utils.ts`, `foo.e2e.config.ts`,
  `foo.e2e.ts`, `e2e/helpers/x.ts` drive the expected verdicts (add a row to
  the pinning suite or assert via `mechanicalSurfaces`).
- `unit`: existing `test-pyramid-fixtures.test.sh` + `fixture-env-adoption.test.sh`
  stay green.
- `e2e`: retained e2e files unchanged behaviorally (marker comments only);
  smoke.e2e.ts keeps its two browser tests. No full battery locally per the
  arc boundary — CI is the e2e executor.

## Non-Goals

- Wiring the dormant env-gated integration suites into CI (#9855 PR 2 —
  needs dev-Supabase Doppler secrets + a per-PR-vs-scheduled decision).
- New cost-signal machinery for `*.test.sh` / promotion logic (#9771).
- Extending `suite-durations.tsv` to e2e/vitest/bun layers (#9763's boundary).
- Widening `*.integration.test.*` to accept `-integration.test.*` (decided:
  rename the file instead).
- Any change to production code, workflows, or infrastructure.

## References

- Issue: #9855 (PR 1 scope), feeds #9771
- Machinery: #9766 / squash `23aa2aaf86`; boundary owners #9763, #9804
- `plugins/soleur/agents/engineering/review/test-design-reviewer.md`
- `apps/web-platform/test/README.md` (integration-flag conventions)
