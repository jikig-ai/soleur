---
title: "fix(test): 3 pre-existing plugin-test flakes (marketing-content-drift, jsonld-escaping, github-stats-data)"
type: fix
date: 2026-05-20
issue: 4112
branch: feat-one-shot-plugin-test-flakes-4112
lane: single-domain
---

# fix(test): 3 pre-existing plugin-test flakes

Closes #4112

## Overview

`bash scripts/test-all.sh` runs `bun test plugins/soleur/` as one suite
(see `scripts/test-all.sh:157`). Inside that suite three test files
intermittently fail with symptoms surfaced during `/ship` Phase 4 on
PR #4097:

- `plugins/soleur/test/marketing-content-drift.test.ts` —
  `beforeEach/afterEach hook timed out for this test` at the
  default 5000 ms threshold.
- `plugins/soleur/test/jsonld-escaping.test.ts` — same shape at
  ~8682 ms.
- `plugins/soleur/test/github-stats-data.test.ts` — leaves a dangling
  process (bun emits `killed 1 dangling process`) and the test runner
  hangs ~180 s before its hard ceiling kills the suite.

Repro under the exact path the bun shard hits in CI:

```bash
bun test plugins/soleur/test/marketing-content-drift.test.ts \
         plugins/soleur/test/jsonld-escaping.test.ts \
         plugins/soleur/test/github-stats-data.test.ts
```

Observed output (verified 2026-05-20 on
`feat-one-shot-plugin-test-flakes-4112`):

```text
plugins/soleur/test/github-stats-data.test.ts:
[githubStats.js] GitHub API failed, using fallback: network down
killed 1 dangling process

plugins/soleur/test/marketing-content-drift.test.ts:
(fail) (unnamed) [5000.94ms]
  ^ a beforeEach/afterEach hook timed out for this test.
```

### Why this is one bundle (not three)

All three failures share a single root cause class: **two long-running
`beforeAll` hooks (Eleventy build) on the default 5000 ms timeout,
gated by an *unbounded* GitHub API fetch in
`plugins/soleur/docs/_data/github.js`**.

- `marketing-content-drift.test.ts:62-77` runs `npm run docs:build` in
  `beforeAll` with no explicit timeout. The build invokes
  `plugins/soleur/docs/_data/github.js` (the *releases* fetcher —
  distinct from `githubStats.js`) which has **no `AbortController`**
  (`github.js:20`) and no `FETCH_TIMEOUT_MS`. When the workflow is on
  a slow runner or the GitHub Releases endpoint hiccups, the build
  blocks past the 5 s default and bun reports a hook timeout.
- `jsonld-escaping.test.ts:20-33` runs a self-contained Eleventy
  fixture in `beforeAll`. Its fixture config doesn't pull
  `_data/github.js`, but Bun runs all `plugins/soleur/test/*.test.ts`
  in **a single OS process** (per
  `knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md`).
  When a prior test file's unfinished `fetch` is still pending at
  file-handoff, the next file's `Bun.spawnSync` enters bun's
  event-loop in a degraded state and the hook clock ticks while
  spawn metadata is still being reconciled.
- `github-stats-data.test.ts:99-111` is the canonical leak source:
  the `dev-mode falls back to nulls when GitHub API errors` test
  installs `globalThis.fetch = async () => { throw new Error(...) }`
  and calls `githubStats()` which has a `try {Promise.all([fetch(...),
  fetch(...)])} ... finally { clearTimeout(timer); }` (`githubStats.js:30-67`).
  The thrown fetch propagates synchronously through `Promise.all`,
  but the **AbortController's `setTimeout` is the dangling handle bun
  warns about** — `clearTimeout(timer)` runs in `finally`, however the
  test's `afterEach` immediately calls `__resetCache()` and exits
  before bun's event loop has reaped the timer. On the next test
  file's load, bun sees one residual handle and emits
  `killed 1 dangling process`. The full hang then comes from the
  Eleventy `beforeAll` in the *next* file (marketing-content-drift)
  blocking on the unbounded `github.js` fetch.

