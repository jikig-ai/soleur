---
name: feat-workspace-invite-acceptance
title: "Workspace Invite Acceptance + Members Tab"
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
bundles:
  - 4516
  - 4519
created: 2026-05-27
brainstorm: knowledge-base/project/brainstorms/2026-05-27-workspace-invite-acceptance-brainstorm.md
---

# Spec: Workspace Invite Acceptance + Members Tab

## Problem Statement

The team workspace infrastructure (organizations, workspace_members, RLS, feature flags, auth identity resolution) exists in production. However, zero frontend UI exists for workspace management: no Members tab in Settings, no invite flow beyond a synchronous API call that requires the invitee to already have an account, no email notifications, no invite acceptance mechanism, and no way for non-users to join via a link.

## Goals

1. Ship a complete Members tab in Settings (flag-gated) with member list and invite modal
2. Implement a token-based invite acceptance flow with a separate `workspace_invitations` table
3. Enable invite-by-email for any email address (existing users and non-users)
4. Send invite notification emails via Resend and acceptance confirmations to inviters
5. Provide multiple acceptance surfaces: dashboard banner, Settings notification, Team page, `/invite/[token]` page
6. Support signup + auto-join for non-user invitees via the `/invite/[token]` landing page

## Non-Goals

- SSO/SAML/SCIM
- Bulk invite / CSV upload
- Invite revocation UI
- Rate limiting on invite creation
- Custom email templates per workspace
- Inngest queue for email (direct Resend fire-and-forget is sufficient)
- Invite expiry reminder emails

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Settings sidebar shows "Team" link when `team-workspace-invite` flag is enabled for the user's org |
| FR2 | Team page displays current workspace members with name, email, role, and join date |
| FR3 | Invite modal accepts any email address; sends invite email with token link |
| FR4 | `workspace_invitations` table stores pending invites with SHA-256 hashed token, 7-day expiry |
| FR5 | `/invite/[token]` public page shows workspace name, inviter name, and accept/decline actions |
| FR6 | Authenticated users on `/invite/[token]` can accept directly; acceptance creates `workspace_members` row |
| FR7 | Unauthenticated users on `/invite/[token]` are redirected to signup with token preserved; post-signup callback auto-accepts |
| FR8 | Dashboard shows pending invite banner when user has unaccepted invitations |
| FR9 | Settings sidebar shows notification dot when pending invites exist |
| FR10 | Team page shows pending invites section with accept/decline actions |
| FR11 | Invite notification email sent to invitee via Resend on invite creation |
| FR12 | Acceptance confirmation email sent to inviter via Resend on invite acceptance |
| FR13 | Tokens are single-use, 7-day expiry, cryptographically random (32 bytes, base64url) |
| FR14 | Declining an invite marks it as declined; the inviter can re-invite |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | New `workspace_invitations` migration with RLS policies, WORM triggers, anonymise cascade |
| TR2 | New `create_workspace_invitation` SECURITY DEFINER RPC (replaces direct `workspace_members` write) |
| TR3 | New `accept_workspace_invitation` SECURITY DEFINER RPC (writes `workspace_members` + marks invitation accepted) |
| TR4 | CSRF protection via `validateOrigin()` on all new POST routes |
| TR5 | `/invite/[token]` added to PUBLIC_PATHS in `lib/routes.ts` with exact-or-slash matching |
| TR6 | Token stored as SHA-256 hash; raw token in email URL; constant-time comparison on validation |
| TR7 | Column-level privilege protection: `accepted_at`, `token_hash`, `inviter_user_id` immutable after creation |
| TR8 | GDPR: `workspace_invitations` added to DSAR export allowlist + Art. 17 anonymise cascade |
| TR9 | Article 30 register updated with invite-email processing activity |
| TR10 | `/soleur:gdpr-gate` invoked at plan Phase 2.7 and work Phase 2 exit |
| TR11 | Redirect allowlist (Set-based exact match) for post-acceptance redirects |
| TR12 | `signInWithOtp` `shouldCreateUser` set deliberately based on invite vs. login context |

## Architecture

### Data Model

```
workspace_invitations
├── id (uuid PK)
├── workspace_id (uuid FK → workspaces)
├── inviter_user_id (uuid FK → auth.users, nullable for Art. 17)
├── invitee_email (text, nullable for Art. 17)
├── invitee_user_id (uuid FK → auth.users, nullable — set if invitee exists)
├── token_hash (text NOT NULL — SHA-256 of raw token)
├── role (text CHECK IN ('owner', 'member'))
├── expires_at (timestamptz NOT NULL)
├── accepted_at (timestamptz NULL)
├── declined_at (timestamptz NULL)
├── attestation_id (uuid FK → workspace_member_attestations, nullable)
└── created_at (timestamptz NOT NULL DEFAULT now())
```

### Flows

**Invite creation:**
1. Owner enters email in invite modal
2. POST `/api/workspace/invite-member` (CSRF gated, flag gated, owner check)
3. `createWorkspaceInvitation()` → generates token, hashes, writes `workspace_invitations` + attestation
4. Fire-and-forget: send invite email via Resend

**Existing user acceptance (via `/invite/[token]`):**
1. User clicks link → `/invite/[token]` page
2. Page fetches invitation details (workspace name, inviter) via token hash lookup
3. User clicks "Accept" → POST `/api/workspace/accept-invite`
4. `acceptWorkspaceInvitation()` → writes `workspace_members` row, marks invitation accepted
5. Fire-and-forget: send acceptance confirmation to inviter
6. Redirect to workspace dashboard

**Non-user signup + auto-join:**
1. Non-user clicks invite link → `/invite/[token]` shows workspace info + "Create account to join"
2. Signup flow with `redirectTo=/invite/[token]`
3. Post-signup callback detects invite token → auto-accepts → joins workspace
4. Redirect to workspace dashboard

**Existing user acceptance (via dashboard/settings):**
1. User logs in → middleware or page query checks `workspace_invitations` for pending invites
2. Dashboard banner or Settings notification appears
3. User clicks accept → same accept flow as above

## Security Considerations

- Token: 256-bit entropy, SHA-256 hashed in DB, single-use, 7-day expiry
- `/invite/[token]`: public route, no information disclosure on invalid tokens
- Workspace-scoped: token FK to workspace_id prevents cross-workspace access
- Attestation WORM: invite and acceptance both create attestation rows
- DSAR: invitations in export allowlist, anonymise cascade on account delete
