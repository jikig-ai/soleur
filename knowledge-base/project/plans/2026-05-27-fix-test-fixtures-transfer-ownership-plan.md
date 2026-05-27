---
title: "fix: update tenant-integration test fixtures for transfer_workspace_ownership RPC"
type: fix
date: 2026-05-27
lane: single-domain
source_issue: 4535
source_pr: 4522
deepened: 2026-05-27
---

# fix: update tenant-integration test fixtures for transfer_workspace_ownership RPC

## Enhancement Summary

**Deepened on:** 2026-05-27
**Sections enhanced:** 4 (Implementation Phases, Acceptance Criteria, Sharp Edges, Test Scenarios)

### Key Improvements
1. Precise audit trigger semantics documented -- `transfer_workspace_ownership` fires TWO `role_changed` audit rows (one for promote, one for demote) via the mig 063 `workspace_members_audit` trigger
2. Revocation row subject corrected -- the revocation is for A (demoted owner), not D; query must filter on `removed_user_id = ownerA.userId`
3. Attestation text requirement grounded -- mig 075 line 88 enforces `length(p_attestation_text) >= 16`; test must pass a string meeting this minimum
4. Test ordering confirmed safe -- tests 3.2.1-3.2.5 and AC15 run before 3.2.4 uses A's owner status; afterAll cleanup uses service-role (no owner-check dependency)

### New Considerations Discovered
- The mig 063 audit trigger at line 192-200 fires `role_changed` for ANY `workspace_members` UPDATE where `OLD.role IS DISTINCT FROM NEW.role` -- `transfer_workspace_ownership` produces TWO such rows (D promoted + A demoted), both with `actor_user_id = A`
- The `workspace_member_removals` row from transfer has `removed_by_user_id = v_caller_user_id` (A), meaning A voluntarily transferred -- distinct from the 3.2.1 removal where `removed_by_user_id = A` and `removed_user_id = B`
- D's cleanup must delete the workspace_members row BEFORE auth.admin.deleteUser since D is now owner and FK constraints may prevent cascade in some paths

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

### Deepen-Plan: Audit Trigger Semantics (mig 063 `workspace_members_audit`)

The audit trigger at `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:160-216` fires `AFTER INSERT OR UPDATE OR DELETE ON public.workspace_members` and writes to `workspace_member_actions`. Key behaviors for the rewrite:

1. **UPDATE path (line 192-200):** When `OLD.role IS DISTINCT FROM NEW.role`, writes `action_type='role_changed'` with `target=NEW.user_id`, `old_role=OLD.role`, `new_role=NEW.role`, `attestation_id=NEW.attestation_id`.
2. **Actor source (line 178):** Reads from GUC `workspace_audit.actor_user_id` set by `transfer_workspace_ownership` at line 94: `PERFORM set_config('workspace_audit.actor_user_id', v_caller_user_id::text, true)`. So `actor_user_id = A` for both triggered rows.
3. **Two audit rows:** `transfer_workspace_ownership` does TWO UPDATEs (promote D at line 111-115, demote A at line 118-121). Each triggers a separate `role_changed` row:
   - Row 1: `target=D, old_role='member', new_role='owner', attestation_id=<v_attestation_id>`
   - Row 2: `target=A, old_role='owner', new_role='member', attestation_id=NULL` (demote does not set attestation_id)

**Assertion adjustment for test 3.2.4:**
- The existing assertion at line 291-301 queries `workspace_member_actions` WHERE `target_user_id = dId`. This still works for the D-targeted promote row.
- The `action_type='role_changed'` assertion at line 301 is still correct.
- Add `new_role='owner'` to the assertion for completeness.
- The revocation assertion at line 303-310 must change from `removed_user_id = dId` to `removed_user_id = ownerA.userId` and from `revocation_reason='role-changed'` to `revocation_reason='ownership-transferred'`.

### Deepen-Plan: Test Ordering Analysis

Vitest runs tests within a `describe` block sequentially by default. The test order is:
1. `3.2.1` -- Owner A removes B from workspace X (A must be owner)
2. `3.2.2` -- Uses B's pre-removal JWT (no A-role dependency)
3. `3.2.3` -- Clock-skew tolerance (no A-role dependency)
4. `3.2.5` -- RLS deny on B's JWT (no A-role dependency)
5. `3.2.4` -- Role-change with D (A is owner at entry, becomes member at exit)
6. `AC15 F6` -- Checks user_session_state for B (no A-role dependency)