So the fix is a triplet:

1. **Source fix:** add `AbortController` + `FETCH_TIMEOUT_MS` to
   `plugins/soleur/docs/_data/github.js` (mirror of the same pattern
   already in `githubStats.js:30-67`, `communityStats.js:24-46`).
2. **Test hardening:** raise `beforeAll` timeout to 30 s on both
   Eleventy-spawning tests (`marketing-content-drift.test.ts`,
   `jsonld-escaping.test.ts`) — matches the precedent set in PR #4097
   for `skill-security-scan.test.ts` spawn-based tests.
3. **Dangling-handle fix:** stub `globalThis.fetch` to short-circuit
   `Promise.all` *before* the AbortController timer is armed in the
   "dev-mode fallback" test (and its CI-fail-fast sibling, and the
   401 sibling) — replace
   `globalThis.fetch = async () => { throw new Error(...) }` with a
   form that returns a rejected promise *synchronously* so
   `clearTimeout` runs in the same microtask the rejection settles.

## User-Brand Impact

**If this lands broken, the user experiences:** intermittent red
checks on `bun test plugins/soleur/` in CI — non-user-facing test
infrastructure. The plugin marketplace install path is unaffected;
the Eleventy docs site builds use the same `github.js` codepath but
operator-side build failures degrade to "version: null" via the
existing fallback (`github.js:31-33`).
**If this leaks, the user's [data / workflow / money] is exposed
via:** N/A — no regulated data on the test path; `github.js` reads a
public Releases endpoint with optional `GITHUB_TOKEN`.
**Brand-survival threshold:** none — internal CI hygiene only.

## Research Reconciliation — Spec vs. Codebase

Issue body says marketing-content-drift + jsonld-escaping fail at
`beforeEach/afterEach hook timed out`. Both files use only `beforeAll`
+ `afterAll`. This is a known bun-test quirk: when a `beforeAll`
exceeds the default test timeout, bun's error reporter labels it
"beforeEach/afterEach" generically. Confirmed against bun 1.3.11 on
this worktree.

Issue body also implies github-stats hangs "~180s before being killed
by the runner's hard ceiling". The hang is **not** in github-stats
itself — verified by running it in isolation (`bun test
plugins/soleur/test/github-stats-data.test.ts` exits in 100 ms with
7/7 pass). The hang is in **the next file's `beforeAll`**, which the
issue conflates because `--bail`-less bun reports failures in file
order. The fix targets the root cause (unbounded fetch in
`github.js`) but the test-file diagnosis is plumbed correctly.

| Spec claim                                | Reality                                                              | Plan response                              |
|-------------------------------------------|----------------------------------------------------------------------|--------------------------------------------|
| `beforeEach`/`afterEach` hook timeout     | Both files use `beforeAll`/`afterAll`; bun mislabels the error.      | Raise `beforeAll` timeout; note the quirk. |
| github-stats hangs ~180s                  | github-stats itself exits in 100ms; *next* file's hook hangs.        | Fix dangling timer + unbounded fetch.      |
| Three different root causes               | One shared root cause: unbounded `github.js` fetch + dangling timer. | Single-file source fix + two test guards.  |

## Files to Edit

- `plugins/soleur/docs/_data/github.js` — add `AbortController` +
  `FETCH_TIMEOUT_MS = 5000` mirror of `githubStats.js:30-67`. Wrap the
  existing `fetch(RELEASES_URL, { headers })` in the
  controller/`signal` pattern; add `setTimeout(() => controller.abort(),
  FETCH_TIMEOUT_MS)` and `clearTimeout(timer)` in `finally`. Preserve
  the CI fail-fast branch verbatim. **No new dependencies.**

- `plugins/soleur/test/marketing-content-drift.test.ts` — change
  `beforeAll(async () => { ... })` to `beforeAll(async () => { ... },
  30_000)` (third arg is the per-hook timeout, see bun-test docs).
  Add a code comment citing PR #4097's precedent for the same pattern.

- `plugins/soleur/test/jsonld-escaping.test.ts` — same: third-arg
  `30_000` on `beforeAll`. `afterAll` cleanup stays default (filesystem
  unlink only — sub-second).

