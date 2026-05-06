---
title: Source-grep drift-guards break after build-time interpolation; switch to compile-time identity
date: 2026-05-06
category: test-failures
tags: [drift-guard, build-time-interpolation, typescript-identity, no-fouc-script, theme-system]
problem_type: test_failure
component: theme/no-fouc-script
related_pr: "#3309"
related_learnings:
  - 2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md
  - 2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md
---

# Source-grep Drift-Guards Break After Build-Time Interpolation

## Problem

PR #3309 introduced a runtime helper `disableTransitionsForOneFrame` in `theme-provider.tsx` and a parallel inline boot-script in `no-fouc-script.tsx`. Both injected a transient `<style id="__soleur-no-transition">` with the same CSS text. The original test asserted on the SCRIPT source via `readFileSync`:

```ts
expect(src).toContain("__soleur-no-transition");
expect(src).toContain("* { transition: none !important; ...");
```

This caught lexical drift between the two files but provided no real guarantee — the `STYLE_ID` was a string literal in both files, so a typo in either would silently desync.

A reviewer (`pattern-recognition-specialist` and `code-quality-analyst`) recommended extracting the contract to a shared TS module:

```ts
// no-transition-contract.ts
export const NO_TRANSITION_STYLE_ID = "__soleur-no-transition";
export const NO_TRANSITION_CSS_TEXT = "* { transition: none !important; ...";
```

Both files now import these. The boot script — which is a `const SCRIPT = \`...\`` template literal rendered as a runtime string — interpolates them at build time:

```ts
s.id = ${JSON.stringify(NO_TRANSITION_STYLE_ID)};
s.textContent = ${JSON.stringify(NO_TRANSITION_CSS_TEXT)};
```

After the refactor, the source-grep test broke:

```
expected 'import { NO_TRANSITION_CSS_TEXT, ... } from "...";\nconst SCRIPT = `...${JSON.stringify(NO_TRANSITION_CSS_TEXT)}...`'
to contain '"* { transition: none !important; animation-duration: 0s !important; }"'
```

`readFileSync` returns the *un-interpolated source* — the `${JSON.stringify(NO_TRANSITION_CSS_TEXT)}` placeholder, not the resolved string. The drift-guard regex was looking for content that no longer exists in the file.

## Root Cause

A source-grep test asserts on **what the editor sees**, not **what the program runs with**. When a build-time mechanism (template-literal interpolation, code generation, macro expansion, `defineConfig({ define: { ... } })`) substitutes values *before* runtime, the source diverges from the runtime string and any source-grep assertion against the post-substitution value silently breaks — even though the runtime behavior is correct.

The class:
- Source-grep tests work when the value lives inline in the file as a string literal.
- Source-grep tests break when the value is referenced by name and resolved at build time.
- The fix is not to revert to inline literals — it is to recognize that the **drift-guard moved from runtime to compile-time**.

## Solution

When refactoring duplicated string literals to shared TS constants:

1. **Drop source-grep tests that assert the literal content.** TypeScript's compile-time identity (`import { X } from "./contract"`) is now the load-bearing drift-guard between files. A typo, rename, or removal of the constant in `no-transition-contract.ts` produces a TS compile error in BOTH consumer files — strictly stronger than a runtime regex.

2. **Replace with edge-asserting tests.** Confirm the import edge survives refactors (so a future inline-literal regression flips back to a real drift surface):

   ```ts
   it("imports the shared contract", () => {
     const src = readScriptSource();
     expect(src).toMatch(/from\s+["']@\/components\/theme\/no-transition-contract["']/);
     expect(src).toContain("NO_TRANSITION_STYLE_ID");
     expect(src).toContain("NO_TRANSITION_CSS_TEXT");
     // Sanity: constants resolve to non-empty values at test time.
     expect(NO_TRANSITION_STYLE_ID.length).toBeGreaterThan(0);
     expect(NO_TRANSITION_CSS_TEXT).toMatch(/transition:\s*none/);
   });
   ```

