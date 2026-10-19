---
title: "Tasks: Remove env-allowlist dual-control gate"
date: 2026-05-26
plan: knowledge-base/project/plans/2026-05-26-refactor-remove-env-allowlist-dual-control-plan.md
lane: single-domain
---

# Tasks: Remove env-allowlist dual-control gate

## Phase 1: Core gate simplification

- [x] 1.1 Simplify `isTeamWorkspaceInviteEnabled` in `server.ts` -- remove allowlist check, keep `!orgId` early return
- [x] 1.2 Simplify `isByokDelegationsEnabled` in `server.ts` -- same pattern
- [x] 1.3 Delete `getTeamWorkspaceAllowlist()`, `getByokDelegationsAllowlist()`, `cachedAllowlist`, `cachedByokDelegationsAllowlist`
- [x] 1.4 Update `__resetFeatureFlagsForTests` -- remove allowlist cache resets
- [x] 1.5 Update comment block (lines 14-29) to reflect single-control architecture

## Phase 2: Test updates

- [x] 2.1 Remove `getTeamWorkspaceAllowlist` import from `server.test.ts`
- [x] 2.2 Delete `describe("getTeamWorkspaceAllowlist", ...)` test suite
- [x] 2.3 Rewrite `isTeamWorkspaceInviteEnabled` tests: dual-control -> single-control truth table
- [x] 2.4 Rewrite `isByokDelegationsEnabled` tests: dual-control -> single-control truth table
- [x] 2.5 Verify tests pass: `./node_modules/.bin/vitest run apps/web-platform/lib/feature-flags/server.test.ts`

## Phase 3: Boot breadcrumb simplification

- [x] 3.1 Update `team-workspace-boot.ts`: remove allowlist import + check, update breadcrumb
- [x] 3.2 Update `byok-delegations-boot.ts`: same pattern
- [x] 3.3 Update `team-workspace-boot.test.ts`: remove allowlist env stubs, simplify assertions

## Phase 4: Consumer comment updates

- [x] 4.1 Update comment in `invite-member/route.ts`
- [x] 4.2 Update comment in `settings/team/page.tsx`
- [x] 4.3 Update comment in `team-membership.e2e.ts`
- [x] 4.4 Update comment in `team-membership-resolver.test.ts`

## Phase 5: Consumer test cleanup

- [x] 5.1 Remove `vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ...)` from `team-membership-resolver.test.ts` (6 occurrences)

## Phase 6: Agent env-allowlist test update

- [x] 6.1 Remove `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` from `agent-env-allowlist.test.ts` KEYS_TO_VERIFY + dedicated test case

## Phase 7: Followthrough script deletion

- [x] 7.1 Delete `scripts/followthroughs/team-workspace-flag-flip-4284.sh` (issue #4284 is CLOSED)

## Phase 8: ADR-043 update

- [x] 8.1 Update Consequences section: dual-control -> single-control

## Phase 9: ADR-038 update (deepen-pass discovery)

- [x] 9.1 Update line 42 Decision summary with `[Updated 2026-05-26]` note
- [x] 9.2 Update lines 134-140 Feature-flag section heading + body
- [x] 9.3 Update line 158 Alternatives Considered rejection note

## Phase 10: Final verification

- [x] 10.1 Run full test suite: `./node_modules/.bin/vitest run`
- [x] 10.2 Run TypeScript check: `npx tsc --noEmit`
- [x] 10.3 Verify no stale allowlist references in lib/server: `grep -rn "TEAM_WORKSPACE_ALLOWLIST_ORG_IDS\|BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS\|getTeamWorkspaceAllowlist\|getByokDelegationsAllowlist\|cachedAllowlist\|cachedByokDelegationsAllowlist" apps/web-platform/lib/ apps/web-platform/server/ --include="*.ts" --include="*.tsx"`
- [x] 10.4 Verify no stale allowlist references in test: `grep -rn "TEAM_WORKSPACE_ALLOWLIST_ORG_IDS\|BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS" apps/web-platform/test/ --include="*.ts"`
- [x] 10.5 Verify followthrough script deleted: `test ! -f scripts/followthroughs/team-workspace-flag-flip-4284.sh`
