---
title: "Tasks — fix web-platform test flake (forks-default + signature-verify split + pdfjs pre-warm)"
date: 2026-05-19
type: fix
status: planning
lane: single-domain
branch: feat-fix-web-platform-tests-3817
worktree: .worktrees/feat-fix-web-platform-tests-3817/
issue: 3817
pr: 4097
plan: knowledge-base/project/plans/2026-05-19-fix-web-platform-test-flake-forks-default-plan.md
---

# Tasks — fix web-platform test flake

Derived from `knowledge-base/project/plans/2026-05-19-fix-web-platform-test-flake-forks-default-plan.md`.

## Phase 0: Pre-flight

- [ ] 0.1 — Verify CWD is the worktree: `pwd` returns `.worktrees/feat-fix-web-platform-tests-3817`
- [ ] 0.2 — Verify branch: `git branch --show-current` returns `feat-fix-web-platform-tests-3817`
- [ ] 0.3 — Verify the four read-target files exist with expected lines:
  - `apps/web-platform/vitest.config.ts:14-15` contains `WEBPLAT_TEST_USE_FORKS === "1" ? "forks" : undefined`
  - `apps/web-platform/test/server/inngest/signature-verify.test.ts:32` contains `vi.resetModules();`
  - `apps/web-platform/test/server/inngest/signature-verify.test.ts:76` contains `ROUTE_LOAD_TIMEOUT_MS = 15_000;`
  - `apps/web-platform/test/kb-document-resolver-pdf-page-gate.test.ts:63` contains `vi.mock("@/server/pdf-text-extract"`
  - `apps/web-platform/test/leader-document-resolver.test.ts:68` contains `vi.mock("@/server/pdf-text-extract"`
- [ ] 0.4 — Capture baseline: `cd apps/web-platform && bun run test:ci 2>&1 | tail -5` — record passing/failing counts.

## Phase 1: Fix 1 — Forks by default

- [ ] 1.1 — Edit `apps/web-platform/vitest.config.ts` lines 7-15: rewrite doc-comment to reflect forks-by-default + `WEBPLAT_TEST_USE_THREADS` opt-out (canonical wording per plan Fix 1 "After" block).
- [ ] 1.2 — Edit `apps/web-platform/vitest.config.ts` lines 14-15: flip selector to `process.env.WEBPLAT_TEST_USE_THREADS === "1" ? undefined : "forks"`.
- [ ] 1.3 — Verify: `grep -F "Default on" apps/web-platform/vitest.config.ts` returns 1 match; `grep -F "WEBPLAT_TEST_USE_THREADS" apps/web-platform/vitest.config.ts` returns ≥1 match; `grep -cF "Default off" apps/web-platform/vitest.config.ts` returns 0.
- [ ] 1.4 — RED→GREEN gate: `cd apps/web-platform && bun run test:ci` reports zero failing files (or the same as baseline pre-Fix 2 — Fix 1 alone should close the bulk of the 51-failure pattern).

## Phase 2: Fix 2 — Split signature-verify

- [ ] 2.1 — Edit `apps/web-platform/test/server/inngest/signature-verify.test.ts`:
  - 2.1.1 — Replace lines 17-49 (`ORIGINAL_ENV` capture + `restoreEnv` helper + `beforeEach`/`afterEach` block) with file-scope `process.env.X =` writes for `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, `INNGEST_DEV` (canonical block per plan Fix 2).
  - 2.1.2 — Drop the `afterEach` import from the top-of-file vitest import list (no longer used).
  - 2.1.3 — Drop the `vi.resetModules();` call (was line 32).
  - 2.1.4 — Delete lines 69-76 (`ROUTE_LOAD_TIMEOUT_MS` constant + its preceding doc-comment).
  - 2.1.5 — Remove `ROUTE_LOAD_TIMEOUT_MS` trailing argument from all 5 cloud-mode `it(...)` calls (lines 87, 97, 110, 126, 144).
  - 2.1.6 — Delete lines 161-177 (the entire `it #6` mode-flip test + its doc-comment). The closing `});` for the `describe(...)` should remain.
