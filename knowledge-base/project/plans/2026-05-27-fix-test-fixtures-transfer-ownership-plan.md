---
title: "fix: update tenant-integration test fixtures for transfer_workspace_ownership RPC"
type: fix
date: 2026-05-27
lane: single-domain
source_issue: 4535
source_pr: 4522
---

# fix: update tenant-integration test fixtures for transfer_workspace_ownership RPC

## Overview

PR #4522 introduced migration 075 which restricts `update_workspace_member_role` to reject direct owner promotions (`p_new_role = 'owner'`). Ownership changes must now go through the `transfer_workspace_ownership` RPC. This breaks tenant-integration test fixtures that use the old RPC to set up owner state.

**Source PR:** #4522
**Error:** `direct promotion to owner is not allowed; use transfer_workspace_ownership`

## Research Insights

### Confirmed Failing Call Site

`workspace-member-revocation.tenant-isolation.test.ts` test 3.2.4 (line 260-317) calls `update_workspace_member_role` with `p_new_role: "owner"` at line 284:

```typescript
// apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts:284-288
const { error: roleErr } = await aClient.rpc("update_workspace_member_role", {
  p_workspace_id: fixtureX.workspaceId,
  p_user_id: dId,
  p_new_role: "owner",
});
```

This is the ONLY direct call to `update_workspace_member_role` with `p_new_role: "owner"` across the three files named in issue #4535.

### Research Reconciliation -- Issue Body vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| `account-delete.cascade.integration.test.ts` uses `update_workspace_member_role` to set up owner state | File contains NO call to `update_workspace_member_role`. Owner state is set by `handle_new_user` trigger via `createSharedWorkspaceMembers` helper. `deleteAccount` calls `anonymise_organization_membership` which was rewritten in mig 075 to also promote `workspace_members.role`. | **Investigate at work time.** If this test does fail, the root cause is different from what the issue describes. Run the test with `TENANT_INTEGRATION_TEST=1` to confirm status. If it passes, scope out. If it fails, diagnose the actual root cause (likely `anonymise_organization_membership` rewrite). |
| `attachments-workspace-shared-cascade.integration.test.ts` uses `update_workspace_member_role` to set up owner state | File contains NO call to `update_workspace_member_role`. Uses `createSharedWorkspaceMembers` (trigger-based owner creation) and `remove_workspace_member` RPC (not blocked by mig 075). | Same as above -- investigate at work time. |
| `workspace-member-revocation.tenant-isolation.test.ts` (2 failures) | Test 3.2.4 at line 284 calls `update_workspace_member_role` with `p_new_role: "owner"`. This is the confirmed broken call site. The "2 failures" likely counts the test plus cascading assertion failures within the same test function. | Fix confirmed -- replace with `transfer_workspace_ownership` RPC. |

### `transfer_workspace_ownership` RPC Signature (mig 075)

```sql
transfer_workspace_ownership(
  p_workspace_id       uuid,
  p_new_owner_user_id  uuid,
  p_attestation_text   text  -- must be >= 16 chars
) RETURNS uuid
```

- Requires `auth.uid()` to be the current owner (via authenticated JWT, not service-role).
- Promotes target to owner, demotes caller to member.
- Writes attestation row + revocation ledger row.
- Returns the attestation_id.

### Key Constraint for Test 3.2.4 Rewrite

Test 3.2.4 currently:
1. Creates fresh member D in workspace X.
2. Owner A promotes D to owner via `update_workspace_member_role(X, D, "owner")`.
3. Verifies `workspace_member_actions` audit row (action_type='role_changed', actor=A).
4. Verifies `workspace_member_removals` revocation row (reason='role-changed').

The replacement `transfer_workspace_ownership` will:
1. Promote D to owner AND demote A to member (atomic).
2. Write `workspace_member_actions` via the audit trigger with the attestation reference.
3. Write `workspace_member_removals` with `revocation_reason='ownership-transferred'` (for A, the demoted owner).

This changes the test semantics -- the revocation row is now for A (demoted owner), not D (promoted member), and the `revocation_reason` changes from `'role-changed'` to `'ownership-transferred'`. The test assertions must be updated accordingly. Additionally, A is now a member, which affects the subsequent test order since 3.2.1 needs A as owner for removal.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing impact -- test-only change.
- **If this leaks, the user's data/workflow/money is exposed via:** no exposure -- test fixtures use synthetic `@soleur.test` emails per `cq-test-fixtures-synthesized-only`.
- **Brand-survival threshold:** `none`
  - `threshold: none, reason: pure test fixture update with no production code changes`

## Acceptance Criteria

