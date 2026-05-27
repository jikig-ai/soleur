---
date: 2026-05-27
category: architecture
module: web-platform/workspace
severity: high
related_issues:
  - 4520
  - 4516
---

# Learning: Workspace Has Two Independent Ownership Representations

## Problem

During brainstorm for #4520 (workspace role management), three independent agents (CPO, CLO, CTO) independently flagged the same architectural risk: workspace ownership is represented in two places that can silently diverge.

1. `organizations.owner_user_id` — billing/org-level owner. Read by `account-delete.ts:670`, `dsar-export-allowlist.ts:190`, `dsar-export.ts:874`, and `list_workspace_member_actions` (mig 063:256).
2. `workspace_members.role = 'owner'` — workspace-level role. Read by invite-member, remove-member, update-role RPCs, delegations route, Members tab UI.

Any mutation that changes ownership at one layer without updating the other creates silent authorization divergence: the UI shows one owner, but audit-log access, DSAR exports, and account-delete cascades follow the other.

## Solution

The `transfer_workspace_ownership` RPC must atomically update both `workspace_members.role` (swap target→owner, caller→member) AND `organizations.owner_user_id` (set to new owner) in a single SECURITY DEFINER transaction. Promote-before-demote ordering ensures the at-least-one-owner invariant is never violated, even momentarily.

## Key Insight

When the same concept (ownership) is represented at two granularity levels (org-level and workspace-level), every mutation must be audited against BOTH representations. The call-site sweep (`hr-write-boundary-sentinel-sweep-all-write-sites`) must enumerate readers of BOTH columns, not just the one being mutated. This pattern recurs whenever a data model has a denormalized foreign concept — the fix is always an atomic dual-write in a single RPC, never two sequential API calls.

## Tags
category: architecture
module: web-platform/workspace
