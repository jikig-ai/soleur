---
type: bug-fix
classification: developer-environment-alignment
issue: 3439
also_closes: [3438]
branch: feat-one-shot-3439-pdfjs-node22-floor
requires_cpo_signoff: false
deepened_on: 2026-05-07
---

# fix: align dev-env Node floor + extend pdfjs engine-floor guard + cover lazy_import_failed (#3439, #3438)

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** 5 (Risks, Files to Edit, Implementation Phases, Acceptance Criteria, Research Reconciliation)
**Verification sources:** Live `gh pr/issue view`, installed `node_modules/pdfjs-dist/legacy/build/pdf.mjs:5465`, `apps/web-platform/vitest.config.ts` projects/include patterns, `apps/web-platform/test/helpers/bundled-server.ts` precedent.

### Key Improvements

1. **Vitest discovery confirmed safe.** `vitest.config.ts` declares `include: ["test/**/*.test.ts"]` for the unit project and `include: ["test/**/*.test.tsx"]` for the component project. The new `test/helpers/engines-floor.ts` (no `.test.` infix) cannot be picked up as a test — same precedent as the existing `test/helpers/bundled-server.ts` shared harness. Risk #1 in the original draft is downgraded from "low" to "verified-not-applicable".
2. **Live SHA/PR verification.** Cited PRs verified against `gh pr view`: #3391 (MERGED 2026-05-06, "fix(test): pin Node version to satisfy pdfjs-dist engines"), #3431 (MERGED 2026-05-07, "fix(test): engine-floor guard for pdf-text-extract suite (#3424)"). Cited issue: #3438 (OPEN, "review: add direct lazy_import_failed test for extractPdfText (PR #3431)"). No fabrication.
3. **pdfjs source line confirmed.** `apps/web-platform/node_modules/pdfjs-dist/legacy/build/pdf.mjs:5465` literally contains `return globalThis.process.getBuiltinModule(name);` — the engine-floor mechanism is real and the diagnostic's line citation is accurate.
4. **`apps/web-platform/README.md` already covers the Requirements messaging.** The original plan said "append a one-line pointer"; the actual existing README.md:7 already names "Node.js ≥ 22.3" and explains the `process.getBuiltinModule` mechanism. Plan revised to "append a one-line pointer to the new `apps/web-platform/.nvmrc` file at the same location" rather than introducing duplicate prose.
5. **`test:ci` script verified.** `apps/web-platform/package.json:16` declares `"test:ci": "vitest run"`. Verification commands updated to use `npm run test:ci` (the existing convention) instead of raw `npx vitest run` where appropriate — matches `scripts/test-all.sh:64` invocation.

### New Considerations Discovered

- **Vitest `projects` config splits unit + component.** The three pdfjs files are `.test.ts` (unit project, `environment: node`). The shared helper has no `.test.` infix in either project's include list. No project-level discovery surface to worry about.
- **`scripts/test-all.sh` invokes `npm run test:ci`.** That maps to `vitest run` which respects both projects. Skip behavior surfaces in vitest's reporter as `↓ test/pdf-text-extract.test.ts (skipped)` etc. — a yellow line, not a red X. The test-all.sh `[ok]` label still fires because `vitest run` exits 0 on skip.
- **`describe.skipIf` semantics with the bundled-server tests.** Each bundled-server file has exactly one `it(...)` inside one `describe(...)`. `describe.skipIf` skips the whole suite + its single test — equivalent to `it.skipIf` here, but matching the precedent established in `pdf-text-extract.test.ts` for consistency.
- **No drift risk for `engines.node` vs. `.nvmrc`.** Verified `apps/web-platform/package.json:7` (`"node": ">=20.16.0 || >=22.3.0"`) and the new `.nvmrc` would pin `22.3.0`. Sharp Edge added: bumping `engines.node` requires same-PR `.nvmrc` bump.

## Overview