**Conclusion:** Test 3.2.4 is the only test that requires A to be owner at entry and modifies A's role. Since it runs after all tests that depend on A's owner status, the ordering is safe. The `afterAll` cleanup at line 127-144 uses service-role operations (`tearDownSharedWorkspace` does direct DELETEs) which bypass ownership checks.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing impact -- test-only change.
- **If this leaks, the user's data/workflow/money is exposed via:** no exposure -- test fixtures use synthetic `@soleur.test` emails per `cq-test-fixtures-synthesized-only`.
- **Brand-survival threshold:** `none`
  - `threshold: none, reason: pure test fixture update with no production code changes`

## Acceptance Criteria

- [ ] AC1: `workspace-member-revocation.tenant-isolation.test.ts` test 3.2.4 calls `transfer_workspace_ownership` instead of `update_workspace_member_role` when promoting a member to owner. Verification: `rg 'transfer_workspace_ownership' apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` returns at least 1 match.
- [ ] AC2: Test 3.2.4 revocation assertion queries `removed_user_id = ownerA.userId` (not `dId`) with `revocation_reason = 'ownership-transferred'` (not `'role-changed'`). The `workspace_member_actions` assertion includes `new_role = 'owner'` for the D-targeted row.
- [ ] AC3: `rg "update_workspace_member_role" apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` returns zero matches (the old RPC call is fully removed from this file).
- [ ] AC4: `account-delete.cascade.integration.test.ts` and `attachments-workspace-shared-cascade.integration.test.ts` investigated -- either confirmed passing (no change needed) or root cause diagnosed and fixed.
- [ ] AC5: Verification: `rg "p_new_role.*owner\|update_workspace_member_role.*owner" apps/web-platform/test/server/` returns zero matches (no remaining calls that promote to owner via the old RPC across all tenant-isolation test files).
- [ ] AC6: No production code changes -- only files under `apps/web-platform/test/` are modified.

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

**File:** `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts`

#### 1.1. Replace RPC call (lines 281-289)

Replace the comment and RPC call:

```typescript
// Old (lines 281-289):
// Demote attempt — D is already member; role-change to member is
// a no-op semantically but exercises the audit writer. Use 'owner'
// → role actually changes.
const { error: roleErr } = await aClient.rpc("update_workspace_member_role", {
  p_workspace_id: fixtureX.workspaceId,
  p_user_id: dId,
  p_new_role: "owner",
});
expect(roleErr).toBeNull();
```

With:

```typescript
// New:
// Transfer ownership from A to D — exercises the audit writer and
// the mig 075 transfer_workspace_ownership path. The transfer
// atomically promotes D to owner and demotes A to member.
const { data: attestationId, error: transferErr } = await aClient.rpc(
  "transfer_workspace_ownership",
  {
    p_workspace_id: fixtureX.workspaceId,
    p_new_owner_user_id: dId,
    p_attestation_text: "test-ownership-transfer-3.2.4-fixture",
  },
);
expect(transferErr, `transfer_workspace_ownership failed: ${transferErr?.message}`).toBeNull();
expect(attestationId).toBeTruthy();
```

Note: attestation text "test-ownership-transfer-3.2.4-fixture" is 42 chars, well above the 16-char minimum.

#### 1.2. Update `workspace_member_actions` assertion (lines 291-301)

The existing query on `target_user_id = dId` is still correct for the D-promote row. Add `new_role` assertion:

```typescript
// Existing assertions remain valid:
expect(actionRows).toHaveLength(1);
expect(actionRows![0].actor_user_id).toBe(ownerA.userId);
expect(actionRows![0].action_type).toBe("role_changed");
// Add:
expect(actionRows![0].new_role).toBe("owner");
```

#### 1.3. Update `workspace_member_removals` assertion (lines 303-310)

Change from querying D's revocation to A's revocation:

```typescript
// Old (lines 303-310):
const { data: revRows } = await service
  .from("workspace_member_removals")
  .select("revocation_reason")
  .eq("removed_user_id", dId)
  .eq("workspace_id", fixtureX.workspaceId);
expect(revRows).toHaveLength(1);
expect(revRows![0].revocation_reason).toBe("role-changed");
```

