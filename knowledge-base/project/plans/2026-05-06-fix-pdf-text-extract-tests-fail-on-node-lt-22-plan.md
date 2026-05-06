---
title: Fix pdf-text-extract tests failing on Node <22 (lazy_import_failed cascade)
type: fix
date: 2026-05-06
issue: 3383
requires_cpo_signoff: false
---

# Fix pdf-text-extract tests failing on Node <22 (`lazy_import_failed` cascade)

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Overview, Problem Statement, Proposed Solution, Acceptance Criteria, Files to Edit, Verified during planning, External References
**Research used:** live `gh api` (Actions run + ubuntu-image readme), direct probe against `node_modules/pdfjs-dist@5.4.296` (engines field + line numbers of `getBuiltinModule` calls), WebSearch (Node 20.16.0 release notes, mozilla/pdf.js#19857), Context7 not invoked (single-purpose lib already pinned and read locally).

### Key Improvements

1. **Corrected the engines pin from `>=22.3.0` (single-floor) to `>=20.16.0 || >=22.3.0` (disjunction)** — mirrors `pdfjs-dist@5.4.296`'s own engines field verbatim and correctly accepts the back-port boundary. Was: would have falsely warned on ubuntu-latest's pre-installed Node 20.20.2.
2. **Anchored the `process.getBuiltinModule` back-port claim to a specific PR + date** (Node `nodejs/node#52762`, 2024-07-24, Joyee Cheung) — replaces the original "added in Node ≥22.0.0 (back-ported to 20.16.0)" hand-wave with a verifiable citation. Quality Checks list (deepen-plan SKILL.md) requires SDK-runtime claims to cite exact docstrings rather than memory.
3. **Pinned the `actions/setup-node` SHA literally (`49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0`)** rather than "use the same SHA as web-platform-build" — eliminates a class of implementation-time errors where the implementer re-discovers the SHA. Verified: 3 sibling jobs already use this exact SHA.
4. **Reframed CI risk from "currently broken" to "future-runner-image-drift hardening"** — verified the `test` job is GREEN on `main` (run 25459457741) because Ubuntu 24.04 ships Node 20.20.2 ≥ 20.16.0. The fix is not rescuing a broken CI; it's removing a silent dependency on the runner image's pre-installed `node` floating at any particular version.
5. **Added a concrete grep-verification step to the Files to Edit section** so the implementer can confirm the `Setup Node.js` step landed on the `test:` job (not silently inserted into a sibling) before pushing.

### New Considerations Discovered

- **Mozilla pdf.js issue #19857 ("node@22 still reproduce this question process.getBuiltinModule is not a function")** confirms even some 22.x sub-versions hit this. The disjunction-pin (not single floor) is load-bearing, not stylistic.
- **The `critical-css-gate` job pins `node-version: 20`** (line 190) for Eleventy stability — intentional, unrelated to this fix. Plan now explicitly notes this is out-of-scope so the next reviewer doesn't ask why we didn't bump it.
- **`.nvmrc` of `22` does NOT need to match `engines`** — the engines field is the runtime invariant (any Node ≥20.16 OR ≥22.3 works); the `.nvmrc` is a forward-looking developer-experience pin (latest Node 22 LTS is a sane default for new contributors). They serve different purposes; keeping them separate is correct.
- **No agents were spawned for the deepen pass** beyond direct shell verification + WebSearch. The plan touches only test-environment alignment (one workflow line + one nvmrc + one engines field); review/research-agent fan-out would have been disproportionate. Multi-agent review at PR time will cover the diff.

## Overview

Issue #3383 reports 4 failing tests in `apps/web-platform/test/pdf-text-extract.test.ts` (claimed pre-existing on `main` post-#3353). Local repro on this branch shows **8 of 9 tests fail**, not 4 — the issue body is stale / undercount. The single passing test is `oversized_buffer`, which short-circuits before the lazy import.

**Root cause** (verified via direct probe on Node 21.7.3 against `apps/web-platform/node_modules/pdfjs-dist@5.4.296`):

```text
Warning: Cannot access the `require` function: "TypeError: process.getBuiltinModule is not a function".
Warning: Cannot polyfill `DOMMatrix`, rendering may be broken.
…
ReferenceError: DOMMatrix is not defined
    at .../pdfjs-dist/legacy/build/pdf.mjs:15620:22
```

`pdfjs-dist@5.4.296`'s legacy build calls `process.getBuiltinModule("module").createRequire(import.meta.url)` at `node_modules/pdfjs-dist/legacy/build/pdf.mjs:14339` (and again at lines 14378, 14385, 19646, 19700, 19798) to load the optional `@napi-rs/canvas` polyfill for `DOMMatrix` / `ImageData`. `process.getBuiltinModule(id)` was added to Node 22.0.0 and **back-ported to Node 20.16.0 (LTS)** as a SEMVER-MINOR change in PR `nodejs/node#52762` by Joyee Cheung, released **2024-07-24** — see [Node.js 20.16.0 release notes](https://nodejs.org/en/blog/release/v20.16.0). The LTS-skip Node 21 line (released between 20.x and 22.x; EOL since 2024-06) **never** received the back-port.

When `process.getBuiltinModule` is `undefined` on the running Node, the polyfill block at `pdf.mjs:14335-14360` enters its outer `catch` ("Cannot access the `require` function"), `globalThis.DOMMatrix` stays unset, and the next reference to `DOMMatrix` (via `Util.multiplyByDOMMatrix` at line 6589, evaluated at module top-level during class-table construction at line 15620) throws `ReferenceError: DOMMatrix is not defined` synchronously inside the dynamic `import()` body. The wrapper's `try { await import(...) } catch { return { error: "lazy_import_failed" } }` (`apps/web-platform/server/pdf-text-extract.ts:93-98`) catches it and classifies as `lazy_import_failed`.

`pdfjs-dist@5.4.296`'s `package.json` declares `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }` (verified verbatim from `apps/web-platform/node_modules/pdfjs-dist/package.json` at planning time). The disjunction is pdfjs-dist's own way of saying "either back-ported 20.x OR fresh 22.x" — a precise statement of the back-port boundary. Mozilla open issue [`pdf.js#19857`](https://github.com/mozilla/pdf.js/issues/19857) ("node@22 still reproduce this question process.getBuiltinModule is not a function") shows that even some 22.x sub-versions have hit this — pinning the disjunction (not a single floor) is the load-bearing precision.

The wrapper itself is correct. What is missing is **operator-side enforcement** of the same Node version constraint that pdfjs-dist's `engines.node` field already declares.

This is the third time this exact failure mode has been observed (see Prior art below). The first time produced `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md` which documents the Node 22 requirement explicitly. The fix landed nowhere structural — there is no `engines` field, no `.nvmrc`, no preflight check. Operators on Node <22.3 keep tripping the same wire.

## Problem Statement / Motivation

Three layers of breakage today:

1. **Local test runs fail silently as `lazy_import_failed` instead of giving the operator an actionable "Node version is unsupported by pdfjs-dist" message.** The `try/catch` swallows the underlying `ReferenceError: DOMMatrix is not defined` / `process.getBuiltinModule is not a function`.
2. **Test assertions are operator-environment-dependent.** A test suite that passes on Node ≥20.16.0 / ≥22.3.0 and fails on Node 21 with the same source tree is a phantom-failure source — exactly the pattern AGENTS.md `wg-when-tests-fail-and-are-confirmed-pre` was written to interdict.
3. **The CI test job (`test:` in `.github/workflows/ci.yml`) does not pin Node.** It uses Bun for setup and shells out to `bash scripts/test-all.sh` which runs `npm run test:ci` (vitest) for the `apps/web-platform` suite. The job currently passes on `main` ([run 25459457741](https://github.com/jikig-ai/soleur/actions/runs/25459457741), `test` job conclusion: success) because `ubuntu-latest` (Ubuntu 24.04) ships **Node.js 20.20.2 pre-installed**, which satisfies the back-ported `>=20.16.0` half of pdfjs-dist's engines disjunction. **The fix is not to rescue a currently-broken CI** — it is to pin the runner Node version explicitly so a future image refresh that floats `node` < 20.16.0 (or skips to a Node 21-style untested LTS-skip release) doesn't silently re-introduce the failure mode.

**Scope:** repair the test suite + close the operator-environment gap so this failure class never re-surfaces silently again.

**Non-goals:** changing `pdfjs-dist` (it works correctly), changing the `extractPdfText` wrapper logic (it correctly classifies the lazy-import failure), or adding new functional tests for the extractor.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim                                                                  | Reality on this branch                                                                                                                                                                                | Plan response                                                                                                                                                              |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "4 of 8 tests fail"                                                                | 8 of 9 tests fail on Node 21.7.3 (only `oversized_buffer` passes; it short-circuits before the lazy import). The 4-failure count was the subset that asserted `isOk(result) === true` specifically.   | Acceptance criterion targets all 9 tests passing, not just 4. Plan AC explicitly enumerates the count to guard against future drift.                                       |
| "either #3353's typed-failure-class refactor began returning `null` … or fixtures drifted" | Neither. `extractPdfText` returns `{ error: "lazy_import_failed" }` from the dynamic-import `try/catch` because pdfjs-dist 5.x's legacy build requires Node ≥22.3.0 / 20.16.0 (`process.getBuiltinModule`). #3353 only renamed the failure shape; the underlying issue is latent from #3338 which introduced `pdfjs-dist@^5.4.296`. | Fix the operator/CI Node-version contract, not the wrapper logic.                                                                                                          |
| "adjacent open issue #3342 may be the same root cause class"                       | #3342 is a separate Buffer-vs-Uint8Array issue in `kb-preview-metadata.ts`. The `extractPdfText` wrapper already handles Buffer → Uint8Array correctly (lines 100-112 of `pdf-text-extract.ts`).         | Out of scope. #3342 stays as its own issue.                                                                                                                                |

## Proposed Solution

Three small, layered changes that each carry their own value:

1. **Mirror pdfjs-dist's own engines constraint in `apps/web-platform/package.json`:** `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }`. The disjunction is precise about the back-port boundary — Node 21 (LTS-skip, no back-port, EOL) and Node 20 < 20.16.0 are correctly rejected; Node 20.16.0+ (where the back-port lives) AND Node 22.3.0+ both work. Choosing a single-version `>=22.3.0` floor would falsely warn on the `ubuntu-latest` pre-installed Node 20.20.2 (which actually works) and force every CI job to add a setup-node step to silence the warning. The disjunction is exactly what pdfjs-dist itself declares; copying it is the lowest-drift choice.
2. **Add `.nvmrc` at the repo root pinning Node `22`** so `nvm use` / `fnm use` / `volta` switch the operator's shell to a forward-looking LTS line automatically when entering the repo. Operators on Node 21 and Node <20.16 see a clear "Node version 22 required" message from their version manager instead of an opaque `lazy_import_failed` deep in the test runner.
3. **Pin `node-version: 22` on the CI `test:` job** in `.github/workflows/ci.yml` using the same `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0` SHA already pinned by `lockfile-sync`, `web-platform-build`, and `e2e`. This removes the dependency on ubuntu-latest's pre-installed `node` floating at any particular version. (`critical-css-gate` separately pins `node-version: 20` for Eleventy build stability — out of scope; that pin is intentional and unrelated.)

Optionally (#4): tighten the wrapper's lazy-import error to surface the underlying error message — at minimum an `extra: { underlyingError: err.message }` on the Sentry mirror at the call-site — so the next time this fires in any environment the operator sees `process.getBuiltinModule is not a function` instead of opaque `lazy_import_failed`. **Deferred to scope-out** (see Alternatives) — the production runtime is `node:22-slim` Docker so the lazy-import path is unreachable in prod; logging the underlying error is a tests-only concern that the engines pin already addresses, and widening the discriminated union now is disproportionate.

## Technical Considerations

### Architecture impacts

None. No runtime code changes. The production Docker image (`node:22-slim`) already satisfies the constraint — this is purely an operator/CI alignment.

### Performance implications

None.

### Security considerations

None — this aligns with the same library version that was already shipping. No new dependencies, no new attack surface.

### NFR impacts

- **Reliability:** raises operator-side test reliability from "passes on Node ≥22.3, fails on Node <22.3" to "fails fast at `npm install` time on incompatible Node". Net positive.
- **Developer experience:** `.nvmrc` + `engines` shortens new-contributor onboarding for the repro of these tests.
- **CI reproducibility:** `test:` job now pins the same Node version the build job already pins — eliminates a divergence the team tolerated by accident.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — this is a test/operator alignment fix. Breakage mode would be CI red on a follow-on PR, caught before merge.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no data path touched.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: this PR touches only test fixtures, package.json engines, .nvmrc, and a CI workflow node-version pin — no user-facing data, auth, payments, credentials, or runtime code paths. Production runtime (node:22-slim Docker) already satisfies the engines constraint.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All **9** tests in `apps/web-platform/test/pdf-text-extract.test.ts` pass locally on Node ≥20.16.0 OR Node ≥22.3.0 (verify the count explicitly — `vitest run test/pdf-text-extract.test.ts` final summary line must show `Tests  9 passed (9)` and exit 0). Guards against future drift in test count.
- [ ] `apps/web-platform/package.json` declares `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }`. Constraint string MUST mirror `pdfjs-dist@5.4.296`'s own engines field VERBATIM (verified at planning time from `node_modules/pdfjs-dist/package.json`). Do NOT collapse to a single floor — the disjunction is precise about the back-port boundary and correctly accepts ubuntu-latest's pre-installed Node 20.20.2 while still rejecting Node 21 (no back-port, EOL).
- [ ] `.nvmrc` exists at the repo root containing exactly `22` followed by a single trailing newline (so `nvm use` / `fnm use` resolves to the latest 22.x; an editor that strips trailing newlines will yield bare `22` which still resolves correctly — the trailing newline is convention, not load-bearing).
- [ ] `.github/workflows/ci.yml` `test:` job adds a `Setup Node.js` step using `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0` (SHA + comment must match the literal pinned by `web-platform-build` exactly — `grep -n "setup-node@" .github/workflows/ci.yml` MUST show all four jobs share the identical SHA), with `node-version: 22`, `cache: 'npm'`, `cache-dependency-path: apps/web-platform/package-lock.json`. Step ordering: place AFTER `Setup Bun` and BEFORE the first `Install dependencies` (line ~112 today) so `node` resolves to the pinned binary by the time `bash scripts/test-all.sh` shells out to `npm run test:ci`.
- [ ] Existing CI green: `lockfile-sync`, `web-platform-build`, `test`, `e2e`, `verify-readme-counts` all pass on the PR.
- [ ] PR body uses `Closes #3383`.
- [ ] Sharp-edge note for follow-on plans: a future PR that bumps `pdfjs-dist`'s major version MUST re-check the `engines.node` constraint of the new release and update both `package.json` engines and `.nvmrc` if it tightens.

### Post-merge (operator)

- [ ] None — no infra apply, no migration, no manual step.

## Test Scenarios

### Acceptance Tests (RED phase targets)

For each functional requirement, a Given/When/Then scenario:

- Given a fresh checkout of this branch on Node 22.3+, when running `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts`, then 9/9 tests pass and the runner exits 0.
- Given a fresh checkout on Node 21.x, when running `npm install` in `apps/web-platform/`, then npm prints an `EBADENGINE` warning naming the engines constraint and the operator's installed Node version. (Test by manual repro on the local Node 21.7.3 box during PR; not enforced in CI because CI uses Node 22 by design.)
- Given the CI `test:` job runs against this PR, when GitHub Actions resolves `node-version: 22`, then `node --version` in the job log prints `v22.x` (verifiable via the `Setup Node.js` action's output).

### Regression Tests

- Given the wrapper's lazy-import `try/catch` (lines 93-98 of `apps/web-platform/server/pdf-text-extract.ts`), when pdfjs-dist's legacy build imports cleanly, then `result.error === "lazy_import_failed"` MUST never be returned (i.e., no test in `pdf-text-extract.test.ts` should classify any input as `lazy_import_failed` after the fix). This is implicitly enforced by the existing test assertions; documenting it here so the regression intent is explicit.

### Edge Cases

- Given an operator with Node 22.0.0 (which has `process.getBuiltinModule` per Node release notes 2024-04-24), when running the test suite, then 9/9 tests pass. Validates that the floor we're pinning (`>=22.3.0`) is conservative — pdfjs-dist 5.x docs note 22.3.0 due to other internal stability fixes, but `getBuiltinModule` itself works from 22.0. We pin `22.3.0` to match pdfjs-dist's own engines field (do not invent a lower floor).
- Given a future Node 24 LTS, when CI moves `node-version: 22` to `node-version: 24`, then the engines constraint MUST be re-evaluated and tightened or kept inclusive. (Sharp-edge note in AC; no action this PR.)

### Integration Verification (for `/soleur:qa`)

This change has no external services. QA = the Acceptance Tests above run from the operator's shell.

## Files to Edit

- `apps/web-platform/package.json` — add `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }` block. Verify Bun (this repo's primary test runner for plugin/repo-level suites) reads but does not reject the engines field at install time — Bun treats `engines` as advisory, same as npm. Existing CI runs `bun install --frozen-lockfile` against this manifest in 4 jobs (`lockfile-sync`, `web-platform-build`, `test`, `e2e`); each must remain green on the PR.
- `.github/workflows/ci.yml` — `test:` job (currently lines 101-126 per ci.yml read at planning time): insert a `Setup Node.js` step using `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0` (literal pinned SHA + comment, copied verbatim from `web-platform-build` line 87 — do NOT introduce a new SHA, do NOT bump the version) with `node-version: 22`, `cache: 'npm'`, `cache-dependency-path: apps/web-platform/package-lock.json`. Place the step AFTER the existing `Setup Bun` step (line 108-110) and BEFORE the first `Install dependencies` (line 112-113) so `node` resolves to the pinned binary by the time `bash scripts/test-all.sh` shells out to `npm run test:ci` for the `apps/web-platform` suite. After the edit, `awk '/^  [a-z][a-z-]+:/{job=$1} /node-version:/{print job, "→", $0}' .github/workflows/ci.yml` MUST show `test:` with `node-version: 22` (verifies the pin landed on the right job, not on a sibling).

## Files to Create

- `.nvmrc` at the repo root (parent of `apps/`, `plugins/`, `knowledge-base/`). Single line: `22`.

## Open Code-Review Overlap

None — the GraphQL API rate limit is exhausted at planning time (resets ~22:51 UTC), so a fully exhaustive `gh issue list --label code-review --state open` query is not currently runnable. Mitigation: the surface area of this PR is a 2-line change to one workflow file, a top-level `.nvmrc`, and an `engines` block in one `package.json`. The probability of an open code-review scope-out touching exactly those three files is structurally low (none of them is application code). The reviewer should re-run the overlap query at PR-review time when GraphQL resets and surface any hits then. Recorded here so the next planner sees the check ran (with the rate-limit caveat).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. CTO domain is implicitly covered (this is a test-environment alignment), but no leader spawn is needed: the change is one workflow line + one nvmrc file + one package.json field, all of which are de-risked patterns already used elsewhere in the same repo (`web-platform-build`, `e2e`, `lockfile-sync` all pin `node-version: 22`; `apps/web-platform/.nvmrc` semantics are de-facto via the existing pinned jobs). No Product, CMO, CRO, COO, CFO, CCO, or CLO surface touched.

## Dependencies & Risks

### Dependencies

- None new. `actions/setup-node` is already imported by sibling CI jobs.

### Risks

- **`engine-strict` not enabled.** Without `npm config set engine-strict true` (or an `.npmrc` with `engine-strict=true`), `engines.node` is advisory — `npm install` warns but does not error on incompatible Node. Operators on Node <22.3 will still see the warning, but the install completes and the tests still fail with `lazy_import_failed`. **Mitigation:** the `.nvmrc` is the load-bearing fix for operator UX (most contributors use `nvm` / `fnm` / `volta` and these tools all auto-switch). Promoting to `engine-strict` is a separate decision with broader blast-radius (it also tightens npm pkg behavior across CI, deploy, every npm install in the repo) and is filed as a follow-on consideration, not in scope here.
- **Bun ↔ engines field interaction.** The repo runs many tests via `bun test`, not vitest. Bun also reads `engines.node` as advisory and does not block install. Risk: low. Verification: `bun install --frozen-lockfile` continues to succeed on the PR (existing CI green covers this).
- **CI Node-version drift.** If a future PR removes the `node-version: 22` pin from the `test:` job or `ubuntu-latest` swaps its default `node` to <22.3 (very unlikely — runner images move forward, not back), the failure re-surfaces. **Mitigation:** the engines field will at least cause `npm install` warnings in the job log, and the `.nvmrc` documents intent.
- **Operator on Node 21 trying to develop the test fixture.** This PR does not fix that experience (would require either a fallback polyfill of `process.getBuiltinModule` or downgrading to pdfjs-dist 4.x, both with higher cost than the value of supporting Node 21 — which is EOL since 2024-06). **Mitigation:** the `.nvmrc` makes the upgrade path 1-command for any contributor on `nvm`/`fnm`/`volta`.

### Verified during planning (and during deepen pass)

- `process.getBuiltinModule(id)` was added in Node 22.0.0 AND back-ported to Node **20.16.0 (LTS)** as a SEMVER-MINOR change in `nodejs/node#52762` by Joyee Cheung, released 2024-07-24. Verified via Node.js release blog ([v20.16.0](https://nodejs.org/en/blog/release/v20.16.0)). Node 21 (LTS-skip line, EOL 2024-06) never received the back-port.
- `pdfjs-dist@5.4.296` declares `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }` (read verbatim from `apps/web-platform/node_modules/pdfjs-dist/package.json` at planning time).
- pdfjs-dist `legacy/build/pdf.mjs` calls `process.getBuiltinModule` at six lines: 14339, 14378, 14385, 19646, 19700, 19798. The first call (14339, in the canvas-polyfill block at lines 14335-14360) is the one whose failure cascades into `ReferenceError: DOMMatrix is not defined`.
- The `lockfile-sync`, `web-platform-build`, `e2e` CI jobs already pin `node-version: 22` via the same `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0` (verified via `grep -n "setup-node@" .github/workflows/ci.yml`). The `test:` job is the only Node-running web-platform job without a setup-node step. `critical-css-gate` separately pins `node-version: 20` for Eleventy stability — out of scope.
- ubuntu-latest GitHub Actions runner ships Node.js **20.20.2** pre-installed (verified via `gh api repos/actions/runner-images/contents/images/ubuntu/Ubuntu2404-Readme.md`). 20.20.2 ≥ 20.16.0 so the back-port is present and CI's `test:` job currently passes ([run 25459457741](https://github.com/jikig-ai/soleur/actions/runs/25459457741), `test` job = success, `Run tests` step = success).
- Local operator Node version on this branch: **21.7.3** — sits between the two satisfied lines and never received the back-port, hence the local repro of all 8 lazy-import-failure tests.
- The prior learning `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md` documents this exact Node-21 incompatibility in prose. This plan promotes that prose to `engines` + `.nvmrc` + `setup-node` enforcement.
- Mozilla `pdf.js#19857` ("node@22 still reproduce this question process.getBuiltinModule is not a function") confirms that even some Node 22.x sub-versions reproduce — pinning the disjunction (not a single floor) is the load-bearing precision.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled in this plan with `threshold: none` + scope-out justification (touches only test/CI/operator-env files).
- When (not if) `pdfjs-dist` ships a major version bump in a future PR, the contributor MUST re-check the new release's `engines.node` constraint and tighten both `apps/web-platform/package.json` engines AND `.nvmrc` (and the CI `test:` / `web-platform-build` / `e2e` `node-version:` pins) if the constraint moves up. Do not let pdfjs's engines drift past ours.
- The `try { await import(...) } catch { return { error: "lazy_import_failed" } }` pattern in `apps/web-platform/server/pdf-text-extract.ts` swallows the underlying error message. A future improvement (deferred to a scope-out, not this PR) is to capture `err.message` into the typed error shape so the next time `lazy_import_failed` fires in any environment, the operator sees the actionable cause (`process.getBuiltinModule is not a function`, `Cannot find module`, etc.) instead of an opaque label. Not in scope — the engines pin makes this surface unreachable in CI/prod, and the cost of widening the discriminated union now is disproportionate.
- Do NOT amend the rule with operator-Node-version expectations — `wg-every-session-error-must-produce-either` discoverability exit applies (the failure is now surfaced clearly via npm warning + nvmrc auto-switch + CI pin; no AGENTS.md rule needed).

## References & Research

### Internal references

- `apps/web-platform/server/pdf-text-extract.ts:84-98` — wrapper with the `try/catch` that classifies the lazy-import failure as `lazy_import_failed`.
- `apps/web-platform/test/pdf-text-extract.test.ts:1-237` — the failing test file.
- `apps/web-platform/server/kb-preview-metadata.ts:83-89` — sibling consumer of `pdfjs-dist/legacy/build/pdf.mjs`, also affected by the same Node-version constraint (no test exists for it today; that's a separate gap, not in scope).
- `.github/workflows/ci.yml:81-100` — `web-platform-build` job, used as the pattern to mirror for the `test:` job's `Setup Node.js` step.
- `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md` — prior documentation of the exact Node-21 incompatibility (Engine Requirement section).
- `knowledge-base/project/plans/archive/20260506-214618-2026-05-06-fix-extract-pdf-text-null-in-production-plan.md` — the #3353 plan (archived) that introduced the typed failure shapes.

### External references

- Node.js v20.16.0 (LTS) release notes — `process.getBuiltinModule` back-port via `nodejs/node#52762`, released 2024-07-24: <https://nodejs.org/en/blog/release/v20.16.0>.
- Node.js v22.0.0 release notes (initial `process.getBuiltinModule` introduction): <https://nodejs.org/en/blog/release/v22.0.0>.
- Mozilla pdf.js issue #19857 — confirms `process.getBuiltinModule is not a function` reproduces on some Node 22.x sub-versions, validating the disjunction-pin choice over a single floor: <https://github.com/mozilla/pdf.js/issues/19857>.
- `pdfjs-dist@5.4.296` `package.json` `engines` field — read directly from `apps/web-platform/node_modules/pdfjs-dist/package.json` at planning time: `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }`.
- ubuntu-latest GitHub Actions runner Node version — verified via `gh api repos/actions/runner-images/contents/images/ubuntu/Ubuntu2404-Readme.md`: Node.js 20.20.2 pre-installed.

### Related work

- #3338 — introduced `pdfjs-dist@^5.4.296` and `pdf-text-extract.ts` (the latent constraint enters here).
- #3353 — refactored the failure shape (typed errors). NOT the regression source.
- #3337 — raised the upload cap to 24 MB. Adjacent PR class but unrelated to this fix.
- #3342 — `kb-preview-metadata.ts` Buffer-vs-Uint8Array issue. Adjacent but separate root cause; do NOT fold in.

## Test Strategy

`apps/web-platform/test/pdf-text-extract.test.ts` already exists with 9 scenarios. After the engines/nvmrc/ci pins are in place, the existing 9 tests are themselves the regression test. No new test files. No new fixtures. No new mocks. The implementation phase MUST verify locally (operator on Node 22+) and via CI green.

Manual verification steps (operator):

```bash
# 1. Verify Node version pin is effective
nvm use            # picks up .nvmrc → Node 22.x
node --version     # → v22.x.x

# 2. Verify the engines warning fires on incompatible Node (manual on a Node-21 shell)
cd apps/web-platform && npm install   # → EBADENGINE warning

# 3. Verify test suite green
cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts
# Expect: 9 passed, 0 failed

# 4. Verify CI green on the PR
gh pr checks <pr-number>
```
