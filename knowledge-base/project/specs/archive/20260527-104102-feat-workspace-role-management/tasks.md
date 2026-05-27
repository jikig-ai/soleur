---
plan: knowledge-base/project/plans/2026-05-27-feat-workspace-ownership-transfer-plan.md
status: pending
---

# Tasks: Workspace Ownership Transfer

## Phase 0: Preconditions

- [x] 0.1 Verify #4518 merged to main
- [x] 0.2 Verify migration 067 exists on main
- [ ] 0.3 Determine next migration number
- [ ] 0.4 Read invite-member route for API pattern

## Phase 1: Migration

- [ ] 1.1 Create `NNN_transfer_workspace_ownership.sql`
  - [ ] 1.1.1 `transfer_workspace_ownership` RPC (SECURITY DEFINER, search_path pin)
  - [ ] 1.1.2 Self-transfer guard (RAISE 22023)
  - [ ] 1.1.3 Attestation INSERT with column mapping (inviter=old owner, invitee=new owner)
  - [ ] 1.1.4 Promote UPDATE: `SET role = 'owner', attestation_id = v_attestation_id`
  - [ ] 1.1.5 Demote UPDATE: `SET role = 'member'`
  - [ ] 1.1.6 Dual-write: `organizations.owner_user_id`
  - [ ] 1.1.7 Revocation INSERT: `revocation_reason = 'ownership-transferred'`
  - [ ] 1.1.8 F6 session clear for demoted owner only
  - [ ] 1.1.9 REVOKE/GRANT matrix
- [ ] 1.2 Restrict `update_workspace_member_role` (CREATE OR REPLACE with FULL body + new guard)
- [ ] 1.3 Fix `anonymise_organization_membership` (promote replacement member's role)
- [ ] 1.4 Create down migration
- [ ] 1.5 Verify `check-workspace-members-write-sites.sh` passes

## Phase 2: Server + API Route + Frontend

- [ ] 2.1 Add `transferWorkspaceOwnership` to `server/workspace-membership.ts`
  - [ ] 2.1.1 Types (TransferWorkspaceOwnershipArgs, TransferResult, TransferFailureReason)
  - [ ] 2.1.2 RPC call via service client
  - [ ] 2.1.3 Error mapping (self_transfer, caller_not_owner, target_not_member, target_already_owner)
  - [ ] 2.1.4 SIGTERM + WS close for demoted owner only
- [ ] 2.2 Add `"ownership-transferred"` handler to middleware.ts
- [ ] 2.3 Add `organizationName` to `TeamMembershipPageData` in team-membership-resolver.ts
- [ ] 2.4 Create `app/api/workspace/transfer-ownership/route.ts`
  - [ ] 2.4.1 CSRF, auth, flag gate
  - [ ] 2.4.2 Body validation
  - [ ] 2.4.3 Workspace mismatch + owner check
  - [ ] 2.4.4 Error-to-HTTP-status mapping
- [ ] 2.5 Create `components/settings/transfer-ownership-dialog.tsx`
  - [ ] 2.5.1 Consequences display
  - [ ] 2.5.2 Type-to-confirm input (org name or target email fallback)
  - [ ] 2.5.3 Loading + error states
- [ ] 2.6 Extend kebab menu in `team-membership-list.tsx`
  - [ ] 2.6.1 "Transfer ownership" option (isOwner && !isCurrentUser)
  - [ ] 2.6.2 Dialog open/close wiring

## Phase 3: Tests

- [ ] 3.1 Integration test: transfer RPC happy path
- [ ] 3.2 Negative tests: non-owner, self-transfer, non-member, workspace mismatch
- [ ] 3.3 Verify update_workspace_member_role rejects owner promotion
- [ ] 3.4 Verify anonymise_organization_membership promotes replacement
- [ ] 3.5 Verify audit trigger attestation_id linkage
- [ ] 3.6 Verify list_workspace_member_actions returns for new owner
- [ ] 3.7 Verify middleware "ownership-transferred" copy
