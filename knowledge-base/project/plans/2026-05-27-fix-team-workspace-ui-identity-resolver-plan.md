---
title: "fix: team workspace UI not showing due to broken identity resolver query"
type: fix
date: 2026-05-27
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
---

# fix: team workspace UI not showing due to broken identity resolver query

## Overview

The team workspace feature (`FLAG_TEAM_WORKSPACE_INVITE`) was enabled on the jikigai org but the Settings page does not show the "Members" tab or any team/workspace UI. Tested with `ops@jikigai.com` -- the Settings page shows Account, Project, API Key, and Privacy sections only.

**Root cause:** `apps/web-platform/lib/feature-flags/identity.ts` queries `workspace_members.organization_id` -- a column that does not exist on the `workspace_members` table. The `organization_id` column lives on the `workspaces` table (migration 053). PostgREST returns an error for the non-existent column, the destructured `data` is null, and `orgId` resolves to `null`.

With `orgId === null`:

1. **Root layout (`app/layout.tsx`) and `/api/flags` route:** `resolveIdentity()` returns `{ ..., orgId: null }`. The `getFeatureFlags(identity)` call sends Flagsmith identity `role:prd` (no org context). The `org-targeted` segment rule (`orgId IN [jikigai-org-id]`) does not match. `team-workspace-invite` evaluates to `false` everywhere in the client-side `FeatureFlagProvider` and the flags API response.

2. **Settings layout (`settings/layout.tsx`):** Uses a separate path reading `orgId` from the JWT `app_metadata.current_organization_id` claim (migration 060). This path DOES have the correct `orgId` from the JWT. However, it calls `isTeamWorkspaceInviteEnabled(orgId, identity)` which sends the correct org context to Flagsmith. This path should work IF: (a) migration 060 `user_session_state` was backfilled for the user, AND (b) the user has refreshed their session since migration 060 applied, AND (c) Flagsmith is reachable and the segment is configured. But even if this path works, the `FeatureFlagProvider` at the root layout level has `team-workspace-invite: false` because `identity.ts` broke the orgId resolution.

**The fix is a one-line query correction** in `identity.ts`: use PostgREST's embedded-resource join syntax to resolve `organization_id` through the `workspaces` table, matching the established pattern in `workspace-resolver.ts` line 161.

## Research Reconciliation -- Spec vs. Codebase

| Spec/Brainstorm Claim | Codebase Reality | Plan Response |
|---|---|---|
| `workspace_members` has `organization_id` | Column is on `workspaces`, not `workspace_members` (migration 053 lines 80-94) | Fix query with PostgREST join |
| `resolveIdentity` returns orgId for authenticated users | Returns `null` for all users because query fails silently | Root cause of the UI bug |
| Settings layout has independent orgId resolution via JWT claim | Confirmed -- `getCurrentOrganizationId` reads `app_metadata.current_organization_id` from JWT (migration 060) | Even if settings layout works, root-level `FeatureFlagProvider` is broken |

## User-Brand Impact

