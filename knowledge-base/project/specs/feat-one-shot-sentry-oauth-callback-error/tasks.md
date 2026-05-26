---
branch: feat-one-shot-sentry-oauth-callback-error
plan: knowledge-base/project/plans/2026-05-26-fix-sentry-oauth-callback-provider-error-noise-plan.md
lane: single-domain
---

# Tasks: fix OAuth callback provider-error Sentry noise

## Phase 1: Edit callback route

- [ ] 1.1 Update import at line 14: add `warnSilentFallback` to the import from `@/server/observability`
- [ ] 1.2 Replace `reportSilentFallback` with `warnSilentFallback` at line 82 (the provider-error branch)

## Phase 2: Update test file

- [ ] 2.1 Add `mockWarnSilentFallback: vi.fn()` to the `vi.hoisted` block in `callback-route-branches.test.ts`
- [ ] 2.2 Add `warnSilentFallback: mockWarnSilentFallback` to the `vi.mock("@/server/observability")` block
- [ ] 2.3 Update the 4 provider-error `test.each` cases to assert `mockWarnSilentFallback` instead of `mockReportSilentFallback`
- [ ] 2.4 Update the "unrecognized ?error=" test to use `mockWarnSilentFallback`
- [ ] 2.5 Update the "refererHost" test to use `mockWarnSilentFallback`
- [ ] 2.6 Verify the "searchParamKeys" test remains unchanged (asserts `mockReportSilentFallback` for the `callback_no_code` branch)

## Phase 3: Verify

- [ ] 3.1 Run vitest on all 5 auth test files (AC6)
- [ ] 3.2 Run TypeScript compile check (AC7)
- [ ] 3.3 Run AC1-AC5 verification grep commands
