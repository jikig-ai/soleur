---
feature: cancel-pending-invite
date: 2026-05-29
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-05-29-cancel-pending-invite-brainstorm.md
---

# Spec: Cancel a Pending Workspace Invite

## Problem Statement

A workspace owner can create invites and remove existing members, but cannot revoke a **pending** invite.
A typo'd email address or an invite the recipient never accepts stays live until it expires (7 days),
with no way to clean it up. Discovered while dogfooding the multi-user feature in production
(Settings → Members → Team; the Pending invites list is display-only).

## Goals

- Let a workspace **owner** cancel any pending invite belonging to their workspace, from the Pending
  invites list.
- Preserve an audit trail of who cancelled and when (soft revoke).
- Ensure a cancelled invite's token can no longer be accepted.

## Non-Goals

- **Resend / re-issue** of an invite (new token, reset expiry). Deferred — see brainstorm Non-Goals.
- Cancelling **expired** invites from the UI (they don't render and are already inert).
- Member-initiated cancellation (members cannot cancel invites; owner-only).
- Bulk cancel.

## Functional Requirements

- **FR1** — A **Cancel** control appears on each pending invite row, rendered only when the current user
  is a workspace owner (`PendingInvitesList` must receive and respect `isOwner`).
- **FR2** — Cancelling removes the row from the list optimistically **only after** the server confirms
  `{ ok: true }`. On error, the row is restored and an error message surfaced (no silent no-op).
- **FR3** — A cancelled invite is excluded from the owner Pending invites query and from the invitee's
  `getPendingInvitesForUser` results.
- **FR4** — A cancelled invite's token fails `lookup_invitation_by_token` (cannot be accepted after cancel).
- **FR5** — After cancel, the same email may be re-invited (the duplicate-pending guard must not count
  revoked invites).

## Technical Requirements

- **TR1** — Migration: add `revoked_at timestamptz NULL` and `revoked_by uuid NULL` to
  `workspace_invitations`.
- **TR2** — Add `revoke_workspace_invitation(p_invitation_id, p_caller_user_id)` SECURITY DEFINER RPC:
  re-check caller is workspace owner; set `revoked_at = now()`, `revoked_by = caller`; reject if already
  accepted/declined/revoked. Pin `search_path` to `pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`).
- **TR3** — Update `lookup_invitation_by_token`, `getPendingInvitesForUser`, and the team-page owner query
  to filter `revoked_at IS NULL`; update the duplicate-pending guard in `create_workspace_invitation`.
- **TR4** — `revokeWorkspaceInvitation()` wrapper in `server/workspace-invitations.ts` mirroring
  `declineWorkspaceInvitation` (RPC call + typed result + error mapping).
- **TR5** — `POST /api/workspace/cancel-invite` route mirroring `remove-member`'s auth chain: CSRF/origin
  → `auth.getUser` → `resolveTeamMembershipPageData` → `isTeamWorkspaceInviteEnabled` flag gate →
  workspace-match (403 `workspace_mismatch`) → owner-check (403 `not_owner`) → service call. Route file
  exports HTTP handlers only (`cq-nextjs-route-files-http-only-exports`).
- **TR6** — Observability: RPC/route failure paths reach Sentry/Better Stack via `reportSilentFallback`
  (mirror existing invitation logging); no SSH-only diagnosis (`hr-observability-as-plan-quality-gate`).
- **TR7** — Tests before implementation (`cq-write-failing-tests-before`): owner-cancels-happy-path,
  non-owner-rejected (403), cross-workspace-rejected (403), revoked-token-not-acceptable, re-invite-after-cancel.
  Extend `e2e/team-membership.e2e.ts`.

## Review Gates (carry-forward)

- `identity-rbac-reviewer` — owner-check, workspace boundary, SECURITY DEFINER search_path pin.
- `user-impact-reviewer` — `single-user incident` threshold; the three confirmed vectors (wrong-cancel,
  cross-workspace leak, silent no-op).