- [ ] AC1: `workspace-member-revocation.tenant-isolation.test.ts` test 3.2.4 calls `transfer_workspace_ownership` instead of `update_workspace_member_role` when promoting a member to owner.
- [ ] AC2: Test 3.2.4 assertions updated to match `transfer_workspace_ownership` behavior: revocation row for the demoted owner (A) with `revocation_reason='ownership-transferred'`, and `workspace_member_actions` audit row reflects the transfer (action_type includes the new role).
- [ ] AC3: All five test cases in `workspace-member-revocation.tenant-isolation.test.ts` pass (3.2.1 through AC15 F6).
- [ ] AC4: `account-delete.cascade.integration.test.ts` and `attachments-workspace-shared-cascade.integration.test.ts` investigated -- either confirmed passing (no change needed) or root cause diagnosed and fixed.
- [ ] AC5: Verification: `rg 'update_workspace_member_role.*owner' apps/web-platform/test/server/` returns zero matches (no remaining calls that promote to owner via the old RPC).
- [ ] AC6: No production code changes -- only test files are modified.

## Test Scenarios

- Given mig 075 is applied (blocking `update_workspace_member_role` from promoting to owner), when test 3.2.4 runs with the new `transfer_workspace_ownership` call, then the test passes and verifies audit + revocation rows.
- Given test 3.2.4 now uses `transfer_workspace_ownership` (which demotes the caller), when subsequent tests depend on owner A's role, then the test ordering and fixture setup account for A's potential demotion.
- Given `TENANT_INTEGRATION_TEST=1`, when running `./node_modules/.bin/vitest run test/server/workspace-member-revocation.tenant-isolation.test.ts`, then all tests pass.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` | Replace `update_workspace_member_role` call in test 3.2.4 with `transfer_workspace_ownership` RPC. Update assertions for revocation_reason and actor fields. Ensure D-cleanup handles D as owner (or re-transfer back). |

## Files to Investigate (may not need changes)

| File | Reason |
|---|---|
| `apps/web-platform/test/server/account-delete.cascade.integration.test.ts` | Issue claims 2 failures, but no `update_workspace_member_role` call exists. Run test to confirm pass/fail status. |
| `apps/web-platform/test/server/attachments-workspace-shared-cascade.integration.test.ts` | Issue claims 1 failure, but no `update_workspace_member_role` call exists. Run test to confirm pass/fail status. |

## Implementation Phases

### Phase 1: Fix confirmed call site (workspace-member-revocation test 3.2.4)

1. Rewrite test 3.2.4 to use `transfer_workspace_ownership` instead of `update_workspace_member_role`:
   - Owner A calls `transfer_workspace_ownership(X, D, "<attestation-text-16-chars>")` to promote D.
   - This atomically demotes A to member.
   - Update assertion: `workspace_member_actions` row for D should have `action_type` reflecting the transfer and `new_role = 'owner'`.
   - Update assertion: `workspace_member_removals` row is now for A (demoted owner), with `revocation_reason = 'ownership-transferred'`.
   - Cleanup: D is now owner; delete D using service-role `auth.admin.deleteUser` which bypasses workspace role checks.

2. Consider test ordering impact: test 3.2.4 runs AFTER 3.2.1, 3.2.2, 3.2.3, and 3.2.5 which all depend on owner A being the owner of workspace X. Since 3.2.4 demotes A, confirm 3.2.4 runs last or uses an isolated fixture (it already creates a fresh member D, so the ordering concern is specifically about the `afterAll` cleanup of A's workspace_members row).

### Phase 2: Investigate other two test files

1. Run `account-delete.cascade.integration.test.ts` to confirm actual pass/fail.
2. Run `attachments-workspace-shared-cascade.integration.test.ts` to confirm actual pass/fail.
3. If either fails, diagnose root cause (likely related to mig 075 `anonymise_organization_membership` rewrite or other mig 075 side effects) and fix.

## Open Code-Review Overlap

None -- no open code-review issues reference the three target test files.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- pure test fixture update.

## Sharp Edges

- `transfer_workspace_ownership` requires `p_attestation_text` of at least 16 characters -- the test must provide a valid attestation string.
- `transfer_workspace_ownership` demotes the caller (A) to member. This is a semantic change from `update_workspace_member_role` which only promoted D without affecting A. Test 3.2.4's assertions must account for A becoming a member.
- The revocation row from `transfer_workspace_ownership` uses `revocation_reason = 'ownership-transferred'` (not `'role-changed'`). The test assertion at line 310 must change.
- `transfer_workspace_ownership` is `SECURITY DEFINER` and requires `auth.uid()` -- cannot be called via service-role client directly. The test already uses `aClient` (Alice's authenticated JWT), which is correct.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.

## References

- Source issue: #4535
- Source PR: #4522
- Migration: `apps/web-platform/supabase/migrations/075_transfer_workspace_ownership.sql`
- Learning: `knowledge-base/project/learnings/2026-05-27-workspace-dual-ownership-source-of-truth.md`
- RPC server wrapper: `apps/web-platform/server/workspace-membership.ts:326-338`
