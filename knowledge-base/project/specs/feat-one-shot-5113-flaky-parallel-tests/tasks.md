# Tasks — fix flaky full-suite tests under parallel load (#5113)

Plan: `knowledge-base/project/plans/2026-06-10-fix-flaky-parallel-tests-live-repo-badge-signature-verify-plan.md`
Lane: cross-domain (spec lacks `lane:` — defaulted fail-closed)

## Phase 1 — Setup / Reproduction (Phase 0 of plan)

- [ ] 1.1 Baseline isolation check (must be green pre-change):
  - [ ] 1.1.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx` → 5/5
  - [ ] 1.1.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/signature-verify.test.ts test/server/inngest/signature-verify-dev-mode.test.ts` → 6/6
- [ ] 1.2 Best-effort parallel-load reproduction: `cd apps/web-platform && npm run test:ci 2>&1 | tee /tmp/webplat-full-run-1.log`; record error shape (waitFor ~1s timeout for H1; `Test timed out in 16000ms` for H2) in PR body. Non-reproduction does NOT block; a *different* error shape (assertion mismatch) DOES — stop and re-diagnose.

## Phase 2 — Core Implementation

- [ ] 2.1 signature-verify pre-warm (H2):
  - [ ] 2.1.1 `test/server/inngest/signature-verify.test.ts` — add `beforeAll(async () => { await importRoute(); }, 60_000)` inside the describe; import `beforeAll` from vitest; update header comment (lines 17-24) to record the pre-warm.
  - [ ] 2.1.2 `test/server/inngest/signature-verify-dev-mode.test.ts` — same pre-warm; update header comment (lines 15-16).
- [ ] 2.2 live-repo-badge async budgets (H1):
  - [ ] 2.2.1 `test/setup-dom.ts` — add `import { configure } from "@testing-library/react"` + `configure({ asyncUtilTimeout: 10_000 })` with the #5113/#4128 rationale comment.
  - [ ] 2.2.2 `test/live-repo-badge.test.tsx` — add `{ timeout: 10_000 }` to the three `vi.waitFor` calls (lines 37, 108, 114). Do NOT touch test logic, latch resets, or body-settle gating.

## Phase 3 — Verification (Acceptance Criteria)

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (AC6)
- [ ] 3.2 Isolation re-runs green: 5/5 + 6/6 (AC4, AC5)
- [ ] 3.3 Grep gates: AC1 (`beforeAll` + `60_000` in both signature files), AC2 (`timeout: 10_000` ×3), AC3 (`asyncUtilTimeout` in setup-dom.ts)
- [ ] 3.4 Three consecutive `TEST_GROUP=webplat bash scripts/test-all.sh` runs exit 0; log timestamps in PR body (AC7)
- [ ] 3.5 `git diff --name-only origin/main` contains only `apps/web-platform/test/` + `knowledge-base/` paths (AC8)
- [ ] 3.6 PR body uses `Closes #5113` (AC9)
