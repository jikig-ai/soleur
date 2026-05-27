---
title: "fix: update tenant-integration test fixtures for transfer_workspace_ownership RPC"
plan: knowledge-base/project/plans/2026-05-27-fix-test-fixtures-transfer-ownership-plan.md
branch: feat-one-shot-fix-test-fixtures-transfer-ownership
---

# Tasks

## Phase 1: Fix confirmed call site

### 1.1 Replace RPC call in test 3.2.4
- [ ] Replace `update_workspace_member_role` call (line 284-288) with `transfer_workspace_ownership` RPC
- [ ] Use parameters: `p_workspace_id: fixtureX.workspaceId`, `p_new_owner_user_id: dId`, `p_attestation_text: "test-ownership-transfer-3.2.4-fixture"` (42 chars, above 16-char minimum)
- [ ] Assert `transferErr` is null AND `attestationId` is truthy (RPC returns uuid)
- [ ] Update comment at line 281-283 to reflect transfer semantics ("Transfer ownership from A to D" instead of "Demote attempt")
- [ ] Update test name at line 260 to "3.2.4 ownership-transfer writes workspace_member_actions with actor (F2)"

### 1.2 Update workspace_member_actions assertion (lines 291-301)
- [ ] Keep existing query filtering on `target_user_id = dId` (still correct for D-promote row)
- [ ] Keep `action_type = 'role_changed'` assertion (audit trigger fires `role_changed` for the UPDATE)
- [ ] Add `new_role = 'owner'` assertion for completeness
- [ ] Keep `actor_user_id = ownerA.userId` assertion (GUC set at mig 075:94)

### 1.3 Update workspace_member_removals assertion (lines 303-310)
- [ ] Change query from `removed_user_id = dId` to `removed_user_id = ownerA.userId`
- [ ] Add `.eq("revocation_reason", "ownership-transferred")` to distinguish from test 3.2.1's removal row (reason='removed')
- [ ] Change expected reason from `'role-changed'` to `'ownership-transferred'`
- [ ] Add assertion: `removed_by_user_id = ownerA.userId` (voluntary transfer)

### 1.4 Verify cleanup (lines 312-316)
- [ ] Confirm existing cleanup shape (`service.from("workspace_members").delete().eq("user_id", dId)` then `service.auth.admin.deleteUser(dId)`) works for D-as-owner -- service-role bypasses RLS

### 1.5 Verify test ordering
- [ ] Confirm tests 3.2.1, 3.2.2, 3.2.3, 3.2.5, AC15 F6 run before 3.2.4 and do not depend on A's role post-transfer
- [ ] Confirm afterAll cleanup uses service-role operations (no owner-check dependency)

## Phase 2: Investigate other test files

### 2.1 Run account-delete.cascade.integration.test.ts
- [ ] No `update_workspace_member_role` call exists in this file -- if it fails, root cause is different from issue description
- [ ] If fails: check `anonymise_organization_membership` rewrite (mig 075 section 3) or `handle_new_user` trigger interaction
- [ ] If passes: scope out (no change needed)

### 2.2 Run attachments-workspace-shared-cascade.integration.test.ts
- [ ] No `update_workspace_member_role` call exists in this file -- same investigation pattern as 2.1
- [ ] If fails: diagnose root cause from error message
- [ ] If passes: scope out (no change needed)

## Phase 3: Verification

### 3.1 Full suite verification
- [ ] Run: `rg "update_workspace_member_role" apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` returns 0 matches
- [ ] Run: `rg "p_new_role.*owner" apps/web-platform/test/server/` returns 0 matches
- [ ] Run: `rg "transfer_workspace_ownership" apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` returns at least 1 match
- [ ] Confirm no files outside `apps/web-platform/test/` were modified
