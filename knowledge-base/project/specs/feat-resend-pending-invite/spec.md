---
feature: resend-pending-invite
date: 2026-05-29
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-05-29-resend-pending-invite-brainstorm.md
issue: 4636
---

# Spec: Resend / re-issue a pending workspace invite

## Problem Statement

A workspace owner can create, cancel, and remove invites/members, but cannot **resend** a
pending invite. When the right person simply never accepts in time, the owner's only recourse
is cancel + fully re-invite. Deferred from #4634 (cancel-pending-invite, shipped #4632);
re-evaluation criterion was "repeated 'invite expired before acceptance' friction."

## Goals

- Let a workspace **owner** resend any **non-terminal** invite (expired **or** still-valid)
  belonging to their workspace, from the Pending invites list.
- Resending **rotates the token** (old link stops working) and **resets the 7-day expiry**.
- Re-send the invite email to the same address.
- Preserve the append-only audit trail (no mutation of immutable columns).

## Non-Goals

- Changing the invitee email or role on resend (that is cancel + re-invite — wrong-email path).
- Re-capturing owner attestation (the attested fact — this email at this role — is unchanged).
- Resend count / per-invite send history surfaced in the UI (over-build; cooldown guards spam).
- Resending terminal invites (accepted / declined / already-revoked).
- Bulk resend.

## Functional Requirements

- **FR1** — A **Resend** control appears on each pending invite row, owner-only (alongside Cancel).
  Primary/emphasized affordance on **expired** rows; secondary "nudge" on still-valid rows.
- **FR2** — Resend commits UI state (button → "Sent ✓" ~3s, row expiry refreshed to "Expires in 7d")
  **only after** the server confirms `{ ok: true }`. On error, surface a **resend-specific** message
  (not the shared "Couldn't cancel" copy) — no silent no-op.
- **FR3** — After resend, the **old** token fails `lookup_invitation_by_token` / `accept_workspace_invitation`
  (old row is revoked), and the **new** token resolves to a fresh 7-day invite.
- **FR4** — The owner Pending invites list and the invitee's `getPendingInvitesForUser` show exactly one
  live row per invite (the new one); the superseded row is hidden (`revoked_at IS NOT NULL`).
- **FR5** — Resend is rejected for terminal invites (accepted/declined/revoked) with a typed reason.
- **FR6** — Resend is rate-limited: a resend within ~60s of the most recent non-terminal invite for the
  same `(workspace_id, invitee_email)` is rejected (`resend_too_soon`); the UI disables the button for the
  cooldown window.

## Technical Requirements

- **TR1** — Migration: add `resend_workspace_invitation(p_invitation_id, p_new_token_hash, p_caller_user_id)`
  SECURITY DEFINER RPC. In **one transaction**: `SELECT … FOR UPDATE` the old row → re-check caller is owner
  of the **old row's** `workspace_id` (`caller_not_owner`) → terminal-state guards
  (`already_accepted`/`already_declined`/`already_revoked`) → cooldown guard (`resend_too_soon`,
  derived from the most-recent non-terminal row's `created_at` — **prefer no new column / no trigger arm**) →
  `UPDATE old SET revoked_at=now(), revoked_by=caller` → `INSERT` new row (new `token_hash`, `now()+7d`,
  same email/role/inviter, **carry-forward `attestation_id`**). Pin `search_path = public, pg_temp`
  (`cq-pg-security-definer-search-path-pin-pg-temp`); `REVOKE … FROM PUBLIC,anon,authenticated`,
  `GRANT EXECUTE … TO service_role`. **Do not gate on `expires_at`** — expired-but-pending is a valid target.
- **TR2** — Resolve the attestation FK question: confirm two invitation rows may share one `attestation_id`
  (check `058` + `076`). If a 1:1 constraint exists, either copy the attestation row or relax the constraint
  in the same migration. **No** new attestation is captured on resend.
- **TR3** — `resendWorkspaceInvitation()` wrapper in `server/workspace-invitations.ts`: mint token via
  `generateInviteToken`/`hashToken`, pass only the **hash** to PG, return the raw token to the route; typed
  result + error mapping mirroring `revokeWorkspaceInvitation`.
- **TR4** — `POST /api/workspace/resend-invite` route mirroring `cancel-invite`'s auth chain: CSRF/origin →
  `auth.getUser` → `resolveTeamMembershipPageData` → `isTeamWorkspaceInviteEnabled` flag gate →
  workspace-match (403) → owner-check (403) → service call → `sendInviteEmail(...)` with the new token.
  Route exports HTTP handlers only (`cq-nextjs-route-files-http-only-exports`).
- **TR5** — Observability (`cq-silent-fallback-must-mirror-to-sentry`, `hr-observability-as-plan-quality-gate`):
  RPC transport errors and reasonless `ok:false` reach Sentry via `reportSilentFallback`. The resend route's
  email send **must not** use `.catch(()=>{})` — replace with a `.catch` that calls `reportSilentFallback`
  (op `resend-email`), since a swallowed failure on an explicit "send again" is a silent no-op on a user action.
- **TR6** — UI (`components/settings/pending-invites-list.tsx`): add a `sentIds` Set alongside the existing
  per-row `pendingIds`/`errorIds`; Resend button sibling of Cancel in a `flex gap-2` cluster; commit-on-ok;
  resend-specific error copy; refresh `expires_at` on success; 60s disabled-button cooldown.
- **TR7** — Tests before implementation (`cq-write-failing-tests-before`): owner-resend-happy-path (old token
  dead, new token live, expiry reset), non-owner-rejected (403), cross-workspace-rejected (403),
  terminal-invite-rejected (409), cooldown-rejected (`resend_too_soon`), attestation carried forward, DSAR
  export unaffected. Extend `e2e/team-membership.e2e.ts` and `test/components/settings/pending-invites-list.test.tsx`.
- **TR8** — DSAR/account-delete regression check: `dsar-export.ts`, `dsar-export-allowlist.ts`,
  `account-delete.ts` read `workspace_invitations`; confirm revoke+insert (more rows, no new PII shape) leaves
  exports/deletes correct.

## Review Gates (carry-forward)

- `identity-rbac-reviewer` — RPC-level owner re-check on the old row's workspace, SECURITY DEFINER search_path pin.
- `security-sentinel` — token rotation atomicity; old token truly dead; no window with both/neither valid.
- `user-impact-reviewer` — `single-user incident` threshold; the three confirmed vectors: stale-token survival,
  email abuse / #4638 OTP re-trip, cross-tenant resend.
- `gdpr-gate` — resend as a fresh PII-processing event; accountability logging; auditor confirms no
  Privacy/DPD/register edit needed.
