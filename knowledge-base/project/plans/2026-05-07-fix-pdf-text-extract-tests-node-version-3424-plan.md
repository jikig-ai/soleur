---
issue: 3424
type: fix
classification: test-environment
requires_cpo_signoff: false
related_prs:
  - 3338  # introduced extractPdfText + lazy_import_failed branch (verified via git log -p apps/web-platform/server/pdf-text-extract.ts; merged 2026-05-06T18:17:06Z)
  - 3353  # cap-alignment fix (verified merged 2026-05-06T19:56:21Z; touched constants only, NOT the lazy-import path)
  - 3384  # added read_failed to PdfExtractErrorClass union (verified merged 2026-05-06T22:24:09Z; did NOT touch the lazy-import path)
  - 3421  # /ship phase that surfaced this issue (verified merged 2026-05-07T09:35:02Z; PR diff did not touch any PDF code)
---

# Fix: 8 pre-existing pdf-text-extract test failures (lazy_import_failed) — #3424

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** 6 (Strategy decision, Acceptance criteria, Implementation Phases, Risks, Test Scenarios, Sharp Edges)
**Verification artifacts gathered live (not from memory):**

- `apps/web-platform/node_modules/pdfjs-dist/package.json` engines field: `">=20.16.0 || >=22.3.0"` (verified — matches the 2026-04-18 learning's claim).
- `apps/web-platform/node_modules/pdfjs-dist/legacy/build/pdf.mjs` line 5465: `return globalThis.process.getBuiltinModule(name);` (verified — confirms the import-time crash mechanism).
- Vitest reporter shape under `throw new Error(...)` in `beforeAll`: empirically observed via probe — produces "Failed Suites 1" with a SINGLE error message, all `it()` cases reported as skipped (not 8 assertion failures).
- Vitest reporter shape under `describe.skipIf(true)` with a `console.warn` diagnostic: empirically observed via probe — produces "Test Files 1 skipped (1)" with a stderr warning line, no red.
- `git log -p apps/web-platform/server/pdf-text-extract.ts`: lazy-import branch was introduced in #3338's first commit and is unchanged by #3353 and #3384 (PR-number citation reconciliation per `cq-pr-number-citation-reconciliation` quality check).
- PR merge timestamps verified live via `gh pr view --json mergedAt`.

### Key Improvements

1. **Strategy decision sharpened — `describe.skipIf` over throw.** Both modes were empirically verified against vitest's reporter. The skipIf shape has the same operator-pedagogy property (the diagnostic names the exact remediation) but matches the codebase's existing skip-with-diagnostic precedent (`byok.integration.test.ts`, `mu1-integration.test.ts`) — adopting a foreign throw-in-`beforeAll` pattern would cost grep-discoverability for future maintainers. The throw mode's only advantage was "louder", but the diagnostic line is identical either way. **Decision flipped to skipIf** with a `console.error` line at module load (so it lands in the operator's terminal regardless of vitest reporter quietness).
2. **Anti-vacuous-pass guard added to the skipIf branch.** The skipIf model has one risk the throw model doesn't: a CI runner that mistakenly lands on Node 21 would silently skip the suite and ship green. To close this gap, the guard reads the existing `CI` environment variable (set by GitHub Actions, GitLab, etc.) and switches to throw mode in CI even when skipIf would fire locally. CI's contract is "fail loud on environmental drift"; dev's contract is "skip with diagnostic so I can keep working". This bifurcation matches `mu1-integration.test.ts`'s pattern (skip in dev, fail with explanatory comment in CI).
3. **30s timeout sentinel placement reconfirmed.** The `MAX_PAGES` 600-page case is the slowest legitimate case (~600 ms on Node 22 today, but 6 seconds isn't impossible if pdfjs's per-page cost grows). The 16 MB Hypothesis A case takes ~2.5s and already carries `{ timeout: 15_000 }` — the suite's existing timeout pattern is per-case, not file-wide. 30s on the MAX_PAGES case is the right placement.
4. **Test-side diagnostic mirrors the production extractor's failure-class taxonomy.** The diagnostic line names `lazy_import_failed` explicitly so an operator who greps the diagnostic ("nvm use 22") can also grep the production failure mode and find the same string in `pdf-text-extract.ts:117`. Cross-grep discoverability is the cheap win.
5. **No production extractor change.** Reconfirmed via `git log -p`: the lazy-import branch is unchanged across the cascade chain. The plan's strategy (C) explicitly avoids contorting the extractor.
6. **Follow-up issue scope tightened.** The 2026-04-18 learning prescribed three-layer enforcement; only `.nvmrc` + CI pinning shipped. The Phase 0-of-`/work` Node-version preflight is the missing layer. Spec'd as a follow-up issue with concrete labels (`domain/engineering`, `priority/p3-low`, `type/chore`) verified against `gh label list`.

