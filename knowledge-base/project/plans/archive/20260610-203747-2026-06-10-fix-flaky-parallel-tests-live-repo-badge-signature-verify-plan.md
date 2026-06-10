---
title: "fix: flaky full-suite tests under parallel load (live-repo-badge J5, signature-verify timeouts)"
type: fix
date: 2026-06-10
issue: 5113
lane: cross-domain
brand_survival_threshold: none
---

# fix: flaky full-suite tests under parallel load (live-repo-badge J5, signature-verify timeouts)

Closes #5113.

## Enhancement Summary

**Deepened on:** 2026-06-10
**Sections enhanced:** Hypotheses (Network-Outage Deep-Dive), Implementation Phases (verified API signatures), Observability (5-field schema), Risks (fake-timer edge case)
**Verification performed inline** (pipeline context — no Task fan-out): installed-SDK type-def reads, live `gh` citation checks, repo-wide tunable-semantic audit.

### Key Improvements

1. **All three prescribed API shapes verified against installed versions** (not memory): `vi.waitFor(cb, { timeout })`, `beforeAll(fn, timeout)`, RTL `configure({ asyncUtilTimeout })` — verbatim docstrings + line pins in Research Insights below.
2. **Tunable-semantic audit completed for the global `asyncUtilTimeout` change**: repo-wide grep of `apps/web-platform/test/` found ZERO tests that pin the old 1000 ms default (no `rejects`/`toThrow` on `waitFor`/`findBy`, no `getConfig()` reads, no wait-duration assertions). One new edge case documented (fake-timer interaction, see Risks).
3. **All 7 cited PR/issue numbers verified live** via `gh` (states + titles match narrative claims); the "52 function imports" claim verified exactly via `grep -c`.

### New Considerations Discovered

- **Fake-timer interaction:** 10 component-test files use `vi.useFakeTimers`. DTL's `waitFor` detects sinon-backed fake timers (via `setTimeout.clock`) and advances them up to `asyncUtilTimeout` in fake-time on *not-yet-passing* waits. The bump means failing waits advance up to 10 s of fake time (200 × 50 ms ticks) instead of 1 s — pass/fail semantics unchanged for conditions that never become true, but a condition that becomes true between 1 s and 10 s *fake-time* would flip fail→pass. Audit found no test asserting promptness-within-1s, so this is a more-permissive wait, not a masked assertion. Documented in Risks.
- **Plan-time API-default evidence:** the 1000 ms defaults claimed in H1 are now cited from installed code (`@testing-library/dom/dist/config.js:15` → `asyncUtilTimeout: 1000`; `vitest/dist/index.d.ts:203-204` → `@default 1000ms`), upgrading H1 from "documented default" to "verified-installed default".

Two test files flake under full-suite parallel load (`bash scripts/test-all.sh` / `TEST_GROUP=webplat`) but pass green in isolation and on main CI:

1. `apps/web-platform/test/live-repo-badge.test.tsx` — `LiveRepoBadge — J5 revocation interstitial` cases. Observed twice on 2026-06-10, a *different* case each run ("re-arms the interstitial on a fresh fellBackToSolo transition" and "dismissing the interstitial hides it"). 5/5 green in isolation.
2. `apps/web-platform/test/server/inngest/signature-verify.test.ts` + `signature-verify-dev-mode.test.ts` — 16-second timeouts under parallel import load. 6/6 green in isolation.