- **If this lands broken, the user experiences:** Team workspace features (Members tab, invite flow, member list) remain invisible despite the flag being enabled for their organization. Operator cannot onboard team members.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A -- this is a broken query returning null, not an authorization bypass. The failure mode is denial of service (feature not visible), not data exposure.
- **Brand-survival threshold:** `single-user incident` -- inherited from the team-workspace-multi-user brainstorm. The underlying feature surface (`FLAG_TEAM_WORKSPACE_INVITE`) gates access to workspace membership data; a fix that accidentally widens the query scope (e.g., returning another org's ID) would be a cross-tenant authorization bug.

## Observability

```yaml
liveness_signal:
  what: "Settings layout resolveMembersTab returns non-null for jikigai org users"
  cadence: "per-request (server component render)"
  alert_target: "Sentry web-platform via SENTRY_DSN"
  configured_in: "apps/web-platform/server/team-workspace-boot.ts (breadcrumb emission)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "resolveIdentity returns orgId: null for authenticated users who have workspace memberships -- silent fallback logged via reportSilentFallback if Flagsmith errors"

failure_modes:
  - mode: "PostgREST query error on workspace_members join (schema mismatch)"
    detection: "Sentry error from supabase client; orgId null for all users in feature-flag identity"
    alert_route: "Sentry web-platform project alerts"
  - mode: "Flagsmith unreachable -- env-var fallback kicks in"
    detection: "reportSilentFallback breadcrumb in Sentry (feature: feature-flags, op: flagsmith.getIdentityFlags)"
    alert_route: "Sentry web-platform project alerts"

logs:
  where: "Sentry breadcrumbs (feature-flag category) + Next.js server logs"
  retention: "Sentry 90d retention; server logs per deployment platform"

discoverability_test:
  command: "grep -n 'organization_id' apps/web-platform/lib/feature-flags/identity.ts"
  expected_output: "Line showing .select('workspace_id, workspaces!inner(organization_id)') with embedded-resource join syntax"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `apps/web-platform/lib/feature-flags/identity.ts` query uses PostgREST embedded-resource join: `.select("workspace_id, workspaces!inner(organization_id)")` instead of `.select("organization_id")` on `workspace_members`
- [ ] **AC2:** The `memberData` destructure correctly extracts `organization_id` from the nested `workspaces` object in the PostgREST response (shape: `{ workspace_id: string, workspaces: { organization_id: string } }`)
- [ ] **AC3:** `apps/web-platform/lib/feature-flags/identity.test.ts` mock is updated to reflect the correct PostgREST response shape (nested `workspaces` object) and the test still passes
- [ ] **AC4:** Existing tests pass: `./node_modules/.bin/vitest run apps/web-platform/lib/feature-flags/identity.test.ts`
- [ ] **AC5:** `./node_modules/.bin/vitest run apps/web-platform/test/feature-flag-provider.test.tsx` passes (no regression)
- [ ] **AC6:** `./node_modules/.bin/vitest run apps/web-platform/test/team-workspace-boot.test.ts` passes (no regression)
- [ ] **AC7:** `./node_modules/.bin/vitest run apps/web-platform/test/team-membership-resolver.test.ts` passes (no regression)
- [ ] **AC8:** TypeScript type-check passes: `npx tsc --noEmit` (no type errors from the query shape change)

### Post-merge (operator)

- [ ] **AC9:** After merge and deploy, log into the web platform as `ops@jikigai.com` and verify the Settings sidebar shows a "Members" tab. Automation: navigate to `/dashboard/settings` via Playwright MCP and verify the "Members" link is present in the sidebar nav.
- [ ] **AC10:** Clicking "Members" navigates to `/dashboard/settings/team` and shows the team membership list. Automation: Playwright MCP click on "Members" link, verify page contains "Team" heading and "Members" subheading.

## Test Scenarios

- Given an authenticated user with a workspace membership, when `resolveIdentity` is called, then `orgId` is the `organization_id` of the user's workspace's organization (not null)
- Given an authenticated user with no workspace membership rows, when `resolveIdentity` is called, then `orgId` is null (graceful fallback)
- Given an anonymous/unauthenticated request, when `resolveIdentity` is called, then ANON_IDENTITY is returned with `orgId: null`
- Given the PostgREST join query returns an error, when `resolveIdentity` processes the response, then `orgId` falls back to null (no crash)

## Files to Edit

1. `apps/web-platform/lib/feature-flags/identity.ts` -- Fix the query from `.select("organization_id")` to `.select("workspace_id, workspaces!inner(organization_id)")` and update the response type extraction
2. `apps/web-platform/lib/feature-flags/identity.test.ts` -- Update mock data shape to match the PostgREST embedded-resource response (`{ workspace_id: "...", workspaces: { organization_id: "..." } }`)

## Files to Create

None.

## Open Code-Review Overlap

None -- no open code-review issues touch `apps/web-platform/lib/feature-flags/identity.ts` or `apps/web-platform/lib/feature-flags/identity.test.ts`.

## Implementation Phases

### Phase 1: Fix the query (identity.ts)

1. Read `apps/web-platform/lib/feature-flags/identity.ts`
2. Change line 22-26 from:
   ```typescript
   const { data: memberData } = await supabase
     .from("workspace_members")
     .select("organization_id")
     .eq("user_id", userId)
     .limit(1)
     .single<{ organization_id: string }>();

   const orgId = memberData?.organization_id ?? null;
   ```
   to:
   ```typescript
   const { data: memberData } = await supabase
     .from("workspace_members")
     .select("workspace_id, workspaces!inner(organization_id)")
     .eq("user_id", userId)
     .limit(1)
     .single<{ workspace_id: string; workspaces: { organization_id: string } }>();

   const orgId = memberData?.workspaces?.organization_id ?? null;
   ```
3. This matches the established PostgREST embedded-resource join pattern used in `apps/web-platform/server/workspace-resolver.ts` line 161.

### Phase 2: Update the test (identity.test.ts)

1. Read `apps/web-platform/lib/feature-flags/identity.test.ts`
2. Update the `fakeSupabase` helper's `workspaceMembersResult` parameter type and the mock data shapes in test cases to use the nested PostgREST response shape:
   - Change `{ organization_id: "org-123" }` to `{ workspace_id: "ws-123", workspaces: { organization_id: "org-123" } }`
   - Update the type annotation from `{ organization_id: string }` to `{ workspace_id: string; workspaces: { organization_id: string } }`
3. Run the test suite to verify all tests pass.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| PostgREST embedded-resource join on `workspace_members → workspaces` requires RLS SELECT on both tables | Low (RLS policies for both tables exist per migration 053) | Feature stays broken | Verified: `workspaces_select_for_members` policy exists (migration 053 line 169-171); `workspace_members` has `members_select_peers` policy (line 173-175) |
| Response shape mismatch (PostgREST returns array vs object for `workspaces`) | Low (using `!inner` forces exactly-one join) | Runtime error extracting orgId | The `!inner` modifier ensures the join is required (no null result for the nested object) per PostgREST semantics. `.single()` on the outer query ensures exactly one row |
| Supabase client version incompatibility with embedded-resource syntax | Very low (same syntax used successfully at `workspace-resolver.ts:161`) | Query fails | Confirmed: supabase-js client already uses this pattern in production code |

## Sharp Edges

- The fix MUST use `!inner` in the embedded resource syntax (`.select("workspace_id, workspaces!inner(organization_id)")`) to match the `INNER JOIN` semantics. Without `!inner`, PostgREST uses a LEFT JOIN, which could return a row with `workspaces: null` for orphaned workspace_members rows (integrity violation but defensively handled).
- The `.single()` call returns the FIRST matching row. For users with multiple workspace memberships, this returns an arbitrary org. This matches the pre-existing behavior (the broken query also used `.limit(1).single()`). The "correct" org resolution lives in the JWT claim path (`getCurrentOrganizationId`), not in `resolveIdentity`. The identity resolver is the fallback for the root-layout FeatureFlagProvider.
- **JWT claim dependency (pre-existing):** For the "Members" tab to appear, BOTH the root layout's `resolveIdentity` path (DB query, fixed by this plan) AND the settings layout's `getCurrentOrganizationId` path (JWT `app_metadata.current_organization_id`, migration 060) must succeed. If a user has not refreshed their session since migration 060 applied, the JWT claim may be absent and the settings layout will return null for `membersTab` even though the root layout's flag evaluation is now correct. This is a pre-existing propagation concern, not introduced by this fix. Mitigation: user refreshes their session (login/logout cycle or `supabase.auth.refreshSession()`).

## Alternative Approaches Considered

| Approach | Rejected Because |
|---|---|
| Read orgId from JWT claims in `resolveIdentity` (same as settings layout) | `resolveIdentity` is called from the root `app/layout.tsx` which creates a fresh Supabase client; the auth session may not be available yet at that point. The DB query is the established pattern. |
| Add `organization_id` column to `workspace_members` table | Denormalization; `organization_id` correctly lives on `workspaces` per the schema design. Adding a redundant column creates a data consistency risk. |
| Remove the orgId from identity resolution entirely and rely only on JWT claims | Would require refactoring all callers of `resolveIdentity` and `getFeatureFlags`. The root layout's FeatureFlagProvider needs org context to evaluate per-org flags for the client-side provider. |

## Context

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md`
- **ADR-043:** `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`
- **Migration 053 (schema):** `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql`
- **Migration 060 (JWT hook):** `apps/web-platform/supabase/migrations/060_current_organization_jwt_hook.sql`
- **Correct query pattern:** `apps/web-platform/server/workspace-resolver.ts` line 161
- **Second caller:** `apps/web-platform/app/api/flags/route.ts` -- also calls `resolveIdentity`, also benefits from this fix (returns correct orgId in the `/api/flags` GET response)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- single-file bug fix in the feature-flag identity resolver. The fix corrects a PostgREST query to use the established embedded-resource join pattern already used elsewhere in the codebase. No schema changes, no legal changes, no infrastructure changes.

## References

- [workspace-resolver.ts](https://github.com/jikig-ai/soleur/blob/main/apps/web-platform/server/workspace-resolver.ts) -- correct PostgREST embedded-resource join pattern
- [ADR-043](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md) -- Flagsmith per-org targeting