- [ ] 2.2 — Create `apps/web-platform/test/server/inngest/signature-verify-dev-mode.test.ts` with the contents per plan Fix 2's canonical block (file-scope env + `importRoute` helper + `makePostRequest` helper + single `it` asserting `res.status !== 401`).
- [ ] 2.3 — Verify file-by-file:
  - 2.3.1 — `grep -cE 'vi\.resetModules|ROUTE_LOAD_TIMEOUT_MS|15_000' apps/web-platform/test/server/inngest/signature-verify.test.ts apps/web-platform/test/server/inngest/signature-verify-dev-mode.test.ts` returns 0 for every line.
  - 2.3.2 — `grep -E '^process\.env\.INNGEST_DEV' apps/web-platform/test/server/inngest/signature-verify.test.ts` returns `process.env.INNGEST_DEV = "0";`.
  - 2.3.3 — `grep -E '^process\.env\.INNGEST_DEV' apps/web-platform/test/server/inngest/signature-verify-dev-mode.test.ts` returns `process.env.INNGEST_DEV = "1";`.
- [ ] 2.4 — RED→GREEN gate (file-level):
  - 2.4.1 — `cd apps/web-platform && bun test test/server/inngest/signature-verify.test.ts` passes 5/5 in <8s wall-clock.
  - 2.4.2 — `cd apps/web-platform && bun test test/server/inngest/signature-verify-dev-mode.test.ts` passes 1/1 in <6s wall-clock.

## Phase 3: Fix 3 — Pre-warm pdfjs in two flaky files

- [ ] 3.1 — Edit `apps/web-platform/test/kb-document-resolver-pdf-page-gate.test.ts`:
  - 3.1.1 — Add `beforeAll` to the existing `import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";` import line (alphabetical placement OK).
  - 3.1.2 — Inside the `describe(...)` at line 102, as the FIRST statement (before any `beforeEach`/`it`), add:
    ```ts
    beforeAll(async () => {
      await import("pdfjs-dist/legacy/build/pdf.mjs");
    }, 30_000);
    ```
    with a 3-line doc-comment citing the precedent and the cold-load amortization rationale.
- [ ] 3.2 — Edit `apps/web-platform/test/leader-document-resolver.test.ts`: same shape, inside the `describe(...)` at line 108.
- [ ] 3.3 — Verify:
  - 3.3.1 — `grep -A2 "beforeAll(async" apps/web-platform/test/kb-document-resolver-pdf-page-gate.test.ts | grep -F 'import("pdfjs-dist/legacy/build/pdf.mjs")'` returns ≥1 match.
  - 3.3.2 — Same for `leader-document-resolver.test.ts`.
- [ ] 3.4 — RED→GREEN gate (file-level):
  - 3.4.1 — `cd apps/web-platform && bun test test/kb-document-resolver-pdf-page-gate.test.ts` passes; first-test cold-load is amortized.
  - 3.4.2 — `cd apps/web-platform && bun test test/leader-document-resolver.test.ts` passes.

## Phase 4: Full-harness verification

- [ ] 4.1 — `cd apps/web-platform && bun run test:ci` passes green twice in a row from a clean checkout. AC1.
- [ ] 4.2 — `cd apps/web-platform && WEBPLAT_TEST_USE_THREADS=1 bun run test:ci` runs to completion (opt-out path works; flake-class failures may surface but the wiring is verified). AC2.
- [ ] 4.3 — `cd .. && bash scripts/test-all.sh` (from worktree root) reports zero failures in the `apps/web-platform` suite, twice in a row. AC3.

## Phase 5: PR finalization

- [ ] 5.1 — Update PR #4097 body: replace the WIP stub with the canonical PR body, containing `Closes #3817` and `Closes #3818` on separate lines. AC10.
- [ ] 5.2 — Run `/soleur:compound` skill to capture any new session learnings (e.g., the module-init env-capture finding documented in plan's Enhancement Summary).
- [ ] 5.3 — Run plan-review pass (`/soleur:plan-review` or 3-agent parallel) if not already done.
- [ ] 5.4 — Convert PR from draft to ready: `gh pr ready 4097`.
- [ ] 5.5 — Enable auto-merge: `gh pr merge 4097 --squash --auto`.

## Phase 6: Post-merge verification

- [ ] 6.1 — After merge, `gh issue close 3818` (the strict subset is closed by `Closes #3818`; this is a no-op confirmation).
- [ ] 6.2 — After merge, `gh issue close 3817` (same — auto-closed by `Closes #3817`).
- [ ] 6.3 — Run the next `bash scripts/test-all.sh` on `main` post-merge; confirm the 51-failure pattern is gone (record outcome in the PR's post-merge comment).

## Out of Scope

- No vitest sequencer changes.
- No pool-thread-count tuning.
- No component source-file edits.
- No `WEBPLAT_TEST_FAILURES_LOG` log addition to `scripts/test-all.sh` (per non-goal in plan).
- No documentation of the `WEBPLAT_TEST_USE_THREADS` env var in operator-facing docs — it's a diagnostic-only flag; the in-file doc-comment is the single source of truth.
