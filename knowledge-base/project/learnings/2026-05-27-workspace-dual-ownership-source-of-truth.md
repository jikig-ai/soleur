---
date: 2026-05-27
category: architecture
module: web-platform/workspace
severity: high
related_issues:
  - 4520
  - 4522
  - 4518
  - 4516
tags:
  - ownership-transfer
  - security-definer
  - atomic-dual-write
  - workspace-management
---

# Learning: Workspace Ownership Transfer — Dual-Write, Race Guards, and Attestation Alignment

## Problem

Workspace ownership is represented in two places that can silently diverge:

1. `organizations.owner_user_id` — billing/org-level owner. Read by `account-delete.ts`, `dsar-export-allowlist.ts`, `dsar-export.ts`, and `list_workspace_member_actions` (mig 063).
2. `workspace_members.role = 'owner'` — workspace-level role. Read by invite-member, remove-member, update-role RPCs, delegations route, Members tab UI.

Three independent domain agents (CPO, CLO, CTO) flagged this during brainstorm. Additionally, the `anonymise_organization_membership` function (mig 065) updated `organizations.owner_user_id` without promoting the replacement member's `workspace_members.role`, creating a latent desync.

## Solution

`transfer_workspace_ownership` SECURITY DEFINER RPC atomically: (1) promotes target to owner, (2) demotes caller to member, (3) updates `organizations.owner_user_id`, (4) writes fresh attestation row linked to `workspace_members.attestation_id`. Promote-before-demote ordering ensures the at-least-one-owner invariant is never violated.

Three review-cycle fixes proved critical:
- **Concurrent transfer race:** `SELECT FOR UPDATE` on both workspace_members rows prevents two simultaneous transfers from both observing the caller as owner under READ COMMITTED.
- **Attestation alignment:** The attestation row must be INSERTed before the promote UPDATE, then the UPDATE `SET attestation_id = v_attestation_id` links it. Creating the attestation after the role change leaves the audit trigger capturing a `role_changed` event without the attestation reference.
- **Pre-existing desync fix:** `anonymise_organization_membership` now promotes the replacement member's role alongside the `owner_user_id` update.

## Key Insight

When the same concept (ownership) is represented at two granularity levels, every mutation must be audited against BOTH representations. The call-site sweep must enumerate readers of BOTH columns. The fix pattern is always an atomic dual-write in a single RPC, never two sequential API calls.

For concurrent mutation safety: any authorization check that reads a role before mutating it must use `SELECT ... FOR UPDATE` — READ COMMITTED isolation alone does not prevent two transactions from both passing the "am I the owner?" check.

For attestation audit trails: INSERT the attestation row BEFORE the role UPDATE so the UPDATE can reference it via foreign key. Post-mutation attestation creates orphaned rows that the audit trigger cannot correlate.

## Tags
category: architecture
module: web-platform/workspace