With:

```typescript
// New — transfer writes a revocation row for A (demoted owner):
const { data: revRows } = await service
  .from("workspace_member_removals")
  .select("revocation_reason, removed_by_user_id")
  .eq("removed_user_id", ownerA.userId)
  .eq("workspace_id", fixtureX.workspaceId)
  .eq("revocation_reason", "ownership-transferred");
expect(revRows).toHaveLength(1);
expect(revRows![0].removed_by_user_id).toBe(ownerA.userId);
```

Note: the `.eq("revocation_reason", "ownership-transferred")` filter is load-bearing because test 3.2.1 already wrote a revocation row for B on the same workspace. Without filtering by reason, the query could match the wrong row.

#### 1.4. Update cleanup (lines 312-316)

D is now owner after transfer. The cleanup needs to delete the workspace_members row first (D is now owner), then the auth user:

```typescript
// Cleanup D — now owner after transfer.
try {
  await service.from("workspace_members").delete().eq("user_id", dId);
  await service.auth.admin.deleteUser(dId);
} catch {}
```

This is the same shape as the existing cleanup. The `service` client uses service-role which bypasses RLS, so the `workspace_members` DELETE works regardless of D's role.

#### 1.5. Update test comment (line 260)

Update the test description comment to reflect transfer semantics:

```typescript
test("3.2.4 ownership-transfer writes workspace_member_actions with actor (F2)", async () => {
```

### Phase 2: Investigate other two test files

1. Run `account-delete.cascade.integration.test.ts` with `TENANT_INTEGRATION_TEST=1` to confirm actual pass/fail status. The file contains NO call to `update_workspace_member_role` -- if it fails, the root cause is different from the issue description (likely `anonymise_organization_membership` rewrite in mig 075 section 3, or `handle_new_user` trigger interaction).
2. Run `attachments-workspace-shared-cascade.integration.test.ts` with `TENANT_INTEGRATION_TEST=1` to confirm actual pass/fail. Same reasoning -- no `update_workspace_member_role` call exists in this file.
3. If either fails, diagnose root cause by reading the error message and tracing to the specific RPC or trigger that changed in mig 075.

## Open Code-Review Overlap

None -- no open code-review issues reference the three target test files.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- pure test fixture update.

## Sharp Edges

- `transfer_workspace_ownership` requires `p_attestation_text` of at least 16 characters (mig 075 line 88: `IF p_attestation_text IS NULL OR length(p_attestation_text) < 16 THEN RAISE`). The test must provide a valid attestation string.
- `transfer_workspace_ownership` demotes the caller (A) to member. This is a semantic change from `update_workspace_member_role` which only promoted D without affecting A. Test 3.2.4's assertions must account for A becoming a member.
- The revocation row from `transfer_workspace_ownership` uses `revocation_reason = 'ownership-transferred'` (not `'role-changed'`) and `removed_user_id = v_caller_user_id` (A), not D. The test assertion at line 307 (`removed_user_id = dId`) and line 310 (`reason = 'role-changed'`) must both change.
- `transfer_workspace_ownership` is `SECURITY DEFINER` and requires `auth.uid()` -- cannot be called via service-role client directly. The test already uses `aClient` (Alice's authenticated JWT), which is correct.
- The transfer creates TWO `workspace_member_actions` audit rows (one for D promote, one for A demote) via the mig 063 trigger. The existing assertion queries `target_user_id = dId` which correctly isolates the D-promote row. Do NOT query without the target filter or the assertion will see both rows.
- The `workspace_member_removals` query must include `.eq("revocation_reason", "ownership-transferred")` to distinguish from the test 3.2.1 removal row (reason='removed') which also exists on `fixtureX.workspaceId`.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.

## References

- Source issue: #4535
- Source PR: #4522
- Migration: `apps/web-platform/supabase/migrations/075_transfer_workspace_ownership.sql`
- Learning: `knowledge-base/project/learnings/2026-05-27-workspace-dual-ownership-source-of-truth.md`
- RPC server wrapper: `apps/web-platform/server/workspace-membership.ts:326-338`