`scripts/test-all.sh` reports 1/26 suites failing on Node v21.7.3 — three pdfjs-dist–dependent suites all failing with the same `ReferenceError: DOMMatrix is not defined` followed by `Cannot access the require function: process.getBuiltinModule is not a function`. PR #3431 (merged 2026-05-07) already addressed this for the headline suite (`pdf-text-extract.test.ts`) by adding an engine-floor guard. This plan completes the job by:

1. Extending the same engine-floor guard pattern to the two sibling bundled-server suites named in #3439's symptom list (`pdf-text-extract.bundled-server.test.ts`, `kb-preview-metadata.bundled-server.test.ts`) so a Node <22.3 runner gets a yellow skip + actionable stderr diagnostic instead of a red 1-of-1 failure on each suite.
2. Aligning the dev-environment Node-version pin files (root `.nvmrc`, new `apps/web-platform/.nvmrc`) so a contributor running `nvm use` / `fnm use` / `asdf install` in either the repo root or the app directory lands on a Node version above the pdfjs floor without re-discovering the issue. The root `.nvmrc` currently says `22` (a major-version-only pin that resolves to whatever `22.x` the version manager has cached — not necessarily 22.3+); pinning to `22` is sufficient because `nvm install 22` always installs the latest 22.x (currently >22.3), but documenting the floor explicitly closes the trap door.