### New Considerations Discovered

- **Vitest's reporter behavior:** under `throw` in `beforeAll`, vitest reports the file as failed BUT counts all individual `it()` cases as "skipped" — so the issue body's 8-failure count is technically only a reporter artifact, not 8 assertion-level errors. The fix moves both the throw model AND the skipIf model from "8 red lines" to "1 line". This is a strict UX improvement either way.
- **Operator vs. CI bifurcation:** the `CI` env-var split is the load-bearing nuance. Without it, a misconfigured CI runner would ship green silently — exactly the vacuous-pass class the strategy decision rejects.
- **The Phase 2 shared-setup option was dropped.** The single-file inline guard is simpler and the YAGNI rationale holds — no second test file currently exercises a real pdfjs-dist-class lazy import. Phase 2 remains documented but downgraded from "optional" to "explicit non-goal" so a reviewer doesn't propose extracting it preemptively.

## Overview

`apps/web-platform/test/pdf-text-extract.test.ts` reports 8/9 tests failing locally because the lazy `import("pdfjs-dist/legacy/build/pdf.mjs")` throws at module init when run on Node `<` 22.3 / `<` 20.16. `pdfjs-dist@5.4.296` calls `process.getBuiltinModule(...)` in its DOMMatrix/ImageData polyfill fallback; that builtin was added in Node 22.3 and back-ported to 20.16. On any older operator Node (e.g., a developer running v21.7.3) the import rejects, the extractor's catch returns `{ error: "lazy_import_failed" }`, and every test that asserts `["corrupted", "parse_error"]` or `isOk(result)` fails.

CI runs Node 22 (`.github/workflows/ci.yml`) and the suite passes there; the failure is exclusively an operator-environment drift. The 2026-04-18 learning (`pdfjs-metadata-on-node-without-canvas.md`) documented this exact failure mode and prescribed three-layer enforcement (`engines` + `.nvmrc` + `setup-node`). The repo currently has `.nvmrc=22` and CI pinning, but no precommit/skill-level guard prevents an operator on Node 21 from running this test in their working tree and consuming a debug round on a known-environmental red.

## Strategy decision

The issue body offers a binary: (A) fix the extractor to surface `lazy_import_failed` when unreachable, or (B) update tests to match what the extractor produces (`corrupted`/`parse_error`).

**Reject both.** Both A and B lie about the system state:

- (A) would require synthesizing an unreachable lazy-import path the production code never hits; the extractor's `lazy_import_failed` branch is exercised in production today (it fired for a real Sentry event during the #3338 cascade) and tests must not contort to make a real failure mode disappear.
- (B) would let the test suite pass on Node 21 with a green that asserts the wrong shape — the moment the operator upgrades to Node 22 the assertion `["corrupted", "parse_error"]` would still be correct, but the test would no longer catch a regression where the extractor (correctly) returns `parse_error` because it would also accept `lazy_import_failed`. Widening the `expect(...).toContain` set to swallow an environmental fault is a vacuous pass — exactly the failure mode `cq-test-fixtures-synthesized-only`'s sibling rules try to prevent.

