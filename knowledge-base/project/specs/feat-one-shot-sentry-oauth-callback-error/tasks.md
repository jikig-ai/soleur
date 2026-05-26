---
branch: feat-one-shot-sentry-oauth-callback-error
plan: knowledge-base/project/plans/2026-05-26-fix-sentry-oauth-callback-provider-error-noise-plan.md
lane: single-domain
---

# Tasks: fix OAuth callback provider-error Sentry noise

## Phase 1: Edit callback route

- [x] 1.1 Update import at line 14: add `warnSilentFallback` to the import from `@/server/observability`
- [x] 1.2 Replace `reportSilentFallback` with `warnSilentFallback` at line 82 (the provider-error branch)

## Phase 2: Update test file

- [x] 2.1 Add `mockWarnSilentFallback: vi.fn()` to the `vi.hoisted` block in `callback-route-branches.test.ts`
- [x] 2.2 Add `warnSilentFallback: mockWarnSilentFallback` to the `vi.mock("@/server/observability")` block
- [x] 2.3 Update the 4 provider-error `test.each` cases to assert `mockWarnSilentFallback` instead of `mockReportSilentFallback`
- [x] 2.4 Update the "unrecognized ?error=" test to use `mockWarnSilentFallback`
- [x] 2.5 Update the "refererHost" test to use `mockWarnSilentFallback`
- [x] 2.6 Verify the "searchParamKeys" test remains unchanged (asserts `mockReportSilentFallback` for the `callback_no_code` branch)

## Phase 3: Verify

- [x] 3.1 Run vitest on all 5 auth test files (AC6)
- [x] 3.2 Run TypeScript compile check (AC7)
- [x] 3.3 Run AC1-AC5 verification grep commands