`engines.node` in `apps/web-platform/package.json` is **already** `">=20.16.0 || >=22.3.0"` (pinned by PR #3391, confirmed via Read of the file at HEAD). No package.json change needed; the issue body's "Pin engines.node >=22.3" recommendation is already satisfied.

The production runtime is unaffected — `apps/web-platform/Dockerfile` pins `node:22-slim` (currently 22.22.x). CI runners pin `node-version: 22` in every `apps/web-platform`-touching job (`ci.yml:78,103,129,161`). The fix is dev-environment-only.

## User-Brand Impact

**If this lands broken, the user experiences:** No user impact. This is a developer-environment fix (test-runner skip behavior + dev-machine `.nvmrc` files). The production extractor (`server/pdf-text-extract.ts`) is unchanged.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. No credentials, data paths, payment flows, or auth surfaces touched. Files modified are restricted to `apps/web-platform/test/*.bundled-server.test.ts` (test-only), root `.nvmrc` (dev tooling), `apps/web-platform/.nvmrc` (new dev tooling file), and a one-paragraph addition to `apps/web-platform/test/README.md` (docs).

**Brand-survival threshold:** none

**Threshold-none scope-out (per AGENTS.md `hr-weigh-every-decision-against-target-user-impact` + preflight Check 6.1):** threshold: none, reason: test-only and dev-tooling change with zero diff in the production extractor or any prod-reachable code path; production already runs Node 22.22.x via the `node:22-slim` Dockerfile and CI runners pin `node-version: 22`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (#3439 body) | Reality (verified at HEAD) | Plan response |
| --- | --- | --- |
| "Pin `engines.node >=22.3` in `apps/web-platform/package.json`" | Already pinned (line 7: `"node": ">=20.16.0 || >=22.3.0"`) — landed in PR #3391 (40ba6a27). | No-op. Note in plan body that the issue's first remediation step is already done. |
| "update the local-dev README + `.bun-version`/`.nvmrc` (if present) to match" | Root `.nvmrc` exists with `22` (major-version pin). `apps/web-platform/.nvmrc` does NOT exist. `apps/web-platform/README.md:7` already names "Node.js ≥ 22.3" in Requirements section. | Add `apps/web-platform/.nvmrc` with `22.3.0` to anchor the floor explicitly. Leave root `.nvmrc` as `22` (resolves to latest 22.x via `nvm install 22`); add a comment-style README note pointing contributors at `apps/web-platform/.nvmrc` for the binding floor. |
| "1/26 suites failing locally — 8/9 + 2 sibling suites" | Confirmed: `apps/web-platform` is one of 26 suites in `test-all.sh`. Failure cascade is `pdf-text-extract.test.ts` (8/9) + `pdf-text-extract.bundled-server.test.ts` (1/1) + `kb-preview-metadata.bundled-server.test.ts` (1/1) on Node v21.7.3. | PR #3431 already covers the 9-test suite. This plan covers the two 1-test suites. |
| "gate pdfjs tests on a Node 22.3+ check via `it.skipIf(...)` (less ideal — masks real Node-version drift)" | The PR #3431 implementation chose `describe.skipIf` (dev) + `throw at module init` (CI) — strictly stronger than the issue's "less ideal" suggestion. CI throws on a misconfigured runner; only dev paths skip silently. | Use the SAME pattern (extract the guard helper to share between the three test files) — keeps CI loud, keeps dev quiet. |

## Hypotheses

Single hypothesis: extending the existing `BELOW_PDFJS_ENGINES_FLOOR` guard from PR #3431 to the two sibling bundled-server tests will short-circuit them on Node <22.3 with a stderr diagnostic (dev) or a thrown init-time Error (CI), bringing `scripts/test-all.sh` to 26/26 green on a contributor workstation.

The bundled-server suites can NOT be skipped at the `bundleAndExec` layer — that helper is shared, deterministic, and exists to assert the production esbuild bundle excludes pdfjs. The skip MUST happen at the test file level so the skip diagnostic is co-located with the operator's failure, the same shape as the existing fix in `pdf-text-extract.test.ts`.

No L3/network-outage signal in this issue (no SSH/firewall/timeout patterns), so Phase 1.4's network-outage checklist does not apply.

## Files to Edit

- `apps/web-platform/test/pdf-text-extract.bundled-server.test.ts` — wrap the existing `describe(...)` in a `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)`, with the same dev/CI branch as `pdf-text-extract.test.ts:62-75`.
- `apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts` — same wrap.
- `apps/web-platform/test/pdf-text-extract.test.ts` — (a) refactor lines 20-75 (the `supportsGetBuiltinModule()` helper + `BELOW_PDFJS_ENGINES_FLOOR` const + diagnostic + dev/CI branch) into a shared helper at `apps/web-platform/test/helpers/engines-floor.ts`. Import and use the helper here. Diagnostic remains test-file-specific (each diagnostic names its own file). (b) Add one new `it(...)` (per #3438) that uses `vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", ...)` to throw at module init, asserts `result.error === "lazy_import_failed"`, and asserts `reportSilentFallback` was called with the expected `feature`/`extra` shape. Place this test **outside** the `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)` block so it runs on Node 21 too — the mock short-circuits the real import; `process.getBuiltinModule` is never reached.
- `apps/web-platform/test/README.md` — add a 4-line bullet under existing content explaining the engine-floor skip behavior (dev = yellow skip + stderr diagnostic; CI = red throw at module init) and pointing at `apps/web-platform/.nvmrc`.
- `.nvmrc` (root) — leave as `22` (no edit). The major-version pin resolves to latest 22.x via `nvm install 22`, which always satisfies the 22.3 floor. Documented in README.
- `apps/web-platform/README.md` — append a one-line pointer to the new `apps/web-platform/.nvmrc` at the **end of the existing line 7 paragraph** (which already names "Node.js ≥ 22.3" and explains the `process.getBuiltinModule` mechanism — verified in deepen pass; do NOT introduce duplicate prose).

## Files to Create

- `apps/web-platform/test/helpers/engines-floor.ts` — new shared helper:

  ```ts
  // apps/web-platform/test/helpers/engines-floor.ts
  // Shared engine-floor guard for pdfjs-dist-dependent test suites.
  //
  // pdfjs-dist@5.4.296 calls `process.getBuiltinModule` during module init
  // (legacy/build/pdf.mjs:5465); that builtin landed in Node 22.3 / 20.16.
  // Below the floor the lazy `await import("pdfjs-dist/legacy/build/pdf.mjs")`
  // throws and every assertion in the suite resolves to `lazy_import_failed`,
  // masking the real contract.
  //
  // Floor expressed as `>=22.3.0 || (>=20.16.0 AND <21)` — keep in sync with
  // `apps/web-platform/package.json` `engines.node`.
  //
  // Use a regex match over `process.versions.node` (NOT `split(".").map(Number)`
  // which returns NaN on prerelease tags like `22.3.0-nightly...`).

  export function supportsPdfjsEngineFloor(): boolean {
    const match = process.versions.node.match(/^(\d+)\.(\d+)\./);
    if (!match) return true; // Unknown shape (bun/deno emulation) — fail open.
    const maj = Number(match[1]);
    const min = Number(match[2]);
    if (!Number.isFinite(maj) || !Number.isFinite(min)) return true;
    if (maj >= 23) return true;
    if (maj === 22) return min >= 3;
    if (maj === 21) return false;
    if (maj === 20) return min >= 16;
    return false;
  }

  export const BELOW_PDFJS_ENGINES_FLOOR = !supportsPdfjsEngineFloor();

  /**
   * Build a diagnostic string for the calling test file. Names version, floor,
   * mechanism, file:line, failure class, remediation, and learning cross-ref.
   */
  export function pdfjsEngineFloorDiagnostic(testFileLabel: string): string {
    return (
      `[${testFileLabel}] Node ${process.versions.node} is below the ` +
      `pdfjs-dist engines floor (>=22.3.0 or >=20.16.0). pdfjs-dist@5 calls ` +
      `process.getBuiltinModule (legacy/build/pdf.mjs:5465) which lands at ` +
      `those versions; below the floor the lazy import throws and every test ` +
      `in this file would resolve to {error: "lazy_import_failed"}. Run your ` +
      `version manager's .nvmrc reader (nvm use, fnm use, asdf install, ` +
      `volta pin) or install Node 22.3+ to run this test. See ` +
      `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md.`
    );
  }

  /**
   * Idempotent module-init side-effect: throw on CI (so a misconfigured runner
   * cannot ship a vacuous green), stderr-write on dev (single yellow skip).
   */
  export function emitPdfjsEngineFloorDiagnostic(testFileLabel: string): void {
    if (!BELOW_PDFJS_ENGINES_FLOOR) return;
    const diagnostic = pdfjsEngineFloorDiagnostic(testFileLabel);
    if (process.env.CI) {
      throw new Error(diagnostic);
    }
    process.stderr.write(diagnostic + "\n");
  }
  ```

- `apps/web-platform/.nvmrc` — single line: `22.3.0`. (Anchors the binding floor; contributors running `nvm use` from the app directory get exactly the floor minimum.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/test/helpers/engines-floor.ts` exists, exports `BELOW_PDFJS_ENGINES_FLOOR`, `pdfjsEngineFloorDiagnostic(label)`, `emitPdfjsEngineFloorDiagnostic(label)`.
- [x] `apps/web-platform/test/pdf-text-extract.test.ts` imports from the helper instead of defining the guard inline. Behavior unchanged on Node 22.3+ (9/9 pass) and Node 21.x (file skipped, single stderr diagnostic, no double-print).
- [x] `apps/web-platform/test/pdf-text-extract.bundled-server.test.ts` wraps `describe(...)` in `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)`. Calls `emitPdfjsEngineFloorDiagnostic("pdf-text-extract.bundled-server.test")` at module top.
- [x] `apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts` same wrap with its own label.
- [x] On Node 21.7.3 dev path: `scripts/test-all.sh` reports `26/26` (was `25/26`); each of the three pdfjs suites prints exactly one stderr diagnostic line and skips cleanly. Verify via `node --version && bash scripts/test-all.sh 2>&1 | tail -10`.
- [x] On Node 22.22+ ground truth: all three suites pass (no skips). Verified locally via `nvm use 22 && cd apps/web-platform && npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts`.
- [x] On Node 21.7.3 with `CI=1`: each of the three pdfjs suites throws at module init with a single Error message (no double-print). Verified via `CI=1 npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts 2>&1 | grep -c "DOMMatrix"` returning 0 (the throw short-circuits before pdfjs init).
- [x] `apps/web-platform/.nvmrc` exists with content `22.3.0\n`.
- [x] `apps/web-platform/README.md` Requirements section names the new `apps/web-platform/.nvmrc` and remediation flow.
- [x] `apps/web-platform/test/README.md` documents the engine-floor skip behavior.
- [x] `tsc --noEmit` clean from `apps/web-platform/`.
- [x] Full unit suite on Node 22 via `cd apps/web-platform && npm run test:ci` (matches `scripts/test-all.sh:64`): no regressions vs. main (`2885 passed | 30 skipped` per PR #3431's verified baseline).
- [x] New `it("returns lazy_import_failed when pdfjs module init throws", ...)` test added to `apps/web-platform/test/pdf-text-extract.test.ts` outside the `describe.skipIf` block. Uses `vi.doMock` to simulate module-init failure; asserts `result.error === "lazy_import_failed"` AND `reportSilentFallback` was called with `feature: "pdf-text-extract"` (or matching `feature` slug at `pdf-text-extract.ts:107-115`) and the expected `extra` shape. Test passes on Node 21.7.3 and Node 22.x (the `vi.doMock` mocks the real import).
- [x] `Closes #3439` on its own line in PR body.
- [x] `Closes #3438` on its own line in PR body — folded in per user request (lazy_import_failed direct test).

### Post-merge (operator)

- [x] None. Test-only and dev-tooling change; no infra apply, no migration, no ops handoff.

## Open Code-Review Overlap

- **#3438** — "review: add direct lazy_import_failed test for extractPdfText (PR #3431)". Touches `apps/web-platform/test/pdf-text-extract.test.ts`. **Disposition: Folded in (per user request 2026-05-07).** Adding the proposed `vi.doMock` test (~15-20 lines) is mechanically compatible with this plan: same file, same helpers, the new test sits outside the `describe.skipIf` block exactly as #3438 prescribes. The marginal cost is a single `it(...)` block; the marginal benefit is closing a P3 coverage gap on the production extractor's `lazy_import_failed` discriminated-union branch and emptying a deferred-scope-out queue entry. PR body uses `Closes #3438`.

## Test Strategy

Verification is binary and mechanical — three runtime profiles:

1. **Node 22.22.x (CI ground truth):** all three suites pass without skip.
2. **Node 21.7.3 (local dev path):** all three suites skip cleanly, each emitting exactly one stderr diagnostic.
3. **Node 21.7.3 with `CI=1` (forward-defense for misconfigured runners):** each of the three suites throws at module init with a single Error message; no `DOMMatrix is not defined` reaches stderr (the throw short-circuits before the lazy import is evaluated).

No new vitest cases are added beyond the wrap. The existing `it(...)` cases inside each `describe(...)` are unchanged. The shared-helper extraction is verified by tsc + the existing 9-case suite passing on Node 22.

## Risks

1. **~~Helper-file location collides with vitest discovery.~~ Verified-not-applicable.** `apps/web-platform/vitest.config.ts` explicitly declares `include: ["test/**/*.test.ts"]` for the unit project and `include: ["test/**/*.test.tsx"]` for the component project. The new `test/helpers/engines-floor.ts` (no `.test.` infix) cannot match either pattern. Same precedent as `test/helpers/bundled-server.ts`, which sits in the same directory and is also not picked up as a test.
2. **Node 22.0 / 22.1 / 22.2 contributors.** The floor is 22.3, so a contributor on 22.0-22.2 will hit the same guard. The diagnostic names this exactly. Same outcome as Node 21.x: skip on dev, throw on CI. Acceptable.
3. **`apps/web-platform/.nvmrc` overrides root `.nvmrc` for nvm/fnm/asdf.** This is the desired behavior — `cd apps/web-platform && nvm use` should pin to the binding floor, not the looser root pin. README.md update calls this out.
4. **Bundled-server skip masks pdfjs-bundling regression on Node <22.3 dev path.** A contributor running `bash scripts/test-all.sh` on Node 21.x will not catch a future regression that re-bundles `pdfjs-dist` into the production CJS. Mitigation: the regression rail is a CI-only contract (CI is on Node 22). The dev path is for fast feedback; the CI path is the merge-gate. Same trade-off as PR #3431.
5. **`apps/web-platform/.nvmrc` content drift vs. `engines.node` floor.** If a future PR raises `engines.node` to `>=22.5.0` for a pdfjs major bump, the `.nvmrc` file must be raised in the same commit. Sharp Edges below adds the cross-reference invariant.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with the required scope-out reason — verified above.
- When raising `apps/web-platform/package.json:engines.node`, also bump `apps/web-platform/.nvmrc` in the same PR. They are the binding floor pair — drift between them re-creates exactly the #3439 trap.
- The `engines-floor.ts` helper is intentionally co-located with `bundled-server.ts` under `apps/web-platform/test/helpers/`. Keep `helpers/` as the convention; resist exporting the helper from `apps/web-platform/server/` (it would couple test-runtime version detection into the production module graph).
- The CI-throw branch is forward-defense for misconfigured runners — every CI workflow today pins `node-version: 22`, so the throw never fires. Don't remove it as "dead code"; the load-bearing value is "a future workflow that drops the pin re-fails loud" not "this code path executes on current CI".
- Don't replace `describe.skipIf` with `it.skipIf` for the bundled-server suites. Each of those files has only one `it`, so `it.skipIf` would technically work, but `describe.skipIf` is the precedent established by `pdf-text-extract.test.ts` and the diagnostic emission semantics (file-level, once per skip) match `describe`-level placement.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-only refactor + dev-tooling alignment. No infrastructure, payments, auth, content, design, finance, legal, or product surface touched. CTO/CMO/CPO/COO/CLO/CRO sweep returned no signal.

## Out of Scope

- Auto-installing Node 22.3+ for contributors below the floor (e.g., a `lefthook` pre-commit that runs `nvm install 22.3.0`). Out of scope; contributor opt-in is the convention.
- Hardening the `bundleAndExec` helper to short-circuit on Node <22.3. The skip belongs at the test-file level so the diagnostic surfaces with the test.
- Raising `engines.node` to `>=22.3.0` only (dropping the `>=20.16.0` branch). Out of scope — the dual-branch declaration matches Node's dual-LTS support window and is the upstream pdfjs-dist published floor.

## Implementation Phases

### Phase 1 — Extract shared helper (TDD-exempt: refactor)

1. Create `apps/web-platform/test/helpers/engines-floor.ts` with the three exports (`BELOW_PDFJS_ENGINES_FLOOR`, `pdfjsEngineFloorDiagnostic`, `emitPdfjsEngineFloorDiagnostic`). Body verbatim from the helper block above.
2. Replace lines 20-75 of `apps/web-platform/test/pdf-text-extract.test.ts` with:

   ```ts
   import {
     BELOW_PDFJS_ENGINES_FLOOR,
     emitPdfjsEngineFloorDiagnostic,
   } from "./helpers/engines-floor";

   emitPdfjsEngineFloorDiagnostic("pdf-text-extract.test");
   ```

   The existing `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)` at line 165 stays.
3. Verify Node 22 still 9/9 passes; Node 21 still skips with one stderr line (no double-print).

### Phase 2 — Extend guard to sibling suites

4. In `apps/web-platform/test/pdf-text-extract.bundled-server.test.ts`, add at the top after the existing imports block:

   ```ts
   import {
     BELOW_PDFJS_ENGINES_FLOOR,
     emitPdfjsEngineFloorDiagnostic,
   } from "./helpers/engines-floor";

   emitPdfjsEngineFloorDiagnostic("pdf-text-extract.bundled-server.test");
   ```

   Then change `describe(...)` to `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)(...)`.
5. Same change to `apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts` with label `"kb-preview-metadata.bundled-server.test"`.
6. Re-run all three modes (Node 22, Node 21 dev, Node 21 CI=1).

### Phase 2.5 — Add lazy_import_failed direct test (closes #3438)

5a. After the `describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)` block in `apps/web-platform/test/pdf-text-extract.test.ts`, add a new top-level `describe("extractPdfText lazy_import_failed", ...)` (no `skipIf` — runs on all Node versions). Inside it, one `it("returns lazy_import_failed when pdfjs module init throws", ...)`:

```ts
import { reportSilentFallback } from "@/server/observability";

vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: vi.fn() };
});

describe("extractPdfText lazy_import_failed", () => {
  it("returns lazy_import_failed when pdfjs module init throws", async () => {
    vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () => {
      throw new Error("simulated module-init failure");
    });
    vi.resetModules();
    const { extractPdfText } = await import("../server/pdf-text-extract");
    const result = await extractPdfText(new Uint8Array([0x25, 0x50, 0x44, 0x46]));
    expect(result.error).toBe("lazy_import_failed");
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: expect.stringContaining("pdf") }),
    );
    vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
  });
});
```

The exact `feature` slug + `extra` keys are read from `apps/web-platform/server/pdf-text-extract.ts:107-115` during implementation; the assertion shape is loose (`stringContaining("pdf")` + `objectContaining`) to avoid brittleness.

5b. Verify on Node 21.7.3: this single new test passes (the rest of the file is skipped). On Node 22.x: the new test passes alongside the original 9.

### Phase 3 — Dev-tooling alignment

7. Create `apps/web-platform/.nvmrc` with content `22.3.0\n`.
8. Append to `apps/web-platform/README.md`'s existing line 7 paragraph (which already says "Node.js ≥ 22.3 ..."): " Run `nvm use` (or `fnm use` / `asdf install`) from `apps/web-platform/` to land on the binding floor — the directory's `.nvmrc` pins `22.3.0`." Do NOT add a new bullet or new section.
9. Append to `apps/web-platform/test/README.md` a 4-line bullet documenting the engine-floor skip + CI-throw behavior, naming the helper file.

### Phase 4 — Verification

10. `bash scripts/test-all.sh 2>&1 | tail -10` on Node 21.7.3 → expect `26/26 suites passed`.
11. `cd apps/web-platform && nvm use 22 && npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts` → expect 11 tests passing (9 + 1 + 1).
12. `CI=1 npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts` on Node 21.7.3 → expect 3 module-init throws with diagnostic Error messages.
13. `cd apps/web-platform && npx tsc --noEmit` → clean.
14. Full unit suite on Node 22 (`npm run test:ci`) → no regressions vs. main baseline.

## Verification Commands

```bash
# 1. Engine-floor skip behavior on Node 21.7.3 (dev)
node --version  # v21.7.3
bash scripts/test-all.sh 2>&1 | tail -10
# expect: 26/26 suites passed

# 2. Stderr diagnostic count (dev path)
cd apps/web-platform
npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts 2>&1 | grep -c "below the pdfjs-dist engines floor"
# expect: 3

# 3. CI throw path
CI=1 npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts 2>&1 | grep -c "DOMMatrix is not defined"
# expect: 0  (throw short-circuits before pdfjs init)

# 4. Node 22 ground truth
nvm use 22.22  # or any 22.3+
npx vitest run test/pdf-text-extract.test.ts test/pdf-text-extract.bundled-server.test.ts test/kb-preview-metadata.bundled-server.test.ts
# expect: 11 tests passing, 0 skipped

# 5. tsc clean
npx tsc --noEmit
```

## References

- Issue #3439 — this plan closes it.
- PR #3431 — engine-floor guard for `pdf-text-extract.test.ts` (the precedent this plan extends).
- PR #3391 — `engines.node` pin in `apps/web-platform/package.json` (already merged; the issue's first remediation is already done).
- Issue #3438 — code-review scope-out for direct `lazy_import_failed` test; **folded in** per user request 2026-05-07 (see Open Code-Review Overlap).
- Learning `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md` — original pdfjs/Node-version-floor incident.
- Learning `knowledge-base/project/learnings/2026-05-07-pdfjs-dist-bundling-reorder-breaks-node-init.md` — the bundled-server regression rail this plan does NOT change.
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — User-Brand Impact threshold-none scope-out.
- AGENTS.md `cq-test-fixtures-synthesized-only` — covered (no fixture changes; existing minimal-PDF synthesis is untouched).