Both files were untouched by the PR that observed the flakes (#5098, merged); main CI was green at the time. This is a test-harness reliability fix — no production code changes.

Spec note: `knowledge-base/project/specs/feat-one-shot-5113-flaky-parallel-tests/spec.md` does not exist — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Premise Validation

- Issue #5113 is OPEN with zero `closedByPullRequestsReferences` — premise holds.
- All three cited test files exist at the cited paths (verified via `ls`).
- PR #5098 (the PR that observed the flakes) is MERGED — consistent with "files untouched by the observing PR".
- "16s timeouts" matches `testTimeout: 16_000` in `apps/web-platform/vitest.config.ts` (set by #4128) — the timeouts are vitest per-test timeouts, not network timeouts.
- The "pdf-text-extract precedent" cited by the issue body exists: `apps/web-platform/test/pdf-text-extract.test.ts:135-137` — `beforeAll(async () => { await import("pdfjs-dist/legacy/build/pdf.mjs"); }, 30_000);`.
- No external premises are stale.

## Research Reconciliation — Issue Claims vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Worker-pool contention / ordering-dependent state leak in the component pool (live-repo-badge)" | Cross-file leak vectors are already closed: component project runs `pool: "forks"` + `isolate: true` (vitest.config.ts, per #3817). Within-file, `beforeEach` resets mocks + the coalescing latch, and the never-resolving-fetch test runs last. The remaining mechanism is CPU starvation of the fork: all async waits in the file use **default 1000 ms timeouts** (`vi.waitFor` default 1000 ms; RTL `findBy*` asyncUtilTimeout default 1000 ms), while #4128 documented 2.8 s-isolated tests taking 6-14 s contended in this exact suite. | Fix the 1 s async-wait ceilings, not the (already-fixed) pool. See Hypotheses H1. |
| "cold-start module import cost under parallel load (signature-verify)" | Confirmed. `app/api/inngest/route.ts` imports **52 Inngest function modules** plus the Inngest SDK; the signature-verify pair are the only test files that import the full route graph as a live module (`function-registry-count.test.ts` reads route.ts as *text*; `client-startup.test.ts` imports only `client.ts`). The first `await import("@/app/api/inngest/route")` happens *inside an `it()`* and pays the entire cold-import cost against `testTimeout: 16_000`. The file's own header comment says cold re-loads cost "~5s each under contention" and that the "PR #3985 timeout bump was a stop-gap, not a fix". | Adopt the issue-suggested `beforeAll` import pre-warm (pdf-text-extract precedent). See Hypotheses H2. |
| "consider `beforeAll` import pre-warm or a per-file timeout bump" | Pre-warm precedent verified at `pdf-text-extract.test.ts:135-137`. A bare per-file timeout bump is the previously-rejected stop-gap (per the in-file comment about #3985). | Pre-warm chosen; timeout bump rejected (see Alternatives). |

## Hypotheses

The plan-skill network-outage gate fired on the keyword "timeout" in the feature description. Per the L3→L7 checklist, each network layer must be addressed before service-layer hypotheses:

- **L3 firewall / L4 routing / DNS / L7 service reachability: N/A — no network path exists in either failure.** The live-repo-badge tests stub `fetch` via `vi.stubGlobal` inside happy-dom (no socket is ever opened; `test/setup-dom.ts` additionally installs a fail-loud fetch/WebSocket blockade per #4155). The signature-verify timeouts occur during an in-process ESM `import()` of a local module graph — no remote host, no SSH, no HTTP. The word "timeout" refers to vitest's `testTimeout: 16_000` per-test budget. No `hcloud`/`dig`/`curl` verification is applicable; there is no affected host.

Actual hypotheses (both verified against code, see Reconciliation):

- **H1 (live-repo-badge): default 1000 ms async-wait ceilings under CPU starvation.** The file's waits — `screen.findByTestId(...)` (RTL asyncUtilTimeout, default 1000 ms) and `vi.waitFor(...)` (vitest default 1000 ms) — expire when the forked worker is starved by 470+ sibling test files. Supporting evidence: (a) #4128 measured 2-5× contention multipliers on this suite and raised `testTimeout` to 16 s for exactly this reason, but the *intra-test* wait ceilings were never aligned; (b) a different case flakes each run — the signature of probabilistic starvation, not ordering-dependent state leak; (c) the only async machinery in every flaked case is a 1000 ms-default wait; (d) cross-file vectors are already closed by forks+isolate (#3817).
- **H2 (signature-verify): cold import of the 52-function route graph inside `it()` exceeds `testTimeout: 16_000` under contention.** The first test in each file pays the full module-graph load (Inngest SDK + 52 function modules + their transitive Supabase/Sentry/Octokit imports) against the 16 s test budget. In-file comments already document ~5 s cold loads under moderate contention; full-suite load pushes past 16 s. The dev-mode sibling has a single test, so "the first test" is the whole file.

Falsification path (Phase 0): reproduce under parallel load and confirm the error shape — H1 predicts `vi.waitFor`/`findBy` timeout errors at ~1000 ms (NOT 16 s test timeouts); H2 predicts `Test timed out in 16000ms` on the first test of each signature-verify file. If the observed error shapes differ, stop and re-diagnose before applying fixes.

### Network-Outage Deep-Dive

Layer-by-layer status per `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` (gate fired on the literal keyword "timeout"; deepen-plan Phase 4.5 telemetry emitted):

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | **N/A — no remote host exists.** Both failures are local-process: happy-dom component tests with `vi.stubGlobal("fetch", ...)` stubs, and in-process ESM `import()` of local files. | `test/setup-dom.ts` fail-loud blockade (#4155) rejects any *unmocked* fetch/WebSocket — a real network attempt would fail loudly and deterministically, not flake. |
| L3 DNS / routing | **N/A** — no hostname is ever resolved; the stubbed fetch never reaches a resolver. | `live-repo-badge.test.tsx:25-34` (`vi.stubGlobal("fetch", mockActiveRepo(...))`). |
| L7 TLS / proxy | **N/A** — no TLS handshake occurs in either file. | Same as above. |
| L7 application | **Verified as the actual layer**: vitest per-test budget (`testTimeout: 16_000`) and intra-test wait budgets (1000 ms defaults) — both in-process scheduler/budget phenomena. | `apps/web-platform/vitest.config.ts` (#4128 comment block); installed-default citations in Research Insights. |

No sshd/fail2ban/firewall hypothesis is proposed anywhere in this plan — the L3→L7 ordering requirement is satisfied vacuously (no network path).

## Files to Edit

1. `apps/web-platform/test/server/inngest/signature-verify.test.ts` — add `beforeAll` import pre-warm with explicit 60 s hook timeout; update the header comment to record the pre-warm rationale.
2. `apps/web-platform/test/server/inngest/signature-verify-dev-mode.test.ts` — same pre-warm (each file has its own module cache under `isolate: true`; the pre-warm must exist in both).
3. `apps/web-platform/test/live-repo-badge.test.tsx` — pass explicit `{ timeout: 10_000 }` to the three `vi.waitFor` calls (lines 37, 108, 114).
4. `apps/web-platform/test/setup-dom.ts` — add RTL `configure({ asyncUtilTimeout: 10_000 })` so `findBy*`/`waitFor` defaults align with the #4128 contention philosophy across the whole component project (16 files use `findBy`/`vi.waitFor`).

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200-issue window) contains no issue referencing `live-repo-badge`, `signature-verify`, or `setup-dom` paths (checked 2026-06-10).

## Implementation Phases

### Phase 0 — Reproduce + confirm error shape (best-effort, time-boxed)

1. Baseline isolation check (must be green before any change):
   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx
   cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/signature-verify.test.ts test/server/inngest/signature-verify-dev-mode.test.ts
   ```
   (Runner is vitest invoked in-package — NOT `bun test`; `apps/web-platform/bunfig.toml` sets `pathIgnorePatterns = ["**"]`. Verified against `package.json` `test:ci`: `vitest run`.)
2. Attempt reproduction under parallel load: `cd apps/web-platform && npm run test:ci 2>&1 | tee /tmp/webplat-full-run-1.log` (full unsharded webplat suite, the same invocation `scripts/test-all.sh` uses for the webplat group). Optionally amplify contention by running a parallel CPU load alongside.
3. Record the error shape for any reproduced flake (waitFor-timeout vs 16 s test-timeout) in the PR body. **Reproduction is best-effort, not a gate**: the flakes are probabilistic (2 observations in one day of full-suite runs), the mechanisms are code-verified, and both fixes are strict reliability improvements that cannot mask a real regression (they only lengthen wait budgets for *passing* conditions; failing assertions still fail). If reproduction shows a *different* error shape (e.g., assertion mismatch rather than timeout), STOP and re-diagnose.

### Phase 1 — signature-verify pre-warm (H2)

Add to BOTH `signature-verify.test.ts` and `signature-verify-dev-mode.test.ts`, inside the `describe` (after the file-scope env writes, which run at module scope and therefore still precede the import):

```ts
// Pre-warm the route module graph (Inngest SDK + 52 function modules) so the
// first test doesn't pay the cold-import cost against testTimeout (16s) under
// full-suite contention. Mirrors the pdfjs-dist pre-warm in
// pdf-text-extract.test.ts (#4097 Fix 3). See #5113.
beforeAll(async () => {
  await importRoute();
}, 60_000);
```

- Import `beforeAll` from `vitest` in both files.
- 60 s explicit hook timeout: the route graph is materially larger than pdfjs-dist (which uses 30 s); the hook budget is consumed only on cold start and does not extend any test's runtime.
- Do NOT change `testTimeout`/`hookTimeout` in `vitest.config.ts` — the in-file comment records that the #3985 timeout bump was a stop-gap; the pre-warm is the structural fix.
- Update each file's header comment: the "first lazy `await importRoute`" sentence in `signature-verify-dev-mode.test.ts` (lines 15-16) and the cold-load paragraph in `signature-verify.test.ts` (lines 17-24) should mention the `beforeAll` pre-warm so the comments stay truthful.

### Phase 2 — live-repo-badge async-wait budgets (H1)

1. In `test/setup-dom.ts`, after the existing imports:
   ```ts
   import { configure } from "@testing-library/react";

   // #5113 — align RTL's async-util ceiling (findBy*/waitFor, default 1000ms)
   // with the #4128 contention philosophy (testTimeout 16s): forked workers
   // can be CPU-starved past 1s under full-suite load (473 files). Passing
   // waits are unaffected (they resolve when the condition is met); only
   // genuinely-failing waits get slower (10s vs 1s), same tradeoff as
   // isolate:true ("acceptable for a reliable suite").
   configure({ asyncUtilTimeout: 10_000 });
   ```
   10 s sits under the 16 s testTimeout, leaving headroom for a render plus one wait per test; no component test asserts on waitFor *failure* duration (verified by grep — zero `rejects`-on-waitFor patterns in `test/*.test.tsx`).
2. In `test/live-repo-badge.test.tsx`, add `{ timeout: 10_000 }` to the three `vi.waitFor` calls (`vi.waitFor` does NOT read RTL's config):
   - line 37: `await vi.waitFor(() => { ... }, { timeout: 10_000 });`
   - line 108: `await vi.waitFor(() => expect(regainCommitted).toBe(true), { timeout: 10_000 });`
   - line 114: `await vi.waitFor(() => expect(screen.getByTestId(...)).toBeInTheDocument(), { timeout: 10_000 });`
   The `findByTestId` calls (lines 56, 96, 131) inherit the new global asyncUtilTimeout — no per-call change needed.
3. Do NOT alter the test logic, the coalescing-latch resets, or the body-settle gating — they encode the race fixes from the 2026-06-03 fetch-coalescing learning and are correct.

### Research Insights (verified against installed SDK versions)

**API shapes — verbatim from installed type definitions, not memory:**

- `vi.waitFor` options (vitest, `apps/web-platform/node_modules/vitest/dist/index.d.ts:196-208`):

  ```ts
  interface WaitForOptions {
    /** @description Time in ms between each check callback
     * @default 50ms */
    interval?: number;
    /** @description Time in ms after which the throw a timeout error
     * @default 1000ms */
    timeout?: number;
  }
  declare function waitFor<T>(callback: WaitForCallback<T>, options?: number | WaitForOptions): Promise<T>;
  ```

  Confirms both the `{ timeout: 10_000 }` form prescribed in Phase 2.2 AND the H1 claim that the default is 1000 ms.

- `beforeAll` timeout argument (`apps/web-platform/node_modules/@vitest/runner/dist/tasks.d-DEYaIMIu.d.ts:243`):

  ```ts
  declare function beforeAll<ExtraContext = object>(this: unknown, fn: BeforeAllListener<ExtraContext>, timeout?: number): void;
  ```

  Confirms the `beforeAll(async () => { await importRoute(); }, 60_000)` form prescribed in Phase 1.

- RTL `configure` + `asyncUtilTimeout` (installed `@testing-library/react@16.3.2`):
  - `node_modules/@testing-library/react/types/index.d.ts:24` — `export function configure(configDelta: ConfigFn | Partial<Config>): void`
  - `node_modules/@testing-library/dom/types/config.d.ts:12` — `asyncUtilTimeout: number`
  - `node_modules/@testing-library/dom/dist/config.js:15` — `asyncUtilTimeout: 1000,` (installed default; confirms H1's 1000 ms `findBy*` ceiling claim)

**Tunable-semantic audit (global `asyncUtilTimeout` 1000 → 10_000):** every test file in `apps/web-platform/test/` was swept, not sampled:

- `grep -rE "rejects\.|toThrow" test/*.test.tsx | grep -iE "waitFor|findBy"` → 0 hits (no test asserts a wait *fails*).
- `grep -rn "asyncUtilTimeout|getConfig()" test/` → 0 hits (no test reads or pins the config).
- No wait-duration assertions (`Date.now`/`performance.now` deltas around waits) — the only `Date.now` uses are fixture timestamps.
- 10 files use `vi.useFakeTimers` — see the fake-timer edge case in Risks.

**Citation verification (live `gh` probes, 2026-06-10):** #4128 (CLOSED, "test: pre-existing apps/web-platform suite failures…"), #3817 (CLOSED, "fix: pre-existing apps/web-platform test failures (ECONNREFUSED:3000 + chat-surface family)"), #3985 (MERGED, TR9 PR-1 Inngest cron migration), #4097 (MERGED, "fix(test): stabilize web-platform + plugin test harness"), #2594/#2505 (CLOSED, kb-chat-sidebar/chat-page flake family), #4155 (CLOSED, ECONNREFUSED blockade class). All narrative attributions in this plan match the live titles. The "52 function modules" claim: `grep -c 'from "@/server/inngest/functions/' app/api/inngest/route.ts` → `52` (exact).

**Precedent diff (Phase 4.4 gate):** the pre-warm pattern has one sibling precedent — `apps/web-platform/test/pdf-text-extract.test.ts:135-137`: `beforeAll(async () => { await import("pdfjs-dist/legacy/build/pdf.mjs"); }, 30_000);`. Phase 1 adopts the identical shape (lazy `await import` inside `beforeAll` with explicit timeout); the only divergences are the import target (route graph vs pdfjs) and the budget (60 s vs 30 s, justified by graph size). No other pre-warm precedents exist in the repo.

### Phase 3 — Verification

1. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w ...` — repo root has no `workspaces` field).
2. Isolation re-check: both Phase 0.1 commands green; signature-verify pair total wall-clock should not regress materially (pre-warm moves cost, doesn't add it).
3. Full-suite stability: 3 consecutive green runs of the webplat group, matching the issue's acceptance criterion:
   ```bash
   for i in 1 2 3; do TEST_GROUP=webplat bash scripts/test-all.sh || { echo "RUN $i FAILED"; break; }; done
   ```
   (Run from the worktree root. `TEST_GROUP=webplat` exercises exactly the vitest suite where both flakes live — the bun/scripts shards don't touch these files. If wall-clock budget allows, one of the three runs may be the full `bash scripts/test-all.sh`.)
4. Grep gate: confirm no remaining default-budget `vi.waitFor` in the fixed file: `grep -n "vi.waitFor" apps/web-platform/test/live-repo-badge.test.tsx` — every hit must carry `timeout: 10_000`.

## Acceptance Criteria

### Pre-merge (PR)

1. `grep -c "beforeAll" apps/web-platform/test/server/inngest/signature-verify.test.ts` ≥ 1 AND `grep -c "beforeAll" apps/web-platform/test/server/inngest/signature-verify-dev-mode.test.ts` ≥ 1; both `beforeAll` blocks call `importRoute()` and pass an explicit `60_000` timeout argument.
2. `grep -c "timeout: 10_000" apps/web-platform/test/live-repo-badge.test.tsx` returns `3` (one per `vi.waitFor` call).
3. `grep -c "asyncUtilTimeout" apps/web-platform/test/setup-dom.ts` returns ≥ 1 (the `configure({ asyncUtilTimeout: 10_000 })` call).
4. `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx` → 5/5 pass.
5. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/signature-verify.test.ts test/server/inngest/signature-verify-dev-mode.test.ts` → 6/6 pass (5 cloud-mode tests: export-shape + 4 × 401 paths; 1 dev-mode positive control).
6. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
7. Three consecutive `TEST_GROUP=webplat bash scripts/test-all.sh` runs exit 0 (logged in the PR body with run timestamps; per the issue's acceptance section).
8. No production source files changed: `git diff --name-only origin/main` contains only paths under `apps/web-platform/test/`, `knowledge-base/`, and `plugins/soleur/skills/work/SKILL.md` (compound route-to-definition bullet — workflow documentation, not production code; added post-review).
9. PR body uses `Closes #5113`.

### Post-merge (operator)

None — fully automatable; CI's webplat shards re-exercise both files on every subsequent PR, which is the ongoing flake monitor.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this changes test files and test harness config only. The blast radius is internal: a mis-set timeout could let a *genuinely* failing component test take up to 10 s to report failure (vs 1 s), slowing CI feedback; a broken pre-warm would surface immediately as a red signature-verify suite in CI, never in production.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — no data surfaces, no auth surfaces, no API changes. The signature-verify tests use synthetic `signkey-test-*` fixtures already in-repo (cq-test-fixtures-synthesized-only compliant).
- **Brand-survival threshold:** none — reason: test-reliability-only change; no user-facing artifact, no data path, no deploy-path change. (Diff touches no sensitive path per the preflight Check 6 regex.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-harness/tooling change confined to `apps/web-platform/test/`. Mechanical UI-surface override checked: Files to Edit contains no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` paths (test files only) — Product tier NONE. GDPR gate (Phase 2.7): no regulated-data surface, no LLM/external-API processing, no new distribution surface — skipped. IaC gate (Phase 2.8): no new infrastructure — skipped.

## Observability

Plan Phase 2.9 trigger set does not strictly fire (edits are confined to `apps/web-platform/test/**` — no production code under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`). The 5-field schema is nonetheless declared so deepen-plan Phase 4.7 passes under its broader reading; the observability surface for a test-reliability change IS CI:

```yaml
liveness_signal:
  what: webplat CI shards execute all 4 edited files on every PR touching apps/web-platform
  cadence: every PR + every push to main (ci.yml test-webplat jobs)
  alert_target: red required check blocks merge; operator sees it on the PR
  configured_in: .github/workflows/ci.yml (TEST_GROUP=webplat -> scripts/test-all.sh -> vitest)
error_reporting:
  destination: GitHub Actions check annotations + vitest failure output in the job log
  fail_loud: yes — a flake recurrence fails the required check; no silent fallback path exists
failure_modes:
  - mode: H1 fix insufficient (a wait still starves past 10s under contention)
    detection: vitest reports the waitFor/findBy timeout with file+line in the CI log
    alert_route: red required check on the affected PR; re-file via flaky-test triage (this issue's provenance path)
  - mode: H2 fix insufficient (cold import exceeds 60s beforeAll budget)
    detection: vitest names the beforeAll hook timeout in signature-verify.* — distinct, actionable signature
    alert_route: red required check on the affected PR
  - mode: asyncUtilTimeout bump masks a perpetually-slow genuine failure
    detection: failing component tests report after <=10s per wait, still within testTimeout 16s; failure text unchanged
    alert_route: red required check (latency of failure report rises; pass/fail verdict unchanged)
logs:
  where: GitHub Actions run logs (per-suite timing via TEST_TIMING_LOG in scripts/test-all.sh when set)
  retention: GitHub default (90 days)
discoverability_test:
  command: gh run list --workflow ci.yml --branch main --limit 5 --json conclusion,displayTitle
  expected_output: recent runs with conclusion "success"; any flake recurrence shows as "failure" with the test name in the run log
```

## Test Scenarios

This PR *is* tests; the scenarios are the stability properties:

1. **Cold-start budget (H2):** first signature-verify assertion runs against a warm module cache; the cold import consumes the 60 s `beforeAll` budget instead of the 16 s test budget. Verified by AC5 + AC7.
2. **Starvation budget (H1):** every async wait in live-repo-badge tolerates ≥ 10 s of worker starvation. Verified by AC4 + AC7.
3. **No semantic drift:** all existing assertions unchanged — the J5 re-arm ordering machinery (body-settle gating, latch resets) is untouched; the dev-mode positive control still proves the 401 path is mode-gated. Verified by AC4/AC5 diff review.
4. **No masking:** budgets only extend *waiting for a condition to become true*; a wrong assertion still fails (slower). The signature-verify 401 assertions are status-code equality checks unaffected by timing.

## Risks & Mitigations

- **Global `asyncUtilTimeout` bump slows failure reporting for all component tests** (genuine failures take up to 10 s per failing wait instead of 1 s). Mitigation: passing tests are unaffected; the suite already accepted this exact tradeoff at the vitest level in #4128 ("16s testTimeout") and in the isolate-true comment ("acceptable for a reliable suite"). Verified no test asserts on waitFor-failure timing (grep returned zero).
- **Pre-warm `beforeAll` could itself time out under extreme contention.** Mitigation: explicit 60 s budget (2× the pdfjs precedent's 30 s for a larger graph); if 60 s is ever exceeded the failure message names the hook, which is a clear, actionable signal rather than a flaky first-test timeout.
- **Hypothesis wrong (some other mechanism).** Mitigation: Phase 0 error-shape falsification gate; Phase 3's three consecutive full-group runs are the empirical backstop. If a flake recurs post-merge, the issue re-opens with the new error shape captured.
- **Env-write ordering in signature-verify:** the pre-warm must not import the route before the file-scope `process.env.*` writes. Non-risk by construction: module-scope statements run before any `beforeAll`, and the env writes are module-scope (lines 25-29 / 17-21). The header comments already document this contract; Phase 1 keeps the env writes at module scope.
- **Fake-timer interaction with the global `asyncUtilTimeout` bump** (deepen-pass finding): 10 component-test files use `vi.useFakeTimers`; DTL's `waitFor` detects sinon-backed fake timers via `setTimeout.clock` and advances fake time while polling, bounded by `asyncUtilTimeout`. Post-bump, a *not-yet-passing* wait advances up to 10 s of fake time (200 × 50 ms ticks) instead of 1 s before failing. Pass/fail flips only for a condition that becomes true between 1 s and 10 s fake-time — which is semantically a wait succeeding, not a masked assertion (the repo-wide sweep found zero tests asserting promptness-within-1-second). Mitigation: none needed; noted so a future test that *wants* a tight wait passes an explicit per-call `{ timeout }`.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Per-file `testTimeout` bump (e.g., `describe(name, { timeout: 30_000 })`) for signature-verify | Previously tried as PR #3985's timeout bump; the in-file comment explicitly records it as "a stop-gap, not a fix". It keeps the cold-import cost inside the first test's budget, so the number just ratchets up as the function registry grows (52 modules today, growing ~1/week). |
| `vi.mock` the 52 function modules in signature-verify to shrink the import graph | Defeats the test's intent: the suite asserts the *real* `serve()` registry rejects unsigned POSTs "before any function dispatches"; mocking the registry would also desync from `function-registry-count.test.ts`'s lockstep guards. 52 mock declarations is also unmaintainable. |
| Per-call timeouts only in live-repo-badge (no global `asyncUtilTimeout`) | Leaves the identical 1000 ms ceiling live in the other 15 component files that use `findBy`/`waitFor` — the same class flake recurs file-by-file (kb-chat-sidebar family precedent: #2594 → #2505 → #3817 took three rounds because fixes were per-file). One config line closes the class; the blast radius is failure-reporting latency only. |
| Raise global `testTimeout` beyond 16 s | Doesn't address either mechanism: H1 waits fail at 1 s regardless of testTimeout; H2's cold import belongs in a hook budget, not a test budget. |
| Move signature-verify to a serial/sequential vitest project | Heavy config surface for two files; doesn't fix the cold-import cost, just reduces contention probability. |

No deferred-scope items — all alternatives are rejected outright, not deferred, so no tracking issues are required.

## References

- Issue #5113 (this fix); PR #5098 (flake observation context, merged).
- `apps/web-platform/vitest.config.ts` — #4128 testTimeout rationale; #3817 forks-pool rationale.
- `apps/web-platform/test/pdf-text-extract.test.ts:135-137` — `beforeAll` pre-warm precedent (#4097 Fix 3).
- `knowledge-base/project/learnings/2026-06-03-shared-hook-fetch-coalescing-and-e2e-flake-isolation.md` — J5 re-arm test's body-settle/latch design (do not disturb).
- `knowledge-base/project/learnings/2026-04-06-vitest-module-level-supabase-mock-timing.md`, `2026-04-13-vitest-mock-sharing-and-issue-batching.md` — vitest module-cache behavior background.
- AGENTS.md `cq-test-fixtures-synthesized-only` — signature-verify fixtures remain synthetic.
