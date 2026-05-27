---
title: "fix: update tenant-integration test fixtures for transfer_workspace_ownership RPC"
plan: knowledge-base/project/plans/2026-05-27-fix-test-fixtures-transfer-ownership-plan.md
branch: feat-one-shot-fix-test-fixtures-transfer-ownership
---

# Tasks

## Phase 1: Fix confirmed call site

### 1.1 Rewrite test 3.2.4 in workspace-member-revocation.tenant-isolation.test.ts
- [ ] Replace `update_workspace_member_role` call (line 284) with `transfer_workspace_ownership` RPC
- [ ] Provide valid `p_attestation_text` (>= 16 chars)
- [ ] Update comment at line 281-283 to reflect transfer semantics instead of "demote attempt"
- [ ] Update `workspace_member_actions` assertion: verify action for D with new_role='owner'
- [ ] Update `workspace_member_removals` assertion: revocation row is now for owner A (demoted), reason='ownership-transferred'
- [ ] Update D cleanup: D is now owner -- service-role `auth.admin.deleteUser(dId)` still works (bypasses RLS)

### 1.2 Verify test ordering safety
- [ ] Confirm test 3.2.4 does not break tests 3.2.1-3.2.5 or AC15 F6 by demoting A
- [ ] If ordering issue exists, isolate test 3.2.4 with its own fixture or restore A's owner role in cleanup

## Phase 2: Investigate other test files

### 2.1 Run account-delete.cascade.integration.test.ts
- [ ] Execute with `TENANT_INTEGRATION_TEST=1` to confirm pass/fail
- [ ] If fails: diagnose root cause (mig 075 `anonymise_organization_membership` rewrite or other)
- [ ] If fails: apply targeted fix

### 2.2 Run attachments-workspace-shared-cascade.integration.test.ts
- [ ] Execute with `TENANT_INTEGRATION_TEST=1` to confirm pass/fail
- [ ] If fails: diagnose root cause
- [ ] If fails: apply targeted fix

## Phase 3: Verification

### 3.1 Full suite verification
- [ ] Run: `rg 'update_workspace_member_role.*owner' apps/web-platform/test/server/` returns 0 matches
- [ ] Run all three test files with `TENANT_INTEGRATION_TEST=1` and confirm green
- [ ] Confirm no production code changes (only test files modified)
