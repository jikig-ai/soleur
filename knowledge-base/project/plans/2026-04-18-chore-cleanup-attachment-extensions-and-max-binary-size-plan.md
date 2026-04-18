# Cleanup: inline ATTACHMENT_EXTENSIONS + import MAX_BINARY_SIZE in tests

- **Issue:** #2325
- **Branch:** `feat-one-shot-2325-cleanup-attachment-extensions`
- **Priority:** P3 (low)
- **Type:** chore / refactor
- **Milestone:** Phase 3: Make it Sticky

## Enhancement Summary

**Deepened on:** 2026-04-18
**Depth applied:** proportional — this is a 2-line refactor, so the parallel-agent-army deepening pattern was deliberately skipped. Focused verification instead.

### Verified facts (from grep sweep against the worktree)

- `ATTACHMENT_EXTENSIONS` has **exactly 2 in-code references**, both in `apps/web-platform/server/kb-binary-response.ts` (line 36 definition, line 143 usage). Nothing imports it. Safe to inline without touching any other file.
- `MAX_BINARY_SIZE` is imported by three production modules today: `server/agent-runner.ts:45`, `server/kb-share.ts:20`, and (jsdoc-only) `server/kb-reader.ts:265`. The test file change adds a fourth importer — entirely additive.
- Prior plans (`2026-04-17-refactor-kb-serve-binary-helpers`, `2026-04-17-feat-agent-user-parity-kb-share`) already deferred #2300 with the same rationale used here. Acknowledge-and-defer is the established repo pattern for #2300, so the disposition in this plan is consistent, not ad-hoc.

### No new considerations

The original plan captured the full scope. Only line-number reconciliation (line 22 → 36, line 162 → 144) was required, and that was already folded into the Research Reconciliation table.

## Overview

Two minor cleanups in the KB binary response module and its tests:

1. Remove speculative generality from `ATTACHMENT_EXTENSIONS = new Set([".docx"])` in `apps/web-platform/server/kb-binary-response.ts:36`. A `Set` with a single element is overkill; inline as `ext === ".docx"` at the single call site (line 143).
2. Replace the hardcoded `50 * 1024 * 1024 + 1` literal in `apps/web-platform/test/kb-share-allowed-paths.test.ts:144` with `MAX_BINARY_SIZE + 1` imported from `@/server/kb-binary-response`. The current literal silently decouples from the source constant; if `MAX_BINARY_SIZE` ever changes, the boundary test keeps passing with a stale threshold.

Trivial, low-risk, no behavior change.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2325) | Codebase reality | Plan response |
|---|---|---|
| `ATTACHMENT_EXTENSIONS = new Set([".docx"])` at `kb-binary-response.ts:22` | Actually at line 36 (file has grown) | Use line 36 in implementation; single call site at line 143. |
| Hardcoded 50MB literal in test at line 162 | Actually at line 144 (`Buffer.alloc(50 * 1024 * 1024 + 1)`) | Use line 144 in implementation. |
| Issue proposes "either inline OR add a doc-comment" | Inlining is simpler and aligns with the single-call-site reality | Choose inlining. |

No fictional infrastructure. Issue prose is accurate; only line numbers drifted.

## Open Code-Review Overlap

Two open code-review issues touch `kb-binary-response.ts`:

- **#2300** — `arch: move MAX_BINARY_SIZE out of kb-binary-response.ts into kb-limits.ts`. **Disposition: Acknowledge (defer).** #2300 is an architectural refactor that extracts a new `kb-limits.ts` module for policy constants. #2325 is a trivial 2-line simplification; folding #2300 in would blow up scope (new file, rewire imports across share route + binary response). Inlining `ATTACHMENT_EXTENSIONS` in this PR actually *reduces* the surface #2300 has to move (one fewer constant). The test-side change in #2325 imports `MAX_BINARY_SIZE` from `kb-binary-response` — once #2300 lands, a one-line import path update from `@/server/kb-binary-response` → `@/server/kb-limits` is all that will be needed. #2300 remains open and tracked.
- **#2297** — `arch: unify file-kind classification across owner and shared viewer pages`. **Disposition: Acknowledge.** Different concern (file-kind unification across viewer pages), does not touch the 2 lines in scope.

## Files to Edit

