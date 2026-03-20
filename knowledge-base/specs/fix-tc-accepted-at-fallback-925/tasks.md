# Tasks: fix tc_accepted_at fallback unconditional set (#925)

## Phase 1: Implementation

- [ ] 1.1 Read `apps/web-platform/app/(auth)/callback/route.ts`
- [ ] 1.2 In the `GET` handler (line ~26-28), extract `tcAccepted` boolean from `user.user_metadata?.tc_accepted` before calling `ensureWorkspaceProvisioned`
- [ ] 1.3 Add `tcAccepted: boolean` as third parameter to `ensureWorkspaceProvisioned` function signature (line ~53)
- [ ] 1.4 Update the `ensureWorkspaceProvisioned` call site to pass `tcAccepted` (line ~28)
- [ ] 1.5 In the fallback INSERT (line ~73-79), replace unconditional `tc_accepted_at: new Date().toISOString()` with conditional `tc_accepted_at: tcAccepted ? new Date().toISOString() : null`
- [ ] 1.6 Update the comment block (lines 68-71) to note the conditional mirrors trigger logic

## Phase 2: Verification

- [ ] 2.1 Run TypeScript type-check (`npx tsc --noEmit`) to confirm no type errors
- [ ] 2.2 Run existing test suite (`bun test`) to confirm no regressions
- [ ] 2.3 Grep codebase for any other unconditional `tc_accepted_at` writes (confirm none exist beyond the two known paths)

## Phase 3: Ship

- [ ] 3.1 Run `skill: soleur:compound` before commit
- [ ] 3.2 Commit with message: `fix(auth): only set tc_accepted_at in fallback INSERT when metadata confirms acceptance (#925)`
- [ ] 3.3 Push and create PR with `Closes #925` in body