**Adopted strategy (C):** Keep the assertions exactly as they are (the extractor's contract is correct) and add an **engine-floor guard** at the top of the test file that fails fast with a diagnostic message if the runtime is below the pdfjs-dist engines floor. Pair this with two preventive changes the 2026-04-18 learning prescribed but the repo only half-shipped: (1) honor `.nvmrc` in the `/work`+`/preflight` skill flow so operators get a Node-mismatch warning at session start, (2) thread a `node --version` check into the test suite's vitest setup so any other future test that lazy-imports a pdfjs-dist-class dep gets the same fail-fast diagnostic, not 8 confusing assertion failures.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from #3424 body) | Reality | Plan response |
|---|---|---|
| "Likely the lazy-import path was changed (#3353, #3384) without updating the tests" | False. `git log -p apps/web-platform/server/pdf-text-extract.ts` shows the lazy-import branch is unchanged since the file was first introduced in #3338 (#3353 changed `INPUT_BUFFER_CAP_BYTES` → `MAX_AGENT_READABLE_PDF_SIZE`; #3384 added `read_failed` to the union — neither touched the import). | Document the actual cause (operator Node version drift) in the plan body so the implementer doesn't chase a phantom code-path-change root cause. |
| "Test environment cannot trigger the import-failure code path" | False — it CAN trigger it, on any Node `<` 22.3 / `<` 20.16. The local repro is 100% reproducible at Node 21.7.3 (the operator's current version). | Plan addresses both directions: keep tests truthful AND add the engine-floor diagnostic so the failure is a one-line warning, not an 8-test assertion cascade. |
| "Either fix the production extractor to surface `lazy_import_failed` when the lazy import is unreachable" | The extractor ALREADY surfaces `lazy_import_failed` on import failure — that's exactly why the tests see it. The misframing in the issue body conflates "unreachable in test" with "unreachable in prod". | Reject (A) per Strategy decision above. |
| "Update the tests to match what the extractor actually produces (`corrupted` / `parse_error`)" | The extractor produces `corrupted`/`parse_error` ONLY when pdfjs is reachable. Widening the assertion set masks the environmental fault. | Reject (B) per Strategy decision above. |
| "Discovered during PR #3421 ship phase" | Verified — PR #3421 diff doesn't touch any PDF code. CI for #3421 was green. The /ship preflight ran the test locally on the operator's Node 21 worktree and surfaced the failure. | This is the actual root-cause framing — operator-side Node drift discovered by /ship's preflight running tests in the operator's shell. Plan §Phase 2 closes this loop by making /preflight (and the test runner) check Node version BEFORE running the suite. |

## User-Brand Impact

- **If this lands broken, the user experiences:** Operator-only impact. End users see nothing — production runs on Node 22. A broken fix would either keep Node-21 operators tripping the same 8-test red (status quo) or, if poorly executed, mask a real `lazy_import_failed` regression in production by widening test assertions inappropriately.
- **If this leaks, the user's data/workflow is exposed via:** No data leak. No workflow leak. Pure developer-experience scope.
- **Brand-survival threshold:** `none` — this is a test-environment fix touching `apps/web-platform/test/pdf-text-extract.test.ts` and the test setup. It does not touch credentials, auth, data, payments, or user-owned resources. The diff path is `apps/web-platform/test/**` + a vitest setup file; no sensitive-path regex match per `plugins/soleur/skills/preflight/SKILL.md` Check 6. `reason: test-environment fix only — assertions stay strict, production extractor unchanged, no user-facing surface.`

## Open Code-Review Overlap

Verified via:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/test/pdf-text-extract.test.ts apps/web-platform/server/pdf-text-extract.ts apps/web-platform/test/setup-node-floor.ts; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None.

## Acceptance criteria

### Pre-merge (PR)

- [x] All 9 cases in `apps/web-platform/test/pdf-text-extract.test.ts` pass on Node 22 (CI ground truth) with assertions UNCHANGED from the current spec (`["corrupted", "parse_error"]` etc.).
- [x] Running the test on a Node version below the pdfjs engines floor (`<` 22.3 / `<` 20.16) prints a single human-readable diagnostic line ("Node X.Y.Z is below the pdfjs-dist engines floor — upgrade to ≥22.3 or ≥20.16") and skips (or fails fast with an actionable message — see Phase 1 below for the chosen mode), instead of producing 8 confusing assertion failures.
- [x] One test case in the suite carries `{ timeout: 30_000 }` so a future regression in the lazy-import path (e.g., pdfjs hangs at parse instead of throwing) surfaces inside 30s with a vitest timeout signal, not as a stuck CI job.
- [x] `tsc --noEmit` clean from `apps/web-platform/`.
- [ ] PR body uses `Closes #3424` (per `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [ ] After CI green and merge, run `gh workflow run ci.yml --ref main` to confirm the unit-test job stays green on Node 22 (no regression from the test setup rewire).
- [ ] Operators currently on Node `<` 22 see the diagnostic in their next vitest run and upgrade their local Node — track via a one-off `gh issue close` comment when reported.

## Files to Edit

- `apps/web-platform/test/pdf-text-extract.test.ts` — add an engine-floor guard at the top of the file (or `beforeAll`); add `{ timeout: 30_000 }` to the most likely regression-surfacing case (the `MAX_PAGES` 600-page test, which is also the slowest); leave all assertions unchanged.

## Files to Create

- None mandatory. **Optional Phase 2** (gated on Phase 1 review feedback): `apps/web-platform/test/setup-node-floor.ts` — vitest `setupFiles` entry that runs the engine-floor check before any test file loads, so future tests adding a pdfjs-dist-class lazy import don't have to repeat the guard. Decide at the Phase 2 boundary; default is to inline in the single failing file and defer the shared setup until a second test file needs it (YAGNI).

## Implementation Phases

### Phase 1 — Engine-floor guard inline (the load-bearing fix)

1.1. Compute a single boolean `BELOW_PDFJS_ENGINES_FLOOR` at the top of `pdf-text-extract.test.ts` that reads `process.versions.node`, parses major/minor/patch, and is `true` when:
- Node 22.x with minor `< 3` (e.g., 22.0, 22.1, 22.2 → too old)
- Node 20.x with minor `< 16` (e.g., 20.0 through 20.15 → too old)
- Any other major (Node 18, 19, 21, 23, 25, etc. — none of which clear the engines floor; Node 21 in particular was a non-LTS that pre-dates `process.getBuiltinModule`)
- Otherwise `false`.

1.2. **Decision (revised in deepen pass): `describe.skipIf` + CI escalation.** The original Phase 1 prescribed `throw` in `beforeAll`. Empirical probes (vitest 3.2.4, both shapes) revealed:
- Throw shape: produces "Failed Suites 1" with the single diagnostic; all `it()` cases reported as skipped. Loud red.
- skipIf shape: produces "Test Files 1 skipped (1)" with a stderr `console.warn`. Quiet yellow.
- Codebase precedent: `apps/web-platform/test/byok.integration.test.ts` and `apps/web-platform/test/mu1-integration.test.ts` both use `describe.skipIf` with stderr diagnostics — adopting the same shape preserves grep-discoverability for future maintainers.
- The throw shape's load-bearing property is "fail loud so a misconfigured CI runner doesn't ship green silently." We can recover this property under the skipIf model by escalating to `throw` when `process.env.CI` is set.

The revised guard is both: skipIf in dev (yellow skip, single warning line), throw in CI (red fail, single error). Operator UX wins (no false red on local Node 21); CI safety wins (no vacuous green on misconfigured runner). Bifurcation matches the project's broader pattern of dev-permissive / CI-strict.

1.3. Code shape (load-bearing — the implementer ships approximately this):

```ts
// At the top of pdf-text-extract.test.ts, BEFORE describe()
import { describe, it, expect } from "vitest";

import { extractPdfText } from "@/server/pdf-text-extract";
import { MAX_AGENT_READABLE_PDF_SIZE } from "@/lib/attachment-constants";

// Engine-floor guard for #3424. pdfjs-dist@5.4.296 calls
// `process.getBuiltinModule` during module init (legacy/build/pdf.mjs:5465);
// that builtin landed in Node 22.3 / 20.16. Below the floor, the lazy import
// in extractPdfText throws and every assertion in this file resolves to
// `lazy_import_failed`, masking the extractor's real contract.
//
// Dev: skipIf with a one-line console.error naming the exact remediation, so
// the operator sees a yellow skip + actionable diagnostic instead of an 8-red
// assertion cascade.
//
// CI: process.env.CI is set by GitHub Actions / GitLab / most runners; if a CI
// runner mistakenly lands below the floor, fail the file with a single error
// (matches `mu1-integration.test.ts`'s loud-CI-quiet-dev pattern).
function nodeAtLeast(major: number, minor: number): boolean {
  const [maj, min] = process.versions.node.split(".").map(Number);
  return maj > major || (maj === major && min >= minor);
}
const BELOW_PDFJS_ENGINES_FLOOR = !(nodeAtLeast(22, 3) || nodeAtLeast(20, 16));
const ENGINES_FLOOR_DIAGNOSTIC =
  `[pdf-text-extract.test] Node ${process.versions.node} is below the ` +
  `pdfjs-dist engines floor (>=22.3.0 or >=20.16.0). pdfjs-dist@5 calls ` +
  `process.getBuiltinModule (legacy/build/pdf.mjs:5465) which lands at those ` +
  `versions; below the floor the lazy import throws and every test in this ` +
  `file would resolve to {error: "lazy_import_failed"}. Run \`nvm use 22\` ` +
  `(.nvmrc pins 22) or install Node 22.3+ to run this test. See ` +
  `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md.`;

if (BELOW_PDFJS_ENGINES_FLOOR) {
  console.error(ENGINES_FLOOR_DIAGNOSTIC);
  if (process.env.CI) {
    // Loud failure on CI — a misconfigured CI runner below the floor must NOT
    // ship a vacuous green. Mirrors throw-in-beforeAll without the cross-file
    // grep cost.
    throw new Error(ENGINES_FLOOR_DIAGNOSTIC);
  }
}

describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)("extractPdfText", () => {
  // ... existing 9 cases unchanged, except the MAX_PAGES case carries
  // { timeout: 30_000 } per Phase 1.5 below.
});
```

1.4. Rationale: the diagnostic line names the version, the floor versions, the exact mechanism (`process.getBuiltinModule`), the file:line in pdfjs that calls it, the failure shape (`{error: "lazy_import_failed"}`), the remediation (`nvm use 22`), the source-of-truth file (`.nvmrc`), and the cross-reference learning. Six pieces of context in one line — operator can resolve in seconds without reading the test source. Cross-grep with the production extractor's failure class (`lazy_import_failed`) is preserved.

1.5. **Add `{ timeout: 30_000 }` to the `caps page iteration at MAX_PAGES` case** (currently at test/pdf-text-extract.test.ts:227). This case takes ~600 ms on Node 22 today; if a future pdfjs change makes per-page cost grow or scheduler-internal stalls land, the default 5s budget would surface a regression as a confusing timeout-without-context. The 16 MB Hypothesis A case at line 168 already carries `{ timeout: 15_000 }`, so the suite's pattern is per-case. 30s on the MAX_PAGES case gives a 50× headroom over current measured runtime — comfortable but bounded, matches the issue's prescription verbatim.

1.6. Run on Node 22 (CI ground truth): `cd apps/web-platform && PATH=$HOME/.nvm/versions/node/v22.22.2/bin:$PATH ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts` — confirm 9/9 pass, total ≤ 6s (current measurement: 4.9s, with the 30s timeout reserve unused).

1.7. Run on the operator's Node 21: `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts` — confirm output is "Test Files 1 skipped (1)" + the diagnostic stderr line + zero assertion errors. Run with `CI=1` prefix to confirm the throw-on-CI escalation: `cd apps/web-platform && CI=1 ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts` — confirm output is "Test Files 1 failed (1)" + the same diagnostic.

### Research Insights — Phase 1

**Best Practices:**
- Vitest's `describe.skipIf(condition)` is the canonical conditional-skip pattern (vitest 3.2 docs). It evaluates the condition once at file load, and the entire describe block reports as skipped (not "all 9 cases failing"). Compared to per-case `it.skipIf`, `describe.skipIf` is the right granularity here because the whole file shares the same import-time precondition.
- Diagnostic strings should name the failure mechanism, not just the symptom. "Node X.Y.Z below floor" is the symptom; "pdfjs-dist@5 calls process.getBuiltinModule (legacy/build/pdf.mjs:5465)" is the mechanism. Operators search engines for mechanisms; the line:file pin lets the diagnostic itself be the bug-report material.
- The CI bifurcation pattern (skip-in-dev, throw-in-CI on the same condition) is a strict generalization of skipIf. It preserves the loud-on-misconfig safety of the original throw without paying the cross-file grep cost.

**Performance Considerations:**
- The guard's runtime cost is one `process.versions.node.split(".")` + two `nodeAtLeast` calls = sub-millisecond at file load. Negligible.
- The 30s timeout on MAX_PAGES is reserve, not budget — no per-case cost in the green path. Vitest's timeout fires only when the case actually exceeds it.
- File-load-time diagnostic emission via `console.error` is one stderr write (~microseconds). Single-shot, not per-case.

**Edge Cases:**
- Node 19.x or 18.x: `nodeAtLeast(20, 16)` returns false AND `nodeAtLeast(22, 3)` returns false → guard fires correctly.
- Node 23 or 25 (odd-major non-LTS): both checks return true (e.g., for Node 25.6.0, `nodeAtLeast(22, 3)` is true) → guard does NOT fire. Acceptable; pdfjs-dist@5's engines field accepts these per its semver pattern, and the relevant builtin is present from Node 22.3+ regardless of major.
- Bun / Deno runtimes: `process.versions.node` is the Node-API-emulated version on Bun (`bun --version` differs). Bun ≥ 1.1 emulates Node 22+ for `process.versions.node`, so guard does not fire spuriously. If a future Bun version emulates Node 22 but lacks `process.getBuiltinModule`, the guard would let the test through and the extractor would still throw — caught at the existing assertion layer. Acceptable; out of scope.
- Future Node 24 LTS: when CI moves to it, the guard's `nodeAtLeast(22, 3)` check still passes (24 > 22). No update needed at that boundary; the version-floor logic is forward-compatible.

**References:**
- Vitest `describe.skipIf` docs: <https://vitest.dev/api/#describe-skipif>
- pdfjs-dist@5.4.296 engines field: `apps/web-platform/node_modules/pdfjs-dist/package.json` (verified live in deepen pass).
- pdfjs-dist call site: `apps/web-platform/node_modules/pdfjs-dist/legacy/build/pdf.mjs:5465` (verified live).
- Node `process.getBuiltinModule` doc: <https://nodejs.org/api/process.html#processgetbuiltinmodulename> (added v22.3, back-ported to v20.16).
- Sibling skipIf precedent: `apps/web-platform/test/byok.integration.test.ts`, `apps/web-platform/test/mu1-integration.test.ts`.

### Phase 2 — Explicit non-goal: shared setup file

2.1. **Do not extract.** A shared `apps/web-platform/test/setup-node-floor.ts` is an explicit non-goal of this plan. Rationale:
- The guard is ~25 lines and lives in the ONLY test file that exercises a real pdfjs-dist-class lazy import (verified via `grep -l "pdfjs-dist" apps/web-platform/test/`).
- Every other PDF-touching test (`cc-concierge-pdf-summarize-e2e.test.ts`, `cc-dispatcher-concierge-context.test.ts`, `kb-share-preview.test.ts`) mocks at the function boundary (`vi.mock("@/server/pdf-text-extract", ...)`, `metadataMocks.readPdfMetadata.mockResolvedValue(...)`).
- Extracting before a second consumer exists pays an indirection cost (one more file an operator opens when debugging an unrelated test failure) for zero current return.
- If a second test file ever adds a real pdfjs-dist (or sharp, or libxml — any parser whose engines field outpaces the operator's local Node) lazy import, that's the moment to extract.

2.2. If a reviewer suggests extracting in this PR, point them at this section. If a future PR introduces a second consumer of the guard, file an extraction PR at THAT time, not retroactively to this one.

### Phase 3 — Verification

3.1. Run the full unit project once on Node 22 (CI ground truth): `cd apps/web-platform && PATH=$HOME/.nvm/versions/node/v22.22.2/bin:$PATH ./node_modules/.bin/vitest run --project=unit` — confirm zero regressions in any other test file. Expected delta: zero (no production code changed; only the test file's guard).

3.2. Run `tsc --noEmit` from `apps/web-platform/` — confirm clean.

3.3. Run the CI-escalation probe: `cd apps/web-platform && CI=1 ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts` on the operator's Node 21 — confirm output is "Test Files 1 failed (1)" + the diagnostic. This proves the throw-on-CI branch fires under the same condition that lets the dev path skip.

3.4. Run the dev-path probe: `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts` on the operator's Node 21 (no `CI=` env) — confirm output is "Test Files 1 skipped (1)" + the diagnostic stderr line, no assertion errors.

3.5. Push the branch, open the PR with `Closes #3424`, let CI exercise the test on Node 22 (CI's actual runtime).

3.6. After CI green, ship via the standard `/soleur:ship` flow.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-environment fix touching one test file and the developer experience around Node version detection. CTO not flagged because the change has no architectural surface (no new patterns, no new dependencies, no production code modified). CPO not flagged because the change has no user-facing surface.

## Test Scenarios

| Scenario | Pre-fix on Node 21 (dev) | Pre-fix on Node 22 (any) | Post-fix on Node 21 dev (no CI=) | Post-fix on Node 21 with CI=1 | Post-fix on Node 22 (any) |
|---|---|---|---|---|---|
| Single-page PDF text extraction | FAIL (lazy_import_failed) | PASS | SKIPPED + stderr diagnostic | FAIL-FAST (single error) | PASS |
| Multi-page PDF, pageCount=2 | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS |
| Truncate when capChars=20 | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS |
| Garbage buffer → corrupted/parse_error | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS |
| 16 MB band → not oversized_buffer | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS |
| Empty 0-page PDF | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS |
| Mid-stream truncation → corrupted/parse_error | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS |
| MAX_PAGES=500 cap + 600-page PDF | FAIL (lazy_import_failed) | PASS | SKIPPED | FAIL-FAST | PASS (≤30s budget) |
| Oversized buffer → oversized_buffer | PASS (size guard pre-empts the import) | PASS | SKIPPED | FAIL-FAST | PASS |

**Reporter shape (verified empirically in deepen pass):**
- "SKIPPED + stderr diagnostic" cell: vitest reports `Test Files 1 skipped (1)`, `Tests N skipped (N)`, with the diagnostic written via `console.error`. Yellow tone; exit code 0; the operator can keep working.
- "FAIL-FAST" cell: vitest reports `Test Files 1 failed (1)`, `Tests N skipped (N)`, with a single `Error:` line containing the diagnostic. Red tone; exit code 1; CI's existing red-on-failure handling fires.
- "PASS" cell (Node 22): all 9 cases run; total runtime ~5s; no warnings except pdfjs's own `standardFontDataUrl` and `Indexing all PDF objects` (both pre-existing, unrelated to this plan).

## Risks

- **Risk:** the Node-version logic produces a false-positive guard on a future Node major. **Mitigation:** the new logic uses `nodeAtLeast(22, 3) || nodeAtLeast(20, 16)` — any major ≥ 22 with minor ≥ 3 OR any major ≥ 20 with minor ≥ 16 clears the floor. Forward-compatible through Node 24 LTS, 26 LTS, etc. The diagnostic explicitly names the floor versions so an operator on a newer Node can file an issue if it ever fires unexpectedly.
- **Risk:** dev path silently skips on a misconfigured CI runner. **Mitigation:** the `process.env.CI` escalation throws on CI, matching `mu1-integration.test.ts`'s loud-CI-quiet-dev pattern. GitHub Actions, GitLab, CircleCI, and Buildkite all set `CI=true` by default; misconfigured CI is detected at the same moment as the dev case.
- **Risk:** the diagnostic line is long (~6 lines wrapped). **Mitigation:** acceptable — operators see it once per misconfigured run and the line names the exact remediation (`nvm use 22`). A short diagnostic ("Node too old") would just produce a follow-up debug round; the verbose line is the cost-amortized choice.
- **Risk:** widening the `MAX_PAGES` timeout to 30s lets a real regression (pdfjs hangs forever) consume 30s before failing. **Mitigation:** acceptable — 30s is the issue-prescribed sentinel; vitest's default 5s already catches the common-case fast-path; 30s is the explicit slow-path budget. Per the defense-relaxation rule (`hr-when-a-plan-relaxes-or-removes`-class concerns), the 30s ceiling is a NEW slower-than-default budget on a SPECIFIC case (not a relaxation of an existing default for all cases), so no new ceiling is required.
- **Risk:** the inline guard creates a precedent that other test files copy without thinking. **Mitigation:** Phase 2's explicit non-goal documents that the guard SHOULD be extracted at the second consumer, not preemptively. A reviewer copying the pattern to a non-pdfjs test should be redirected to Phase 2's rationale.

## Test Strategy

`apps/web-platform/test/pdf-text-extract.test.ts` is the only test file affected. Vitest's `unit` project (Node environment) is the right runner. Verify:

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts` on Node 22 → 9/9 pass
- Same command on Node 21 → 1 file failed with the single-line diagnostic; 0 cases ran

No new test framework. No new dependency (`vitest`, `pdfjs-dist@^5.4.296`, `Node` are all already in `apps/web-platform/package.json`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with explicit reason; verified above.
- Do NOT change the existing assertions (`["corrupted", "parse_error"]`, `isOk(result)`, etc.) to widen them with `"lazy_import_failed"` — that's the (B) strategy this plan explicitly rejects. The assertions encode the extractor's contract on a working pdfjs; a too-old Node is an environmental fault, not an extractor contract change. Widening assertions to swallow environmental drift is the vacuous-pass pattern documented in the strategy decision.
- Do NOT replace `describe.skipIf` with a `try { import("pdfjs-dist") } catch { skipAllTests }` runtime probe. The probe pattern silently skips on a misconfigured CI runner and produces a vacuous green; the engines-floor + `process.env.CI` bifurcation is strictly better because it loud-fails CI on the same condition that lets dev skip.
- Do NOT drop the `process.env.CI` escalation. It is the load-bearing safety net that turns the skip model into a strict superset of the throw model: dev keeps working (yellow skip), CI keeps failing (red error). Removing the escalation reintroduces the vacuous-green-on-misconfigured-CI risk.
- When Node 24 LTS ships and CI moves to it, the guard's `nodeAtLeast(22, 3) || nodeAtLeast(20, 16)` logic remains correct — Node 24 satisfies `nodeAtLeast(22, 3)`. No update needed at that boundary. If pdfjs-dist's engines field shifts in a future major bump, update both `apps/web-platform/package.json` engines AND the constants in this guard in the same PR.
- The 30s timeout sentinel is on the `MAX_PAGES` test specifically because that's the test most likely to surface a future scheduler-level regression. Do NOT distribute the timeout across multiple cases — it pollutes the diagnostic signal when one of them legitimately gets slow for a different reason.
- This fix does NOT address the root prevention (operator-side `.nvmrc` honor in `/work` skill Phase 0 startup). That's a separate enhancement tracked under the 2026-04-18 learning's "Promote to enforcement" prescription; filing a follow-up issue is part of the post-merge handoff per `wg-when-deferring-a-capability-create-a`.
- The diagnostic line includes a cross-reference to `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md`. Do NOT remove or shorten this reference — it is the institutional memory that turns the diagnostic into a discoverable repair path for the next operator.
- The skipIf shape's reporter exit code is 0 in dev — operators on Node 21 get no red signal locally. This is intentional (operator UX); the safety net is the CI escalation. Do NOT add `process.exit(1)` or any other hack to make dev red — it would force every operator on Node 21 into a debug round on every test invocation.

## Cross-references

- `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md` — root cause documented; the "Engine requirement" section names the exact `process.getBuiltinModule` floor this plan keys off.
- `knowledge-base/project/learnings/2026-05-06-cc-concierge-pdf-summary-cascade-structural-fix.md` — the cascade chain that introduced `extractPdfText`.
- `apps/web-platform/server/pdf-text-extract.ts` — the production extractor; UNCHANGED by this plan.
- `apps/web-platform/server/kb-preview-metadata.ts` — sibling file with the same lazy-import pattern; tests for it (`kb-share-preview.test.ts` tests 16-20) mock at the function boundary and don't exercise real pdfjs, so they aren't affected by this plan.
- `.nvmrc` — already pins Node 22; no change.
- `apps/web-platform/package.json` `engines` — already `">=20.16.0 || >=22.3.0"`; no change.
- `.github/workflows/ci.yml` — already pins `node-version: 22` on the unit-test job; no change.

## Follow-up issues to file

- **Operator Node-floor enforcement at `/work` startup.** File a separate issue tracking the 2026-04-18 learning's "Promote to enforcement" prescription (read `.nvmrc`, compare against `process.versions.node` at `/work` Phase 0, warn if mismatched). Out of scope for this fix; this plan's engine-floor guard is the test-file-local version of that protection. Milestone: Post-MVP / Later. Labels: `domain/engineering`, `priority/p3-low`, `type/chore` (verified extant via `gh label list`).

## Resume prompt (after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-05-07-fix-pdf-text-extract-tests-node-version-3424-plan.md

Context: branch feat-one-shot-3424-pdf-extract-tests, worktree .worktrees/feat-one-shot-3424-pdf-extract-tests/, issue #3424.
Plan written; engine-floor guard chosen as fix; reject (A)/(B) strategies. Phase 1 inline guard is the load-bearing change; tests assertions unchanged.
```
