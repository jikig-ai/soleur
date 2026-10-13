---
title: "Tasks: fix tenant-integration test-suite breakage"
plan: knowledge-base/project/plans/2026-06-15-fix-tenant-integration-test-suite-breakage-plan.md
lane: cross-domain
date: 2026-06-15
---

# Tasks — fix tenant-integration test-suite breakage

Derived from `2026-06-15-fix-tenant-integration-test-suite-breakage-plan.md`. Do NOT touch
account-delete cascade migs 065/066 — verified correct/live, out of scope.

## Phase 0 — Preconditions

- [x] 0.1 Confirm line anchors: `toBe("P0001")` in target test; `ERRCODE = 'insufficient_privilege'` + `REVOKE UPDATE(visibility)` in mig 075.
- [x] 0.2 Enumerate all GoTrue call sites: `createUser`/`deleteUser` in `test/helpers/`, inline `createUser` loops in `*.tenant-isolation.test.ts`, all `signInWithPassword`.
- [x] 0.3 Read `test/helpers/mint-once.ts`; decide whether `withGoTrueRetry` is a new file or folds into mint-once.

## Phase 1 — Fix 1: stale assertion

- [x] 1.1 In `conversation-visibility.tenant-isolation.test.ts` "Non-owner cannot toggle visibility via RPC", change `toBe("P0001")` → `toBe("42501")`.

## Phase 2 — Fix 2: reframe column-REVOKE test

- [x] 2.1 Replace owner-relies-on-REVOKE test with owner-CAN positive control (RLS allows; restore fixture state).
- [x] 2.2 Add non-owner (userB) UPDATE deny: dual-shape (42501 OR 0 rows) + service-role read-back confirms unchanged.
- [x] 2.3 Add anon UPDATE matches-0-rows + read-back unchanged.
- [x] 2.4 Add SOLEUR-DEBT marker (ceiling`;`trigger). **Deviation:** marker placed in the reframed test's AC8 comment block, NOT in mig 075 — editing an already-applied migration's bytes (even a comment) trips the `content_sha` drift probe (dev/prd `_schema_migrations` ledger hash would diverge from origin/main, requiring a prod ledger reconciliation). mig 075 left byte-identical to origin/main.
- [x] 2.5 (Conditional) N/A — went with Option A (debt marker) per plan default; no Option B escalation needed.

## Phase 3 — Fix 3: harness determinism

- [x] 3.1 Add `withGoTrueRetry(label, fn)` using the grounded `isRetryableGoTrueError` predicate (auth-js@2.99.2: `status===429` | `code ∈ over_*_rate_limit` | `/rate limit|too many requests/i` | `/database error deleting user/i`); bounded exp-backoff+jitter under hookTimeout(20s); rethrow non-rate-limit errors.
- [x] 3.2 Wrap: `createUser` (workspace-members-fixtures:80), `deleteUser` (workspace-members-fixtures:173 + tenant-isolation-teardown:94), `signInWithPassword` (target test ×3).
- [x] 3.3 Update `test/README.md`: dedicated-project requirement for behavioral suites (both env conventions); add conversation-visibility suite row + run command.

## Phase 4 — Verify

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] 4.2 No-env-flag `vitest run` of target file skips cleanly (no failures).
- [x] 4.3 Ran ×1 against live dev (`SUPABASE_DEV_INTEGRATION=1`): 11/11 pass (was 2/9 failing pre-fix). Full web-platform vitest suite: 10115 passed / 0 failed. The stricter ×2-on-dedicated-project determinism check remains the post-merge form (rate-limit-heavy full batch).
