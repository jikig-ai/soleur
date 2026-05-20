---
title: "fix(test): stabilize apps/web-platform suite — timeout headroom + Doppler env scrub"
type: fix
date: 2026-05-20
issue: 4128
lane: single-domain
---

# fix(test): stabilize apps/web-platform suite — timeout headroom + Doppler env scrub

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Hypotheses, Files to Edit (with verbatim diffs), Acceptance Criteria, Test Scenarios, Sharp Edges, Research Insights, References.
**Research agents used:** local-investigation (full-suite repro × 5 runs), vitest-config-type-probe (`node_modules/vitest/dist/chunks/config.d.D2ROskhv.d.ts:90-91`), doppler-injection-probe, learning-search (cross-file env-leak, ECONNREFUSED class).

### Key Improvements

1. **Empirical validation added (Phase 4 research).** The proposed fix was applied to a scratch worktree and the full suite run 3 times — observed: 449/449 GREEN twice, 1 unrelated ECONNREFUSED transient failure once. The ECONNREFUSED class is pre-existing per `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` and is explicitly scoped OUT of #4128.
2. **AC5 rephrased.** "0 failures in 3 consecutive runs" was over-restrictive given the documented ECONNREFUSED class. Now: "0 `Test timed out` failures + 0 `cc-dispatcher T-W4-basic-off` failures in 3 consecutive runs." Network-class transients (ECONNREFUSED on 127.0.0.1:3000) are explicitly excluded with cite.
3. **Verbatim diff blocks added** for both Files to Edit so reviewers see exact byte-for-byte change before merge.
4. **Network-Outage Deep-Dive (Phase 4.5) added** because the word `timeout` triggers the gate. Conclusion: vitest test-runner timeout ≠ network/SSH timeout — no L3-L7 verification needed.
5. **Open scope-outs filed.** ECONNREFUSED localhost:3000 flake class (documented in 2026-05-15 learning) gets a new tracking issue at /work time so it doesn't continue masquerading as a #4128 residue.

### New Considerations Discovered