- `plugins/soleur/test/github-stats-data.test.ts` — change the three
  error-throwing fetch stubs (lines ~99-111, ~113-122, ~124-135) from

  ```ts
  globalThis.fetch = (async () => { throw new Error("network down"); }) as typeof fetch;
  ```

  to a form that resolves rejected promises synchronously *and* settles
  before `AbortController`'s timer is armed:

  ```ts
  globalThis.fetch = ((..._args: unknown[]) =>
    Promise.reject(new Error("network down"))) as typeof fetch;
  ```

  This guarantees the `Promise.all` settles in the same microtask the
  controller's `setTimeout` is registered, so `finally { clearTimeout
  (timer) }` runs before any test-runner handoff. No semantic change
  to what the test asserts.

## Files to Create

None. (Drift-guard test is folded into the existing `.test.ts` files.)

## Open Code-Review Overlap

Ran (verified 2026-05-20):

```bash
gh issue list --label code-review --state open --json number,title,body \
  --limit 200 > /tmp/open-review-issues.json
for p in plugins/soleur/docs/_data/github.js \
         plugins/soleur/test/marketing-content-drift.test.ts \
         plugins/soleur/test/jsonld-escaping.test.ts \
         plugins/soleur/test/github-stats-data.test.ts; do
  jq -r --arg path "$p" '.[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: **None**. No open code-review scope-outs touch these files.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1: `github.js` has bounded fetch.** `grep -nE
  'AbortController|FETCH_TIMEOUT_MS|signal' plugins/soleur/docs/_data/
  github.js` returns ≥3 matches (controller, timeout constant, signal
  pass-through). The constant is `5000` (ms) to match
  `githubStats.js:6` and `communityStats.js:15`.
- [ ] **AC2: Eleventy-spawning hooks have 30s timeout.** `grep -nE
  '30_000|30000' plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/jsonld-escaping.test.ts` returns ≥1 match per
  file, on a `beforeAll` line.
- [ ] **AC3: Error-throwing fetch stubs use Promise.reject form.**
  `grep -nE 'throw new Error\("network down"\)|throw new Error\("boom"\)'
  plugins/soleur/test/github-stats-data.test.ts` returns **0** matches
  (was 3); `grep -nE 'Promise\.reject\(new Error' plugins/soleur/test/
  github-stats-data.test.ts` returns **≥3** matches.
- [ ] **AC4: Repro command exits 0 with no dangling-process warning
  and no hook timeout.** Run

  ```bash
  bun test plugins/soleur/test/github-stats-data.test.ts \
           plugins/soleur/test/marketing-content-drift.test.ts \
           plugins/soleur/test/jsonld-escaping.test.ts
  ```

  in this order (matches the file-discovery order under
  `plugins/soleur/`). Exit code MUST be 0; stderr MUST NOT contain
  `killed N dangling process` or `beforeEach/afterEach hook timed out`.
- [ ] **AC5: Full plugin suite passes.** `bun test plugins/soleur/`
  exits 0 in ≤120 s. Capture timing in PR body.
- [ ] **AC6: CI bun-shard passes.** `TEST_GROUP=bun bash scripts/
  test-all.sh` exits 0 (this is the exact form CI runs — see
  `scripts/test-all.sh:128-159`).
- [ ] **AC7: No new dependencies.** `git diff --stat package.json
  bun.lockb` returns empty.
- [ ] **AC8: PR body uses `Closes #4112`** (per
  `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

None. The fix is pure code; the next `bun test` run on `main` will
exercise it.

## Test Strategy

No new test files. The drift-guard is the AC4 repro itself: if either
of the two test-side guards (30s timeout, Promise.reject form) is
removed, the same `bun test ...` invocation regresses. If the source
fix in `github.js` is removed but the test guards stay, AC5 still
passes locally (because dev runs have `CI=` unset and fall through to
`version: null`); CI catches it because CI sets `CI=true` and the
existing `if (process.env.CI) throw` branch in `github.js:28-30`
will fire on the next runner hiccup. That branch is unchanged.

Negative-space note: the issue body suggested an alternative fix
("guard with a strict timeout in the test or stub the GitHub API at
the module-init boundary"). This plan declines that alternative
because **the source fix in `github.js` is required regardless** —
the docs build *itself* runs in CI via `npm run docs:build` (Eleventy)
and is the same unbounded-fetch surface that hangs the test. Fixing
only the test would leave the production docs build unprotected, the
exact failure mode `cq-progressive-rendering-for-large-assets` and
the `communityStats.js`/`githubStats.js` precedents are designed to
prevent.

## Risks & Sharp Edges

- **Risk: 30s timeout masks a slower regression.** If a future
  Eleventy plugin or `_data` file pushes the build past 30s, the
  raised threshold delays detection. Mitigation: the CI runner has
  its own outer timeout (job-level `timeout-minutes`), so a regression
  cannot hide indefinitely. Per `wg-when-tests-fail-and-are-confirmed-
  pre`, the threshold matches PR #4097's precedent for spawn-based
  tests — 30s is the project convention, not a one-off.

- **Risk: github.js abort on slow Releases endpoint.** A real
  abort would replicate the existing CI fail-fast contract on
  `githubStats.js:52-53`. The behavior on dev (`CI` unset) is the
  existing `console.warn` + `{ version: null, changelog: { html: "" } }`
  fallback (`github.js:31-33`), unchanged.

- **Sharp Edge: bun-test mislabels `beforeAll` timeout as
  `beforeEach/afterEach`.** Documented inline in both edited test
  files. Future debuggers searching for the error string will land on
  the code comment first.

- **Sharp Edge: `Promise.reject(new Error(...))` vs `async () =>
  { throw }`.** The two are semantically equivalent for await-callers
  but differ in microtask scheduling. The bun-runtime quirk we're
  dodging is that `async () => { throw }` schedules the rejection on
  the *next* microtask, leaving a one-tick window in which
  `AbortController`'s `setTimeout` registers and gets queued for GC
  *after* the test's `afterEach` runs. `Promise.reject(...)` settles
  synchronously, closing the window. If a future bun version changes
  microtask ordering, this fix becomes belt-and-suspenders rather
  than load-bearing.

- **Sharp Edge: `globalThis.fetch` restoration discipline.** The
  test file already captures `ORIGINAL_FETCH` and restores it in
  `afterEach` — see lines 17-26. No change to that mechanism.

- **Sharp Edge per AGENTS.md:** the plan's `## User-Brand Impact`
  section threshold is `none`. `deepen-plan` Phase 4.6 verifies the
  section exists and the threshold is in the allowed enum.

