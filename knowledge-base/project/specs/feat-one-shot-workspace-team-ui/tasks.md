---
plan: knowledge-base/project/plans/2026-05-27-fix-team-workspace-ui-identity-resolver-plan.md
lane: single-domain
---

# Tasks: fix team workspace UI identity resolver query

## Phase 1: Fix the query (identity.ts)

- [ ] 1.1 Read `apps/web-platform/lib/feature-flags/identity.ts`
- [ ] 1.2 Change `.select("organization_id")` to `.select("workspace_id, workspaces!inner(organization_id)")` on the `workspace_members` query
- [ ] 1.3 Update the generic type from `{ organization_id: string }` to `{ workspace_id: string; workspaces: { organization_id: string } }`
- [ ] 1.4 Update the data extraction from `memberData?.organization_id` to `memberData?.workspaces?.organization_id`
- [ ] 1.5 Verify the fix matches the established pattern in `apps/web-platform/server/workspace-resolver.ts` line 161

## Phase 2: Update the test (identity.test.ts)

- [ ] 2.1 Read `apps/web-platform/lib/feature-flags/identity.test.ts`
- [ ] 2.2 Update `fakeSupabase` helper's `workspaceMembersResult` parameter type to use the nested PostgREST response shape
- [ ] 2.3 Update mock data in test "returns orgId from workspace_members when row exists" from `{ organization_id: "org-123" }` to `{ workspace_id: "ws-123", workspaces: { organization_id: "org-123" } }`
- [ ] 2.4 Update the `mockQueryChain` type parameter accordingly
- [ ] 2.5 Run `./node_modules/.bin/vitest run apps/web-platform/lib/feature-flags/identity.test.ts` -- all tests pass
- [ ] 2.6 Run `./node_modules/.bin/vitest run apps/web-platform/test/feature-flag-provider.test.tsx` -- no regression
- [ ] 2.7 Run `./node_modules/.bin/vitest run apps/web-platform/test/team-workspace-boot.test.ts` -- no regression
- [ ] 2.8 Run `./node_modules/.bin/vitest run apps/web-platform/test/team-membership-resolver.test.ts` -- no regression
- [ ] 2.9 Run `npx tsc --noEmit` -- no type errors
