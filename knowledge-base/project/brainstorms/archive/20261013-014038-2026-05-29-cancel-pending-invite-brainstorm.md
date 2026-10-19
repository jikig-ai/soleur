---
date: 2026-05-29
topic: cancel-pending-invite
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Cancel a Pending Workspace Invite

## What We're Building

An owner-facing **Cancel invite** action on the Pending invites list (Settings → Members → Team).
Today an owner can invite a member and remove an existing member, but there is **no way to revoke a
pending invite** — so a typo'd email or a never-accepted invite stays live until it expires (7 days).

Scope: cancel only. Resend / re-issue is explicitly deferred (see Non-Goals).

## Why This Approach

The codebase already has every adjacent primitive; this fills a CRUD hole rather than introducing a
new pattern:

- **Invitee side:** `accept_workspace_invitation`, `decline_workspace_invitation` RPCs + routes exist.
- **Owner side:** `remove-member` route is the authorization template (CSRF → auth → page-data resolve
  → flag gate → workspace-match → owner-check → service call).
- **State model:** `workspace_invitations` uses soft-state columns (`accepted_at`, `declined_at`).
  Cancellation gets the symmetric `revoked_at` (+ `revoked_by`) column, keeping an audit trail and
  staying consistent with the existing accept/decline shape.

Confirmed gaps (grepped on `main`): no `revoke_workspace_invitation` / `cancel_workspace_invitation`
RPC, no `revoked_at` column on `workspace_invitations`, and `PendingInvitesList` is display-only (not
even passed `isOwner`).

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage | **Soft revoke** — add `revoked_at` + `revoked_by` | Audit trail; mirrors accepted_at/declined_at; doesn't break the duplicate-pending guard on re-invite |
| Scope | **Cancel only** | Covers wrong-email (cancel + re-invite correct address) and stale-invite cases; resend is YAGNI for now |
| Authorization | **Owner-only, double-gated** | Route owner-check (mirror `remove-member`) AND ownership re-checked inside the SECURITY DEFINER RPC |
| Tenant safety | **Workspace-scoped RPC** | Caller's resolved workspace must match the invite's `workspace_id`; reject `workspace_mismatch` (403) |
| UX | **Server-confirmed optimistic removal** | Row removed from list only after `{ ok: true }`; on error, restore row + surface message (no silent no-op) |
| Discoverability | Cancel button rendered only when caller `isOwner` | Pass `isOwner` into `PendingInvitesList` (currently absent) |

## User-Brand Impact

- **Artifact:** pending `workspace_invitations` rows on a multi-tenant production surface.
- **Vectors (operator confirmed ALL apply):**
  1. *Wrong invite cancelled / non-owner cancels* → owner-only + invitation-id-scoped delete.
  2. *Cross-workspace leak* (owner of A cancels B's invite) → workspace-match gate + RPC re-check.
  3. *Silent no-op* (button "works" but invite stays live) → UI commits removal only on server `{ ok: true }`.
- **Threshold:** `single-user incident`. Carries forward to the plan; the load-bearing review gates are
  `identity-rbac-reviewer` (RLS / owner-check / workspace boundary) and `user-impact-reviewer` at PR time.

## Open Questions

1. **Expired invites:** the owner list filters `expires_at > now()`, so expired invites never render and
   can't be cancelled from the UI. Acceptable for now (they're inert) — flag for plan if we later want an
   "expired" section.
2. **Attestation linkage:** invite creation records an attestation. Does revoke need its own attestation
   row, or is `revoked_by` + `revoked_at` on the invitation sufficient? Lean sufficient; confirm at plan.
3. **In-flight token:** soft-revoke must cause `lookup_invitation_by_token` to treat a revoked invite as
   invalid (add `revoked_at IS NULL` to the lookup predicate) so a leaked link can't be accepted post-cancel.

## Domain Assessments

**Assessed:** Engineering (inline), Product (inline). Marketing, Operations, Legal, Sales, Finance,
Support — not relevant to an owner-only membership control.

### Engineering

**Summary:** Pure additive CRUD-with-authz mirroring `remove-member` + `decline-invite`. Surfaces:
migration (`revoked_at`/`revoked_by` + SECURITY DEFINER RPC with `search_path` pinned to `pg_temp` per
`cq-pg-security-definer-search-path-pin-pg-temp`), service wrapper in `workspace-invitations.ts`, new
`/api/workspace/cancel-invite` route, `lookup_invitation_by_token` predicate update, and `PendingInvitesList`
client action. No new external dependency.

### Product

**Summary:** Closes an obvious UX gap the operator hit while dogfooding in production. Cancel-only is the
right MVP slice; it already solves the two stated motivations (wrong email, never-accepted). Resend deferred.