3. **Keep source-grep tests for content that genuinely cannot live in TS.** Hex literals duplicated from `globals.css` (e.g., `#fbf7ee` for `--soleur-bg-base`) fall in this category — the boot script needs JS strings before stylesheets load, but the canonical source is CSS. The test reads `globals.css`, extracts the value via regex anchored to `:root[data-theme="..."]`, and asserts the script contains it. This is a runtime check that survives refactors because the canonical-source file is the regex target, not the consuming file.

## Key Insight

Drift-guards have two failure modes:
- **Brittleness** — they break on refactors that preserve behavior.
- **Vacuity** — they pass when the actual contract has drifted (the matcher is too permissive).

The fix for brittleness is rarely "revert the refactor." It is to recognize **where the drift surface moved** and route the guard to the new surface. When duplication collapses to shared imports, the drift surface moves from runtime strings to compile-time identifiers; the test should assert on the import edge or rely on the compiler.

## Sharp Edges

- A `${expr}` interpolation in a template-literal SCRIPT does NOT make the resolved value visible to `readFileSync(file)`. The placeholder text is what the file contains.
- TypeScript compile-time identity protects two files from drifting against each other ONLY when both files import from the same source. If one file copies the value (`const X = "literal"`) instead of importing, the contract has degraded to runtime-only and source-grep is the only available guard. Code review should flag any inline copy of a shared-contract constant.
- Hex literals in inline boot scripts are a special case: the script runs before stylesheets load, so it cannot import from CSS at runtime. The drift-guard must read the canonical CSS source and string-match the consumer — the inverse of the import-edge pattern.

## Session Errors

1. **CWD non-persistence on `cd apps/web-platform && vitest run`** — Recovery: switched to absolute-path commands. Prevention: AGENTS.md already documents Bash CWD non-persistence; one-off slip.
2. **Stale `__soleur-no-transition` style leaked across happy-dom tests on the same worker** — Recovery: added `beforeEach` scrub. Prevention: any test file that adds module-level DOM mutators (style-injection, listener-attachment) must clean up in `beforeEach`/`afterEach`. Considered a learning candidate but already covered by the existing `cq-ref-removal-sweep-cleanup-closures` rule's spirit.
3. **`vi.stubGlobal` indirection misdiagnosis** — initially attributed test failure to stub-coverage; real cause was Error #2. Recovery: routed the helper through `globalThis.requestAnimationFrame` defensively (not strictly required but improves test isolation) AND added the leak-scrub. Prevention: when a test failure points at a stubbing mechanism, verify the stub IS receiving calls (e.g., add a counter) before redesigning the helper.
4. **Review-fix regression: 3 tests broke after applying P2 corrections** — Recovery: re-ran the full theme test suite after each fix, identified the two root causes (mount-skip dropped a load-bearing dataset write; source-grep broke on JSON.stringify interpolation), corrected the helper to write data-theme always while skipping the transition-disable on first run, replaced source-grep with import-edge assertion. Prevention: when applying review fixes, re-run not just the failed tests but the full file's suite and the broader-domain suite to catch regressions. Documented in this learning.
5. **Semgrep auto-install failed (no brew/pipx/pip3)** — Recovery: announced the skip explicitly per skill rule; CI gate intact. Prevention: skill rule already covers ("Do NOT silently skip"); the explicit announcement was the correct response. Could update the review skill to allow continuation when the diff has no I/O/auth/network surfaces — but this is contested-design territory; leave as-is for now.
6. **Dev server instrumentation ES-module mismatch** — pre-existing in `apps/web-platform`, blocked automated visual QA. Recovery: documented in QA report; visual scenarios deferred to Phase 5 manual. Prevention: file as a separate issue (out of scope for this PR).

## Prevention

When extracting shared TS constants for build-time interpolation:
- **Audit every existing source-grep test** for the constants being centralized. Each one is a candidate for replacement with an import-edge assertion.
- **Confirm the import edge is actually used** via a complementary assertion that the constant resolves at test time — guards against a refactor that imports without using.
- **Keep the canonical-source-file pattern** for content that genuinely cannot live in TS (CSS variables read by inline JS before stylesheets load).