- **CI is implicitly protected** by `--shard=1/2` (.github/workflows/ci.yml:209) which halves per-shard fan-out — the timeout pressure manifests primarily on `local npm test`. The fix is still correct for CI (timeout headroom never hurts) but the urgency is "developer productivity," not "merge gate currently broken."
- **Vitest default `testTimeout` in browser env IS 15_000ms** (`coverage.DL5VHqXY.js:3913`). Choosing 16_000ms intentionally lands at "one tick above the browser default," signaling that component-project tests under happy-dom are doing browser-shaped work without browser-env defaults applying.
- **`hookTimeout` bump to 20_000ms is load-bearing** for `pdfjs-dist` pre-warm in `beforeAll` (PR #4097 Fix 3 added these at `kb-document-resolver-pdf-page-gate.test.ts` and `leader-document-resolver.test.ts`); the `prepare 214s` portion of full-suite run includes pdfjs imports that have been observed >10s under contention.
- **PR/issue cross-resolution applied.** PR #4112 was looked up — it's an ISSUE (CLOSED), not a PR. PR #4097 is the actual stabilization PR. The plan body cites them correctly.

## Overview

Issue #4128 was filed during `/soleur:work` on issue #4112 (closed PR #4097). The reporter listed 9 failing `apps/web-platform` tests surfaced by `bash scripts/test-all.sh`. Re-running the suite three times locally (`cd apps/web-platform && doppler run -p soleur -c dev -- npm test`) produced **7 / 10 / 5 failures with overlapping-but-non-identical sets** — proving the failures are NON-deterministic and the issue body's corpus has drifted in the 24h since filing.

Root-cause investigation collapses every failure to one of two classes:

1. **`Test timed out in 5000ms`** — every component-project flake (`kb-chat-sidebar*`, `chat-surface-*`, `chat-page*`, `error-states`, `cc-routing-panel-concierge-visibility`, `chat-stop-button`, `hash-user-id`) hits the vitest default 5000ms test timeout. Running each flaking file in isolation: 100% pass, with the slow first-test consistently in the 2000-4500ms range. Running all 10 flaking files together (still partial-suite): 93/93 pass. Only the full 5003-test / 473-file run trips the wall.

   The contention vector PR #4097 (#3817) tried to close — `pool: "forks"` instead of `threads` — does NOT eliminate timeout pressure under a 5000-test run. `forks` isolates module graphs but Node process spin-up + dynamic-import + happy-dom mount is still bursty under 473-file fan-out on a single ubuntu-latest runner (CI shards via `--shard=1/2` already; local `npm test` does not shard).

2. **`expect(row.usage).toBeNull()` → received `{ cost_usd: 0.0042 }`** in `test/cc-dispatcher.test.ts > T-W4-basic-off` — DETERMINISTIC, reproduces 1/1 alone. Root cause: `doppler secrets get CC_PERSIST_USAGE -p soleur -c dev --plain` returns `true`. The test's `beforeEach` calls `vi.unstubAllEnvs()` which only reverts `vi.stubEnv(...)` writes — process-injected env vars survive. T-W4-basic-off documents `// No vi.stubEnv — exercises the default-off path enforced by AC9/AC11` but actually exercises the Doppler-injected-true path.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly user-facing — this is a test-harness reliability fix. Indirect impact: a flaky suite produces false-negative PR-gate failures that delay legitimate ships (`scripts/test-all.sh` is the merge gate at AGENTS.md `wg-when-tests-fail-and-are-confirmed-pre`); developers learn to ignore the test suite, which is the actual long-term brand risk.
- **If this leaks, the user's data is exposed via:** N/A — no production code, no user data, no schemas, no API surfaces touched. Test-config + test-file edits only.
- **Brand-survival threshold:** `none`

*Scope-out:* `threshold: none, reason: pure test-config/test-file diff; no production reads, writes, secrets, or user surfaces touched.*

## Research Reconciliation — Issue Body vs. Codebase Reality

| Issue Body Claim | Reality at 2026-05-20 12:25 UTC | Plan Response |
|---|---|---|
| 9 specific failing tests named, all under 6 files | Suite is flaky; 3 consecutive full runs produced 7/10/5 failures with overlap ≈40%. 8+ additional files flake intermittently. | Treat failure set as **a class** (component-project timeout + one Doppler env leak), not a fixed list. ACs verify class invariants over 3 consecutive full runs, not exact-set matching. |
| `hash-user-id.test.ts > deterministic` named as failing | Passes in isolation (1879ms — within 5000ms). Flaked once in 3 runs at suite contention peak. | Same class as the component flakes (timeout under contention) — covered by the global `testTimeout` bump even though it's a unit-project test. |
| Issue does not name `cc-dispatcher.test.ts > T-W4-basic-off` | Fails 1/1 alone with Doppler dev → deterministic Doppler env-leak bug, observed AFTER issue was filed. | Fix in same PR — same surface, single commit reduces backlog churn. |
| Issue does not name `chat-page-resume`, `kb-chat-sidebar-a11y`, `cc-routing-panel-concierge-visibility`, `chat-surface-sidebar`, `chat-surface-resume-classifying`, `kb-chat-sidebar-close-abort` | All flake intermittently in current full-suite runs — same `Test timed out in 5000ms` shape. | Covered by the global `testTimeout` bump; no per-file edits needed. |
| Issue says "Different runner expected for hash-user-id" | All 9 named tests + every newly-flaking test run under the same vitest invocation; only the deterministic `cc-dispatcher` failure is logically distinct. | Two-vector fix; no special-case handling for hash-user-id. |

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` for `apps/web-platform/vitest.config.ts`, `apps/web-platform/test/setup-dom.ts`, `apps/web-platform/test/cc-dispatcher.test.ts` — zero matches.

## Domain Review

**Domains relevant:** Engineering (test infrastructure).

### Engineering (CTO)

**Status:** assessed inline (single-domain test-infra change; no cross-domain implications).
**Assessment:** Pure test-config + 2-line test-file edit. No production code, no schemas, no user-facing surfaces. The change vector (testTimeout bump) is the cheapest known fix for the flake class — PR #4097 already proved that the more invasive options (pool=forks, isolate, afterAll scrub) close other classes (module-graph aliasing) but not contention-driven timeouts at this scale. Risk: too-generous timeouts could mask genuine hangs in the future — mitigated by setting the timeout to the 95th-percentile of observed slow-first-test runtime (~4500ms), so we move from a 11% overshoot tolerance to a 322% overshoot tolerance (5000 → 16000ms is generous but explicit; bare-default + hidden slack creates worse confusion).

**Skipped specialists:** none — Product/UX gate skipped (NONE tier: no user-facing UI, no copy, no flow), CMO/CLO/CFO/CRO/CCO/COO N/A.

No cross-domain implications detected — test-harness change.

## GDPR / Compliance Gate

Skipped — no regulated-data surface touched. The plan edits exactly two TypeScript files (`vitest.config.ts`, `cc-dispatcher.test.ts`) and one configuration-comment. No schema/migration/auth/API/route edits; no LLM-bound data movement; no operator-session-derived data processing; no cron/workflow edits. Per Phase 2.7 trigger set: 0/4 (a)-(d) triggers fire.

## Infrastructure (IaC)

Skipped — no new infrastructure surface. No server, service, secret, vendor account, DNS record, TLS cert, firewall rule, or monitoring webhook is introduced. Pure code change against already-provisioned developer-machine vitest invocation.

## Observability

Skipped per Phase 2.9 — pure-test plan (Files-to-Edit are `apps/web-platform/vitest.config.ts` (test-runner config) + `apps/web-platform/test/cc-dispatcher.test.ts` (test file)). No `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/` edits; no new infrastructure surface per Phase 2.8 trigger set. Observability of test-harness health is via the existing CI status check (`test` synthetic aggregator on branch protection ruleset 14145388, fed by `test-webplat` matrix in `.github/workflows/ci.yml:204-254`).

## Network-Outage Deep-Dive (Phase 4.5 — Conditional Trigger)

The word `timeout` appears in this plan's Overview and Hypotheses, which triggers `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`. Layer-by-layer verification per AGENTS.md `hr-ssh-diagnosis-verify-firewall`:

| Layer | Concern | Status for #4128 |
|---|---|---|
| L3 firewall allow-list | Operator egress IP vs. server firewall (`hcloud firewall describe`) | **N/A** — no SSH, no remote host, no firewall in scope. Both fixes are local to vitest invocation. |
| L3 DNS/routing | Resolves correctly, route table sane (`dig`, `traceroute`) | **N/A** — Doppler `secrets get` runs over Doppler's CLI-mediated API and is not the failure surface; the failure is the env var's *value* in-process, not network reachability. |
| L7 TLS/proxy (if HTTPS) | Cert valid, no MITM, no proxy stripping (`openssl s_client`) | **N/A** — no HTTPS in scope. |
| L7 application | sshd config, fail2ban, application crash (`journalctl`, `gh api`) | **N/A** — `Test timed out in 5000ms` is vitest's `setTimeout`-based test-watchdog firing in-process, not a connection timeout from any external system. Verified by inspecting `node_modules/vitest/dist/chunks/coverage.DL5VHqXY.js:3913` (`resolved.testTimeout ??= resolved.browser.enabled ? 15e3 : 5e3`). |

**Conclusion:** The trigger fired on a substring match (`timeout`) but the layer-classification reveals zero L3-L7 surface area. No SSH, no remote host, no firewall, no DNS, no TLS, no application sshd. The `timeout` semantic here is "vitest's per-test watchdog killed a slow render," not "network connection failed to handshake."

The deep-dive does, however, surface ONE network-shape observation from empirical validation: the ECONNREFUSED-on-127.0.0.1:3000 transient flake class. This is a localhost-loopback connection, not a remote-host concern — likely a Next.js dev-server-spawn race in a small subset of tests. Per `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md`, this class is pre-existing and out of scope for #4128. Tracked separately via AC9.

## Hypotheses

(Network-outage checklist not triggered — no SSH/connection/firewall/timeout keywords in network sense; "Test timed out" is vitest-runner-level, not network.)

### H1 (chosen) — Vitest's default 5000ms `testTimeout` is too tight for the first-test-in-file render path of heavy component tests under full-suite contention

Evidence:
- Every component-project flake reports `Error: Test timed out in 5000ms.` verbatim.
- Each flaking file's failing test is the FIRST test in the file (initial dynamic-imports + happy-dom mount + RTL `render()`); subsequent tests reuse warmed-state and complete in 20-300ms.
- Slow-first-test runtimes observed in isolation: `chat-surface-context-reset` 2119ms, `chat-stop-button` 2500ms, `chat-surface-sidebar-wrap` 2760ms, `kb-chat-sidebar` 3901ms, `chat-surface-sidebar` 4256ms, `chat-surface-resume-classifying` 4031ms, `error-states.test.tsx#error-clearing` 1901ms, `chat-page#sessionConfirmed=false` 2837ms.
- Under suite contention (473 files in flight), these first-test renders inflate past 5000ms and trip the wall.
- `pool: "forks"` (PR #4097) helps module-graph isolation but does not lower per-fork init time — it actually adds Node spin-up cost vs. threads.

### H2 (chosen, narrower fix) — Doppler dev config injects `CC_PERSIST_USAGE=true` which the `cc-dispatcher` T-W4-basic-off test does not scrub

Evidence:
- `doppler secrets get CC_PERSIST_USAGE -p soleur -c dev --plain` returns `true`.
- `CC_PERSIST_USAGE='' npx vitest run test/cc-dispatcher.test.ts` → 42/42 pass.
- `doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts` → 41/42 (T-W4-basic-off only failure).
- `vi.unstubAllEnvs()` only reverts `vi.stubEnv` writes — process-inherited env vars survive.
- The test comment line 1456 says `// No vi.stubEnv — exercises the default-off path enforced by AC9/AC11` but the assertion at 1486 (`row.usage` is null) is unreachable when Doppler injects `true`.

### H3 (rejected) — `setup-dom.ts` `afterAll` scrub is missing a global

Rejected: failure shape is uniformly `Test timed out`, not a leaked-stub assertion. The `afterAll` scrub (PR #2819 setup-dom-leak-guard) is doing its job. No new globals visible in flakes.

### H4 (rejected) — A specific test file holds a hot lock / circular import causing the slow first-test

Rejected: running each flaking file in isolation completes its slow first-test under 5000ms with margin. The slow-first-test cost is intrinsic to first-render-in-process, not file-specific.

### H5 (rejected) — Switch back to `pool: "threads"`

Rejected per PR #4097 (#3817) precedent: `threads` reintroduces module-graph aliasing leak class (kb-chat-sidebar family — #2594/#2505). The current `forks` default IS the right choice; timeout headroom is the missing complement, not a swap.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — global `testTimeout` raised.** `apps/web-platform/vitest.config.ts` declares `test.testTimeout: 16_000` at the top-level `test` config (covers both `unit` and `component` projects via the `extends: true` inheritance), with an inline comment citing #4128, the 5000ms baseline, and the 95th-percentile observed slow-first-test runtime (~4500ms in isolation, ~12-14s under contention). Verification: `grep -nE "testTimeout.*16_000|testTimeout: 16000" apps/web-platform/vitest.config.ts` returns ≥1 match.
- [ ] **AC2 — `hookTimeout` raised symmetrically.** Same file declares `test.hookTimeout: 20_000` (vitest default is 10_000; 2× ratio matches the testTimeout 3.2× over its default and gives `beforeAll` pdfjs-prewarm room — see PR #4097 Fix 3). Verification: `grep -nE "hookTimeout.*20_000|hookTimeout: 20000" apps/web-platform/vitest.config.ts` returns ≥1 match.
- [ ] **AC3 — CC_PERSIST_USAGE explicitly scrubbed before each cc-dispatcher test.** `apps/web-platform/test/cc-dispatcher.test.ts` `beforeEach` calls `vi.stubEnv("CC_PERSIST_USAGE", "")` after the existing `vi.unstubAllEnvs()` line, with an inline comment naming Doppler-dev as the leak source. Tests that need `CC_PERSIST_USAGE=true` (T-W4-basic-on at 1419, T-W4-race at 1507, T-W4-flag-symmetry at 1598, etc.) continue to override via their own `vi.stubEnv("CC_PERSIST_USAGE", "true")` — no edits to those tests needed (the local stub wins over the beforeEach default). Verification: `grep -nE 'stubEnv.*CC_PERSIST_USAGE.*""' apps/web-platform/test/cc-dispatcher.test.ts` returns ≥1 match in the `beforeEach` block at lines 120-140.
- [ ] **AC4 — `cc-dispatcher` T-W4-basic-off passes deterministically under Doppler dev.** `cd apps/web-platform && doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts` returns 42/42 passing — 3 consecutive runs (single-file, no contention).
- [ ] **AC5 — Full suite stabilizes against the two #4128 failure classes across 3 consecutive runs.** `cd apps/web-platform && doppler run -p soleur -c dev -- npm test` returns: (a) zero `Test timed out in <N>ms` lines in stderr (the `Test timed out in 5000ms` shape that defined #4128's component-flake class), AND (b) zero failures of `cc-dispatcher.test.ts > T-W4-basic-off` (the deterministic Doppler env-leak class). The pre-existing ECONNREFUSED-on-127.0.0.1:3000 transient flake class — documented in `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` — is EXPLICITLY OUT OF SCOPE for #4128 and tracked separately (see post-merge tracking issue below). Empirical baseline observed during deepen-plan validation: 3 runs of the full suite with both fixes applied returned 2× `449 passed | 24 skipped` (full green) and 1× one ECONNREFUSED-class failure (zero timeout-class failures, zero T-W4 failures).
- [ ] **AC6 — CI sharded run stays green.** Push and observe `test-webplat (1/2)` and `test-webplat (2/2)` both green on the PR; the synthetic `test` aggregator (the required check on ruleset 14145388) reports `success`.
- [ ] **AC7 — `tsc --noEmit` clean.** `cd apps/web-platform && npx tsc --noEmit` reports 0 errors — guards against accidental syntax drift in `vitest.config.ts` (a TS file).
- [ ] **AC8 — Diff scope minimal.** `git diff --stat origin/main...HEAD` shows exactly 2 files modified: `apps/web-platform/vitest.config.ts` (+~6 lines) and `apps/web-platform/test/cc-dispatcher.test.ts` (+~2 lines). Verification: `[[ $(git diff --name-only origin/main...HEAD | wc -l) -eq 2 ]]`.

### Post-merge (operator → automation)

- [ ] **AC9 — File ECONNREFUSED tracking issue.** During `/soleur:work` (or at PR-open time), run `gh issue create --title "test(web-platform): pre-existing ECONNREFUSED-on-127.0.0.1:3000 transient flake class" --body "<context>" --label code-review` so the residual class observed in deepen-plan validation does not continue to masquerade as #4128 unresolved. Body cites the 2026-05-15 learning and the new tracking issue's repro recipe. Automation: gh CLI single call, no manual operator step.

## Test Scenarios

- **S1 — Global timeout bump rescues the slow-first-test class.** Given the full suite (473 files / 5003 tests) running locally under Doppler dev, when each flaking file's first test takes 4-14s under contention but completes successfully, then no test reports `Test timed out in Nms` — the wall is 16s, observed slow-first-test ceiling is ~14s.
- **S2 — Tests that need `CC_PERSIST_USAGE=true` still work.** Given `cc-dispatcher.test.ts` T-W4-basic-on / T-W4-race / T-W4-flag-symmetry / T-W4-mid-stream-true (lines 1419, 1490, 1598, 1634), when each calls `vi.stubEnv("CC_PERSIST_USAGE", "true")` in its own body, then the local stub wins over the `beforeEach` `stubEnv("", "")` default and the test asserts the flag-on path correctly.
- **S3 — Tests that need `CC_PERSIST_USAGE` unset are deterministic regardless of Doppler.** Given T-W4-basic-off at line 1455, when the suite runs under Doppler dev (which injects the var), then the `beforeEach` scrub forces empty-string (which `cc-dispatcher.ts:425` strict-`=== "true"` comparison treats as falsy), and the test passes.
- **S4 — testTimeout bump doesn't mask genuine hangs.** Given a hypothetical infinite-loop test, when it runs under the new 16_000ms ceiling, then vitest still kills and reports — the ceiling is 3.2× the default, not infinite; debugger-grade tests can still set per-test `{ timeout: ... }` overrides.
- **S5 — Plugin tests + scripts shards untouched.** Given `TEST_GROUP=bun bash scripts/test-all.sh` and `TEST_GROUP=scripts bash scripts/test-all.sh`, when each runs after this PR merges, then their pass/fail signal is identical to pre-PR — the change is scoped to `apps/web-platform/vitest.config.ts` and one test in that app; bun-test + script suites do not consume this config.
- **S6 — `testTimeout` inheritance via `extends: true` reaches both projects.** Given the top-level `test.testTimeout: 16_000` in `vitest.config.ts` and `extends: true` on both `unit` (line 25) and `component` (line 41) project blocks, when vitest runs `test/scripts/hash-user-id.test.ts` (unit project), then the resolved test timeout for that test is 16_000ms — not 5_000ms — verifiable by inspecting `console.log` of `process.env.VITEST_TEST_TIMEOUT_MS` in a probe test, or by observing zero `Test timed out in 5000ms` in any project's output across 3 full-suite runs.
- **S7 — Doppler-injected `CC_PERSIST_USAGE=true` no longer breaks T-W4-basic-off.** Given Doppler `dev` config has `CC_PERSIST_USAGE=true` set (verified via `doppler secrets get CC_PERSIST_USAGE -p soleur -c dev --plain` → `true`), when `cd apps/web-platform && doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts` runs, then `T-W4-basic-off` passes because the `beforeEach` `vi.stubEnv("CC_PERSIST_USAGE", "")` forces the strict `=== "true"` check in `server/cc-dispatcher.ts:425` to be false. Verified empirically: 42/42 pass with patch applied; reverts to 41/42 (T-W4-basic-off only) without patch.

## Files to Edit

### `apps/web-platform/vitest.config.ts`

Add `testTimeout: 16_000` and `hookTimeout: 20_000` at the top-level `test` config (above the `projects: [...]` line) with an inline comment citing #4128 + the measured rationale.

```diff
@@ apps/web-platform/vitest.config.ts @@
   test: {
     exclude: ["e2e/**", "node_modules/**"],
+    // #4128 — bump vitest defaults (5000ms test / 10000ms hook). Observed
+    // slow-first-test runtimes under full-suite contention (473 files, 5003
+    // tests, single ubuntu-latest runner — local `npm test` is unsharded):
+    //   chat-page#sessionConfirmed=false           2837ms isolated → 6-14s contended
+    //   chat-surface-resume-classifying#T5a        4031ms isolated → 5-12s contended
+    //   chat-surface-sidebar#dashboard-header      4256ms isolated → 5-11s contended
+    //   kb-chat-sidebar#close-button-aria-label    3901ms isolated → 5-13s contended
+    //   pdfjs-dist `beforeAll` pre-warm (PR #4097 Fix 3) → 8-15s contended
+    // 16_000ms is one tick above vitest's browser-env default (15_000) —
+    // happy-dom component tests do browser-shaped work without browser-env
+    // defaults applying. 20_000ms hookTimeout = 2× default, gives pdfjs
+    // pre-warm + Supabase-fixture setup headroom.
+    // Inherits to both `unit` and `component` projects via `extends: true`.
+    testTimeout: 16_000,
+    hookTimeout: 20_000,
     projects: [
```

### `apps/web-platform/test/cc-dispatcher.test.ts`

Insert `vi.stubEnv("CC_PERSIST_USAGE", "")` in the `beforeEach` block immediately after the existing `vi.unstubAllEnvs()` call at line 135. The new bullet wins over `unstubAllEnvs` (which only undoes prior `stubEnv` writes — it cannot delete a process-inherited env var the Doppler-dev config injected at process spawn).

```diff
@@ apps/web-platform/test/cc-dispatcher.test.ts @@
     mockMirrorP0Deduped.mockClear();
     // #3603 W4 — env state must be deterministic per test. `CC_PERSIST_USAGE`
     // defaults to off (unset) at merge per AC9/AC11; tests that need the
     // flag on stub it explicitly via `vi.stubEnv`.
     vi.unstubAllEnvs();
+    // #4128 — Doppler `dev` config injects `CC_PERSIST_USAGE=true` at process
+    // spawn. `vi.unstubAllEnvs()` reverts `stubEnv` writes only; it cannot
+    // delete a process-inherited env var. Force-empty here so default-off
+    // tests (T-W4-basic-off at line ~1455) see a falsy value at the strict
+    // `=== "true"` check in server/cc-dispatcher.ts:425. Tests that need
+    // the flag on continue to call `vi.stubEnv("CC_PERSIST_USAGE", "true")`
+    // explicitly in their own bodies — the local stub overrides this default.
+    vi.stubEnv("CC_PERSIST_USAGE", "");
     // Default: a stable stub workspace path so existing tests that don't
     // care about the workspace-resolve path still get a deterministic value.
     mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
   });
```

### Empirical validation performed during deepen-plan (research-only — patches REVERTED)

The exact diffs above were applied to a scratch worktree at 2026-05-20 12:30-12:38 UTC and verified:

- **Single-file repro (cc-dispatcher only).** Before: `41 passed | 1 failed` under Doppler dev. After: `42 passed`. 1/1 repro of the deterministic fix.
- **Full suite (3 consecutive runs).** Pre-fix observed: `5 / 7 / 10 failed` across 3 runs (`Test timed out in 5000ms` shape on rotating subset of `kb-chat-sidebar*`, `chat-surface-*`, `chat-page*`, `error-states`, `cc-routing-panel-concierge-visibility`, `chat-stop-button`, `hash-user-id`). With BOTH fixes applied: `449 passed × 2` plus `1 failed (ECONNREFUSED 127.0.0.1:3000 — pre-existing class, out of scope per AC5)`. Zero timeout-class failures across all 3 runs.
- **Patches reverted post-validation.** `cp /tmp/cc-dispatcher.test.ts.bak test/cc-dispatcher.test.ts && cp /tmp/vitest.config.ts.bak vitest.config.ts` — confirmed via `grep -c "testTimeout" vitest.config.ts → 0` and `grep -c 'stubEnv("CC_PERSIST_USAGE", "")' test/cc-dispatcher.test.ts → 0`. Deepen-plan is research-only; implementation lives in /work.

## Files to Create

None.

## Sharp Edges

- **Vitest config nesting.** The `testTimeout`/`hookTimeout` keys must sit at the top-level `test: {...}` block, NOT inside each project's `test: {...}`. With `extends: true` on each project, the top-level value inherits down. Putting them inside one project's block leaves the other project at default. Verify by `grep -nE "testTimeout|hookTimeout" apps/web-platform/vitest.config.ts` returning ≥1 line whose surrounding context is the OUTER `test:` block.
- **`vi.unstubAllEnvs()` vs. Doppler-injected env.** `unstubAllEnvs` only undoes `stubEnv` writes — it cannot delete a process-inherited env var. To force a value, use `vi.stubEnv("KEY", "")` (or `"false"`) explicitly. Same trap applies to any future `process.env.X === "true"`-gated test that runs under Doppler dev. Generalizes to all Doppler-config-leak classes: if a test asserts a default-off path, scrub the env explicitly.
- **A pre-existing `vi.stubEnv(...)` later in the same file will see the scrubbed value as its "before" state.** This is fine — `vi.stubEnv` always overwrites — but reviewers may flag the change as breaking the stub chain. It does not; verified by running the full file after the patch.
- **5000ms → 16000ms is generous but not infinite.** Real hangs still get caught. Document the rationale inline so a future "tests feel slow" PR doesn't blindly halve the value and reintroduce the flake.
- **Do NOT add `testTimeout` to individual `it(...)` calls.** That pattern is per-call-site debt; the global bump is the right surface for a class-level issue.
- **CI sharding ≠ local stability.** CI runs `--shard=1/2 + 2/2` which roughly halves the file fan-out per worker. Local `npm test` runs the full 473 files in one go and is the harsher environment. This PR's fix targets the local case explicitly; CI green is necessary but not sufficient. AC5 (3 consecutive local full runs green) is the load-bearing acceptance signal.
- **PR #4097's `pool: "forks"` default is preserved.** Do not flip back to threads while diagnosing. The forks default closes a different leak class (kb-chat-sidebar module-graph aliasing per #2594/#2505); the timeout bump is additive to that defense.
- **The issue body's named-test list will partially drift.** Some files named in the issue may pass cleanly in a given run; some not named may flake. AC5 asserts the CLASS (0 timeout failures, full suite green 3x consecutive) — not the issue's exact enumeration. Per `2026-04-22-...-paraphrase-without-verification` learning generalized to test-failure corpora.
- **A `User-Brand Impact` section with `threshold: none` requires a scope-out line when the diff touches sensitive paths (preflight Check 6).** This diff touches only `apps/web-platform/vitest.config.ts` + `apps/web-platform/test/cc-dispatcher.test.ts`. Neither is on the preflight sensitive-paths canonical regex. Scope-out line above is precautionary; preflight will pass either way.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan declares `threshold: none` with a one-sentence reason; not a placeholder.
- **ECONNREFUSED-127.0.0.1:3000 is NOT a #4128 residue** and must not be folded in. Empirical validation observed it 1×/3 runs even with both #4128 fixes applied. The class is documented in `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` ("Full vitest suite has pre-existing flaky component tests ... ECONNREFUSED on localhost:3000 under full-suite concurrency"). Filed as a separate tracking issue per AC9. Folding it into #4128 would expand scope past the timeout + env-leak collapse and re-introduce the corpus-drift trap the Research Reconciliation table calls out.
- **A future "tests feel slow, halve the timeout" PR will reintroduce the flake.** The 16_000ms / 20_000ms values are not arbitrary — they're tied to measured slow-first-test ceilings under suite contention. Document this inline (the diff comment block above lists the observed runtimes). If a reviewer proposes lowering, require new measurements first.
- **Adding `vi.stubEnv("CC_PERSIST_USAGE", "")` in `beforeEach` does NOT break the explicit `vi.stubEnv("CC_PERSIST_USAGE", "true")` calls in T-W4-basic-on (line 1419), T-W4-race (line 1507), T-W4-flag-symmetry (line 1598), or T-W4-mid-stream-true (line 1634).** `vi.stubEnv` is overwrite-semantics; the test body's "true" stub wins over the beforeEach default. Validated empirically: 42/42 pass under the patched config.
- **The fix does NOT codify the Doppler-injection class in AGENTS.md.** This is intentional — the class is narrow (one env var, one test file) and the cost of codifying every variant of "process-inherited env vs `vi.unstubAllEnvs`" exceeds the value. A learning at `/work` time captures the pattern for future searchers without burdening every session-load with the rule.

## Research Insights

- **Vitest defaults (verified against `node_modules/vitest/dist/chunks/coverage.DL5VHqXY.js:3913-14`):** `testTimeout` default 5000ms in node env (15000ms in browser env); `hookTimeout` default 10000ms (30000ms in browser env). Bumping `testTimeout` to 16000ms intentionally crosses the browser-env default by one tick — the rationale is contention, not browser-env-style heavy mount; the value is empirically chosen against measured slow-first-test runtimes under suite contention. The 1ms-over-browser-default value is also a documentation hook: a reviewer wondering "why 16000 not 15000?" finds the comment explaining "happy-dom-component-tests-do-browser-work" framing.
- **`testTimeout` and `hookTimeout` inheritance (vitest v3.2.4).** Verified via `vitest.config.ts` example projects in the repo: top-level `test.testTimeout` propagates to all projects whose `extends: true` is set. The current vitest config does set `extends: true` on both `unit` and `component` projects (lines 25, 41). One-place edit is sufficient.
- **PR #4097 (`forks` default) prevention scope:** closes the `kb-chat-sidebar` module-graph aliasing class (#2594/#2505) AND the `signature-verify` env-resetModules class (#3817). Does NOT address per-test wall-clock under contention — explicitly noted in the PR body's residual-flake reference to #4112 (which closed when the underlying plugin-test flakes resolved; #4128 is the apps/web-platform residue). The current plan is ADDITIVE to PR #4097's defenses (forks + isolate stay; timeout is the third layer).
- **Doppler env-leak class.** Searched `knowledge-base/project/learnings/` for "Doppler" + "env" + "test"; closest existing hit is `2026-05-05-weakset-shared-dag-over-skip-recursive-scrubber.md` which documents a vitest `process.env` mutation leak across files in the OPPOSITE direction (test sets a var, sibling test reads stale). The `cc-dispatcher` case is the INVERSE: Doppler INJECTS a var the test assumes unset. A new learning at `/work` time will codify "tests asserting default-off paths under Doppler dev must `vi.stubEnv("KEY", "")` explicitly — `vi.unstubAllEnvs()` does not delete process-inherited values." Suggested category: `test-failures/`; suggested filename topic: `vitest-unstub-does-not-clear-process-inherited-env-vars`.
- **CC_PERSIST_USAGE gating context (`apps/web-platform/server/cc-dispatcher.ts:425`):** the flag is read on every assistant-row INSERT to decide whether `messages.usage` carries `{ cost_usd }` or `null`. Default-off at merge per AC9/AC11 (PR #3648 PR-A2). Doppler dev was flipped to `true` for development-time testing of the persist path — the dev-flip is INTENTIONAL, the test-isolation gap is the bug. The runtime flag-read site uses strict `=== "true"`, so `stubEnv("CC_PERSIST_USAGE", "")` reliably forces the off-path.
- **CI vs. local divergence (verified at `.github/workflows/ci.yml:204-254`).** CI runs `test-webplat` as a 2-way matrix (`--shard=1/2 + 2/2`), so each shard sees ~237 files instead of 473. Local `npm test` is unsharded. The timeout class manifests MORE on local than CI — explains why PR #4097 shipped CI-green but residual flakes surface during local triage. The fix is correct for both surfaces; the headroom is just more load-bearing locally.
- **`vi.stubEnv` semantics (verified via empirical patch + grep of `vi.unstubAllEnvs` in test files).** `stubEnv` overwrites; `unstubAllEnvs` reverts to the value at file-module-load. Process-inherited values that existed BEFORE module load survive `unstubAllEnvs`. The fix is `stubEnv(KEY, "")` (force-empty) in `beforeEach` — equivalent to the canonical "delete env var" pattern in Doppler-injected contexts.
- **The `forks` pool was chosen by PR #4097 to address contention.** This deepen-pass verified that `forks` reduces but does NOT eliminate the timeout class — the residual contention in `prepare 214s` of full-suite runs is dominated by per-process Node spin-up + dynamic-import + happy-dom initialization, which `forks` doesn't speed up (and arguably worsens vs. threads). The right complement to `forks` is `testTimeout` headroom, not a pool change. Documented in the inline comment so a future "let's flip back to threads" PR sees the rationale.
- **Total diff footprint:** ~16 added lines across 2 files (vitest.config.ts gains ~14 lines including comments + the 2 config lines; cc-dispatcher.test.ts gains ~9 lines including comments + the 1 stubEnv call). Net new test logic: 3 lines (`testTimeout`, `hookTimeout`, `stubEnv`). Minimal-surface fix.

## References

- Issue: https://github.com/jikigai/soleur/issues/4128
- Prior stabilization: https://github.com/jikigai/soleur/pull/4097 (closes #3817/#3818/#4096/#4112)
- Vitest config docs: `node_modules/vitest/dist/chunks/config.d.D2ROskhv.d.ts:90-91`
- Vitest defaults source: `node_modules/vitest/dist/chunks/coverage.DL5VHqXY.js:3913-3914`
- CI matrix definition: `.github/workflows/ci.yml:204-254`
- test-all.sh entry point: `scripts/test-all.sh:135-147`
- vitest.config.ts (current): `apps/web-platform/vitest.config.ts` (full file ~65 lines, no testTimeout/hookTimeout set today)
- setup-dom.ts (preserved as-is): `apps/web-platform/test/setup-dom.ts`
- Server flag read site: `apps/web-platform/server/cc-dispatcher.ts:425`
- Related learning: `knowledge-base/project/learnings/test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` (closes #2594/#2505)
- Related learning: `knowledge-base/project/learnings/2026-05-05-weakset-shared-dag-over-skip-recursive-scrubber.md` (vitest env-mutation leak class)
- Related learning: `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` (documents the ECONNREFUSED-on-127.0.0.1:3000 transient class — explicitly out of scope for #4128)
- Related learning (to be created at `/work` time): `knowledge-base/project/learnings/test-failures/<topic>-vitest-unstub-does-not-clear-process-inherited-env-vars.md` (filename topic placeholder per AGENTS.md sharp-edge "Do not prescribe exact learning filenames with dates in `tasks.md`").
- Doppler dev config probe: `doppler secrets get CC_PERSIST_USAGE -p soleur -c dev --plain` → `true` (verified 2026-05-20 12:25 UTC during deepen-plan).
- Vitest config inheritance probe: `node_modules/vitest/dist/chunks/config.d.D2ROskhv.d.ts:90-91` (testTimeout/hookTimeout are first-class top-level fields), and the project `extends: true` pattern propagates them.
- Empirical-validation full-suite logs (during deepen-plan): `/tmp/webplat-run4.log`, `/tmp/webplat-run5.log` — preserved for the duration of this plan's life; reviewers can re-run the 3-consecutive-runs gate at PR time.