## Domain Review

**Domains relevant:** Engineering only.

Single-domain test-infrastructure fix. CTO/engineering scope.

- **CTO assessment (inline):** Source fix in `github.js` mirrors
  three existing siblings (`githubStats.js`, `communityStats.js`,
  Discord fetch in `communityStats.js`) — pattern is well-established.
  Test fixes use the precedent from PR #4097 (per-test/per-hook
  timeout via third argument). No new architectural surface.

No GDPR-gate trigger (no regulated-data surface; public GitHub
Releases endpoint, optional `GITHUB_TOKEN` reader, no operator data,
no LLM, no cron-on-learnings). Phase 2.7 skipped per its own
silent-skip clause.

No IaC trigger (no new infrastructure; existing Eleventy build path).
Phase 2.8 skipped.

No Product/UX trigger (no user-facing surface). Phase 2.5 Step 2
skipped.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] Verify worktree is `feat-one-shot-plugin-test-flakes-4112`.
- [ ] `bun --version` ≥ 1.3.11.
- [ ] Repro the flake with the AC4 command. Capture the
  `killed 1 dangling process` + `beforeEach/afterEach hook timed out`
  in the work-log; this is the before-state.
- [ ] Read `plugins/soleur/docs/_data/githubStats.js:1-67` and
  `plugins/soleur/docs/_data/communityStats.js:1-50` to confirm the
  mirror pattern.

