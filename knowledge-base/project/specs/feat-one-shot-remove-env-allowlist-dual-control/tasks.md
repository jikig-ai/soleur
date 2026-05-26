---
title: "Tasks: Remove env-allowlist dual-control gate"
date: 2026-05-26
plan: knowledge-base/project/plans/2026-05-26-refactor-remove-env-allowlist-dual-control-plan.md
lane: single-domain
---

# Tasks: Remove env-allowlist dual-control gate

## Phase 1: Core gate simplification

- [ ] 1.1 Simplify `isTeamWorkspaceInviteEnabled` in `server.ts` -- remove allowlist check, keep `!orgId` early return
- [ ] 1.2 Simplify `isByokDelegationsEnabled` in `server.ts` -- same pattern
- [ ] 1.3 Delete `getTeamWorkspaceAllowlist()`, `getByokDelegationsAllowlist()`, `cachedAllowlist`, `cachedByokDelegationsAllowlist`
- [ ] 1.4 Update `__resetFeatureFlagsForTests` -- remove allowlist cache resets
- [ ] 1.5 Update comment block (lines 14-29) to reflect single-control architecture

## Phase 2: Test updates

- [ ] 2.1 Remove `getTeamWorkspaceAllowlist` import from `server.test.ts`
- [ ] 2.2 Delete `describe("getTeamWorkspaceAllowlist", ...)` test suite
- [ ] 2.3 Rewrite `isTeamWorkspaceInviteEnabled` tests: dual-control -> single-control truth table
- [ ] 2.4 Rewrite `isByokDelegationsEnabled` tests: dual-control -> single-control truth table
- [ ] 2.5 Verify tests pass: `./node_modules/.bin/vitest run apps/web-platform/lib/feature-flags/server.test.ts`

## Phase 3: Boot breadcrumb simplification

- [ ] 3.1 Update `team-workspace-boot.ts`: remove allowlist import + check, update breadcrumb
- [ ] 3.2 Update `byok-delegations-boot.ts`: same pattern
- [ ] 3.3 Update `team-workspace-boot.test.ts`: remove allowlist env stubs, simplify assertions

## Phase 4: Consumer comment updates

- [ ] 4.1 Update comment in `invite-member/route.ts`
- [ ] 4.2 Update comment in `settings/team/page.tsx`
- [ ] 4.3 Update comment in `team-membership.e2e.ts`
- [ ] 4.4 Update comment in `team-membership-resolver.test.ts`

## Phase 5: Consumer test cleanup

- [ ] 5.1 Remove `vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ...)` from `team-membership-resolver.test.ts` (6 occurrences)

## Phase 6: Agent env-allowlist test update

- [ ] 6.1 Remove `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` from `agent-env-allowlist.test.ts` KEYS_TO_VERIFY + dedicated test case

## Phase 7: Followthrough script deletion

- [ ] 7.1 Delete `scripts/followthroughs/team-workspace-flag-flip-4284.sh` (issue #4284 is CLOSED)

## Phase 8: ADR-043 update

- [ ] 8.1 Update Consequences section: dual-control -> single-control

## Phase 9: ADR-038 update (deepen-pass discovery)

- [ ] 9.1 Update line 42 Decision summary with `[Updated 2026-05-26]` note
- [ ] 9.2 Update lines 134-140 Feature-flag section heading + body
- [ ] 9.3 Update line 158 Alternatives Considered rejection note

## Phase 10: Final verification

- [ ] 10.1 Run full test suite: `./node_modules/.bin/vitest run`
- [ ] 10.2 Run TypeScript check: `npx tsc --noEmit`
- [ ] 10.3 Verify no stale allowlist references in lib/server: `grep -rn "TEAM_WORKSPACE_ALLOWLIST_ORG_IDS\|BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS\|getTeamWorkspaceAllowlist\|getByokDelegationsAllowlist\|cachedAllowlist\|cachedByokDelegationsAllowlist" apps/web-platform/lib/ apps/web-platform/server/ --include="*.ts" --include="*.tsx"`
- [ ] 10.4 Verify no stale allowlist references in test: `grep -rn "TEAM_WORKSPACE_ALLOWLIST_ORG_IDS\|BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS" apps/web-platform/test/ --include="*.ts"`
- [ ] 10.5 Verify followthrough script deleted: `test ! -f scripts/followthroughs/team-workspace-flag-flip-4284.sh`