- `apps/web-platform/server/kb-binary-response.ts` — delete line 36 (`export const ATTACHMENT_EXTENSIONS = new Set([".docx"]);`), replace line 143 (`const disposition = ATTACHMENT_EXTENSIONS.has(ext) ? "attachment" : "inline";`) with `const disposition = ext === ".docx" ? "attachment" : "inline";`.
- `apps/web-platform/test/kb-share-allowed-paths.test.ts` — add `MAX_BINARY_SIZE` to the existing `@/server/kb-binary-response` import (or create a new import line if none exists yet — current test file does NOT import from that module, so add `import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";` near the top). Replace line 144 (`const big = Buffer.alloc(50 * 1024 * 1024 + 1);`) with `const big = Buffer.alloc(MAX_BINARY_SIZE + 1);`.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Inline `ATTACHMENT_EXTENSIONS`

1. Edit `apps/web-platform/server/kb-binary-response.ts`:
   - Delete line 36: `export const ATTACHMENT_EXTENSIONS = new Set([".docx"]);`
   - On line 143, replace `ATTACHMENT_EXTENSIONS.has(ext)` with `ext === ".docx"`.
2. Grep to confirm no other consumers:

   ```bash
   rg "ATTACHMENT_EXTENSIONS" apps/ plugins/ --type ts --type tsx
   ```

   Expected: zero matches after the edit.

### Phase 2 — Import `MAX_BINARY_SIZE` in the test

1. Edit `apps/web-platform/test/kb-share-allowed-paths.test.ts`:
   - Add near the other `@/` imports (around line 47 where `@/app/api/kb/share/route` is imported):

     ```ts
     import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";
     ```

   - Replace line 144 `Buffer.alloc(50 * 1024 * 1024 + 1)` with `Buffer.alloc(MAX_BINARY_SIZE + 1)`.

### Phase 3 — Verify

1. Run the affected test file from `apps/web-platform`:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-share-allowed-paths.test.ts
   ```

   Expected: all tests green, including `"rejects oversize files with 413"`.
2. Run `tsc --noEmit` to catch any type regression:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/tsc --noEmit
   ```

3. Run the broader binary-response test suite to confirm the inlining did not break the single call site:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-binary-response*.test.ts
   ```

## Acceptance Criteria

- [x] `ATTACHMENT_EXTENSIONS` symbol deleted from `apps/web-platform/server/kb-binary-response.ts`.
- [x] The single call site (formerly line 143) uses `ext === ".docx"` directly.
- [x] `rg ATTACHMENT_EXTENSIONS apps/ plugins/` returns zero matches.
- [x] `apps/web-platform/test/kb-share-allowed-paths.test.ts` imports `MAX_BINARY_SIZE` from `@/server/kb-binary-response`.
- [x] The oversize test uses `Buffer.alloc(MAX_BINARY_SIZE + 1)` — no `50 * 1024 * 1024` literal remains in that test file.
- [x] `vitest run test/kb-share-allowed-paths.test.ts` passes.
- [x] `tsc --noEmit` is clean.
- [x] No other behavior or exports change (diff is strictly the two identified edits).

## Test Scenarios

The existing test suite covers the behavior; no new tests are required (it's a pure refactor). The oversize test remains the boundary test but now reflects the true source-of-truth constant:

- `"rejects oversize files with 413"` — still passes with `MAX_BINARY_SIZE + 1`. If `MAX_BINARY_SIZE` changes in the future, the test automatically tracks it.

## Risks

- **Trivial.** The `Set.has` → `===` change is semantically identical for the single element case.
- **Import surface.** The new `MAX_BINARY_SIZE` import in the test creates a dependency edge from the test file onto the server module. Acceptable — the constant is already exported and used by `app/api/kb/share/route.ts`.
- **Future #2300 compatibility.** If/when #2300 moves `MAX_BINARY_SIZE` to `kb-limits.ts`, the test import path will need a one-line update. Noted in the Open Code-Review Overlap section above.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal code cleanup with no user-facing change, no new dependencies, no security/legal/product implications. Pure engineering chore (2-line refactor + 1 test tidy-up) already scoped and severity-tagged by the original reviewer.

## PR Body Reminder

When creating the PR, use:

```text
Closes #2325

Ref #2300 — inlining ATTACHMENT_EXTENSIONS reduces the surface #2300 will move to kb-limits.ts.
```

## Notes

- This is an ideal `soleur:one-shot` candidate: trivial diff, pre-existing test coverage, no UX surface.
- Do NOT fold in #2300 — different scope, different review lens.