### Phase 1 — Source fix (RED → GREEN: `github.js`)

- [ ] Edit `plugins/soleur/docs/_data/github.js`:
  - Add `const FETCH_TIMEOUT_MS = 5000;` near the top, with the
    comment block copied from `githubStats.js:4-5`.
  - Inside the function, before the existing `try { const res =
    await fetch(...) }`:
    - `const controller = new AbortController();`
    - `const timer = setTimeout(() => controller.abort(),
      FETCH_TIMEOUT_MS);`
  - Pass `{ headers, signal: controller.signal }` to `fetch`.
  - Wrap the existing `try { ... } catch { ... }` with a `finally
    { clearTimeout(timer); }`.
- [ ] Run `npm run docs:build` — must exit 0 (the same as before).

### Phase 2 — Test hardening (`marketing-content-drift.test.ts`)

- [ ] Change `beforeAll(async () => { ... });` to `beforeAll(async
  () => { ... }, 30_000);` with a code comment citing PR #4097's
  precedent.
- [ ] Run `bun test plugins/soleur/test/marketing-content-drift.test.ts`
  — must exit 0.

### Phase 3 — Test hardening (`jsonld-escaping.test.ts`)

- [ ] Same change: third-arg `30_000` on `beforeAll`. Same comment.
- [ ] Run `bun test plugins/soleur/test/jsonld-escaping.test.ts`
  — must exit 0.

### Phase 4 — Dangling-timer fix (`github-stats-data.test.ts`)

- [ ] Rewrite the three error-throwing fetch stubs to
  `Promise.reject(new Error(...))` form. Preserve the error messages
  verbatim (`"network down"`, `"boom"`, `"Bad credentials"` /
  HTTP 401 response — the 401 stub is already non-throwing, leave
  it alone).
- [ ] Run `bun test plugins/soleur/test/github-stats-data.test.ts`
  — must exit 0, no `killed N dangling process` on stderr.

### Phase 5 — Integration

- [ ] Run AC4 (`bun test` over the three files in file-discovery
  order). Verify exit 0, no warnings.
- [ ] Run AC5 (`bun test plugins/soleur/`) — full plugin suite.
- [ ] Run AC6 (`TEST_GROUP=bun bash scripts/test-all.sh`) — CI bun
  shard. Capture the timing log.

### Phase 6 — Commit + push + PR

- [ ] One commit: `fix(test): bound github.js fetch + raise eleventy
  beforeAll timeout + reject-via-promise (Closes #4112)`.
- [ ] PR body: AC checklist + before/after repro output + the
  one-paragraph root-cause summary from this plan's Overview.

## CLI-verification

- `bun test <file>` third-arg per-hook timeout: verified against
  `plugins/soleur/test/skill-security-scan.test.ts` (PR #4097
  precedent) — same `30_000` literal pattern.
- `AbortController` + `setTimeout` + `clearTimeout` pattern:
  verified against `plugins/soleur/docs/_data/githubStats.js:30-67`
  and `plugins/soleur/docs/_data/communityStats.js:24-46`. The
  edit is a verbatim port; no novel API.
- `Promise.reject(new Error(...))` semantic: standard ECMAScript;
  no version-pinning needed.

## Research Insights

- **PR #4097** established the project convention for hook timeouts
  (third-arg `30_000` on `beforeAll`/`beforeEach`/`afterEach`) and
  closed the worker-pool flake class.
- **`knowledge-base/project/learnings/test-failures/2026-04-18-bun-
  test-env-var-leak-across-files-single-process.md`** documents the
  single-OS-process bun-test mechanic, which is why a dangling timer
  in one file can poison the next file's `beforeAll`.
- **`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-
  sensitivity.md`** explains why `scripts/test-all.sh` runs `bun
  test plugins/soleur/` as one shard.
- **Constitution `cq-abort-signal-timeout-vs-fake-timers`**
  (referenced in `githubStats.js:5` comment) is the canonical
  reference for the manual `AbortController` + `setTimeout` pattern.
  This plan applies the same pattern to `github.js`.
