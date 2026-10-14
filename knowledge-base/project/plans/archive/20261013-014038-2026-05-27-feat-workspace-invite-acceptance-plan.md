---
title: "feat: Workspace Invite Acceptance + Members Tab"
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
bundles:
  - 4516
  - 4519
created: 2026-05-27
brainstorm: knowledge-base/project/brainstorms/2026-05-27-workspace-invite-acceptance-brainstorm.md
spec: knowledge-base/project/specs/feat-workspace-invite-acceptance/spec.md
---

# feat: Workspace Invite Acceptance + Members Tab

## Overview

Ship a complete team workspace invite flow bundling #4516 (Members tab UI) and #4519 (invite acceptance + email notifications). The feature adds a `workspace_invitations` table for pending invites, a `/invite/[token]` public landing page with signup + auto-join, email notifications via Resend, and a flag-gated Members tab in Settings.

**Brainstorm carry-forward:** 13 key decisions locked in `2026-05-27-workspace-invite-acceptance-brainstorm.md`. Architecture: separate `workspace_invitations` table (not status column on workspace_members), crypto-random tokens SHA-256 hashed, direct Resend fire-and-forget.

## User-Brand Impact

**If this lands broken, the user experiences:** an invite token that grants access to someone else's workspace, exposing their KB, chat history, BYOK key material, and cost ledger.

**If this leaks, the user's data is exposed via:** a compromised invite token URL allowing an unauthorized person to join a workspace and read all workspace-scoped data.

**Brand-survival threshold:** single-user incident — one mis-scoped token that leaks workspace contents to an unauthorized user is brand-survival territory.

## Implementation Phases

### Phase 1: Database Migration (075_workspace_invitations.sql)

Create `workspace_invitations` table with WORM triggers, RLS policies, and RPCs.

**Files to create:**
- `apps/web-platform/supabase/migrations/075_workspace_invitations.sql`
- `apps/web-platform/supabase/migrations/075_workspace_invitations.down.sql`

**Migration contents:**
1. `workspace_invitations` table (schema from spec)
2. RLS: deny all for `authenticated`; SELECT for invitee via `invitee_user_id = auth.uid()` OR `invitee_email = (SELECT email FROM auth.users WHERE id = auth.uid())`
3. WORM trigger: reject UPDATE/DELETE except Art. 17 anonymise shape (NOT NULL → NULL on PII columns)
4. `create_workspace_invitation(p_workspace_id, p_invitee_email, p_role, p_token_hash, p_attestation_text)` SECURITY DEFINER RPC — validates caller is owner, checks no duplicate pending invite, writes invitation + attestation
5. `accept_workspace_invitation(p_invitation_id, p_user_id)` SECURITY DEFINER RPC — validates token not expired/used, writes `workspace_members` row, sets `accepted_at`
6. `decline_workspace_invitation(p_invitation_id)` SECURITY DEFINER RPC — sets `declined_at`
7. `anonymise_workspace_invitations(p_user_id)` SECURITY DEFINER RPC — NULLs PII columns for Art. 17
8. Indexes: `(invitee_email, workspace_id)` for duplicate check, `(invitee_user_id)` for pending-invite queries, `(token_hash)` for token lookup
9. Column-level privileges: REVOKE ALL on table from authenticated, GRANT SELECT on non-PII columns

**Pattern precedent:** migration 058 (`workspace_member_attestations`) — same WORM trigger shape, same anonymise pattern, same service-role-only write discipline.

### Phase 2: Server Layer

**Files to create:**
- `apps/web-platform/server/workspace-invitations.ts`

**Files to edit:**
- `apps/web-platform/server/workspace-membership.ts` — deprecate old `inviteWorkspaceMember()`, add `createWorkspaceInvitation()` + `acceptWorkspaceInvitation()` + `declineWorkspaceInvitation()`
- `apps/web-platform/server/notifications.ts` — add `sendInviteEmail()` + `sendInviteAcceptedEmail()`
- `apps/web-platform/server/dsar-export-allowlist.ts` — add `workspace_invitations` to export list
- `apps/web-platform/server/account-delete.ts` — add `anonymise_workspace_invitations` to cascade

**Server module (`workspace-invitations.ts`):**
- `generateInviteToken()` — `crypto.randomBytes(32).toString('base64url')`
- `hashToken(token)` — `crypto.createHash('sha256').update(token).digest('hex')`
- `lookupInvitationByToken(tokenHash)` — service-role SELECT with workspace/inviter join
- `getPendingInvitesForUser(userId, email)` — SELECT where `invitee_user_id = userId OR invitee_email = email` AND `accepted_at IS NULL AND declined_at IS NULL AND expires_at > now()`

**Email functions (in `notifications.ts`):**
- `sendInviteEmail(inviteeEmail, inviterName, workspaceName, token)` — fire-and-forget, inline HTML template matching existing style
- `sendInviteAcceptedEmail(inviterUserId, inviteeName, workspaceName)` — fire-and-forget to inviter

### Phase 3: API Routes

**Files to create:**
- `apps/web-platform/app/api/workspace/accept-invite/route.ts`
- `apps/web-platform/app/api/workspace/decline-invite/route.ts`
- `apps/web-platform/app/api/workspace/pending-invites/route.ts`

**Files to edit:**
- `apps/web-platform/app/api/workspace/invite-member/route.ts` — refactor to use `create_workspace_invitation` RPC + fire-and-forget email

**Route contracts:**
- `POST /api/workspace/accept-invite` — body: `{ invitationId }`. Auth required. CSRF gated. Calls `acceptWorkspaceInvitation`. Fire-and-forget: `sendInviteAcceptedEmail`.
- `POST /api/workspace/decline-invite` — body: `{ invitationId }`. Auth required. CSRF gated. Calls `declineWorkspaceInvitation`.
- `GET /api/workspace/pending-invites` — Auth required. Returns pending invites for current user.
- `POST /api/workspace/invite-member` (refactored) — generates token, calls `create_workspace_invitation` RPC, fire-and-forget: `sendInviteEmail`.

### Phase 4: Public Invite Page

**Files to create:**
- `apps/web-platform/app/(public)/invite/[token]/page.tsx` — server component
- `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx` — client component for accept/decline buttons

**Files to edit:**
- `apps/web-platform/lib/routes.ts` — add `/invite` to `PUBLIC_PATHS`
- `apps/web-platform/app/(auth)/callback/route.ts` — check for pending invite token in `redirectTo` after signup, auto-accept

**Page behavior:**
- Server component: hash token, lookup invitation, fetch workspace name + inviter name
- If token invalid/expired: show generic "This invitation is no longer valid" (no info disclosure)
- If user authenticated: show accept/decline buttons (client component)
- If user unauthenticated: show "Create account to join" CTA → redirect to `/signup?redirectTo=/invite/[token]`
- Post-acceptance: redirect to `/dashboard/settings/team`

### Phase 5: Members Tab UI

**Files to create:**
- `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx`
- `apps/web-platform/components/settings/team-members-list.tsx`
- `apps/web-platform/components/settings/pending-invites-list.tsx`

**Files to edit:**
- `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` — add Team link with flag gate
- `apps/web-platform/components/settings/settings-shell.tsx` — add Team nav item + notification dot
- `apps/web-platform/components/settings/invite-member-modal.tsx` — refactor: remove "must have account" text, accept any email, use new API

**Team page sections:**
1. Header: "Team" + member count + "Invite member" button
2. Active members table: avatar, name, email, role badge, join date
3. Pending invites section: email, sent date, expiry countdown, "Revoke" button

### Phase 6: Dashboard Acceptance Surfaces

**Files to create:**
- `apps/web-platform/components/dashboard/pending-invite-banner.tsx`

**Files to edit:**
- `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` — render `PendingInviteBanner` at top of content area (query pending invites server-side)

**Banner behavior:**
- Query `getPendingInvitesForUser` in the layout server component
- If pending invites exist: render dismissible info banner with inviter name, workspace name, Accept/Decline buttons
- Accept/Decline use the same `/api/workspace/accept-invite` and `/api/workspace/decline-invite` routes

### Phase 7: GDPR Compliance

**Files to edit:**
- `knowledge-base/legal/article-30-register.md` — add PA-N: workspace invite email delivery processing activity
- `docs/legal/privacy-policy.md` — add invite data to Section 4.7
- `docs/legal/data-protection-disclosure.md` — expand Resend processing purpose

**Legal basis:** Contract performance (Art. 6(1)(b)) for existing-user invites; legitimate interest (Art. 6(1)(f)) for non-user invitees.

### Phase 8: Tests

**Files to create:**
- `apps/web-platform/test/workspace-invitations.test.ts` — unit tests for token generation, hashing, server functions
- `apps/web-platform/test/api/accept-invite.test.ts` — API route tests
- `apps/web-platform/test/api/invite-member-refactored.test.ts` — refactored invite route tests
- `apps/web-platform/e2e/workspace-invite.e2e.ts` — E2E: invite flow, accept flow, decline flow

**Test coverage:**
- Token generation: 32 bytes, base64url format
- Token hashing: SHA-256, deterministic
- Create invitation: owner-only, no duplicate pending, expiry set
- Accept invitation: single-use, expired rejection, wrong user rejection, workspace_members row created
- Decline: marks declined, can re-invite after decline
- Email: fire-and-forget, continues on email failure
- Public page: invalid token → generic error, expired → generic error
- CSRF: all POST routes reject missing/invalid origin

## Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/supabase/migrations/075_workspace_invitations.sql` | Migration: table, RLS, WORM trigger, RPCs, anonymise |
| `apps/web-platform/supabase/migrations/075_workspace_invitations.down.sql` | Rollback migration |
| `apps/web-platform/server/workspace-invitations.ts` | Token generation, hashing, lookup helpers |
| `apps/web-platform/app/api/workspace/accept-invite/route.ts` | Accept invite API route |
| `apps/web-platform/app/api/workspace/decline-invite/route.ts` | Decline invite API route |
| `apps/web-platform/app/api/workspace/pending-invites/route.ts` | Get pending invites for user |
| `apps/web-platform/app/(public)/invite/[token]/page.tsx` | Public invite landing page |
| `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx` | Client component for accept/decline |
| `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` | Team settings page |
| `apps/web-platform/components/settings/team-members-list.tsx` | Member list component |
| `apps/web-platform/components/settings/pending-invites-list.tsx` | Pending invites section |
| `apps/web-platform/components/dashboard/pending-invite-banner.tsx` | Dashboard pending invite banner |
| `apps/web-platform/test/workspace-invitations.test.ts` | Unit tests |
| `apps/web-platform/test/api/accept-invite.test.ts` | API route tests |
| `apps/web-platform/e2e/workspace-invite.e2e.ts` | E2E tests |

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/server/workspace-membership.ts` | Add `createWorkspaceInvitation()`, `acceptWorkspaceInvitation()`, `declineWorkspaceInvitation()` |
| `apps/web-platform/server/notifications.ts` | Add `sendInviteEmail()`, `sendInviteAcceptedEmail()` |
| `apps/web-platform/app/api/workspace/invite-member/route.ts` | Refactor to use new invitation RPC + email |
| `apps/web-platform/lib/routes.ts` | Add `/invite` to PUBLIC_PATHS |
| `apps/web-platform/app/(auth)/callback/route.ts` | Auto-accept invite after signup via redirectTo |
| `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` | Add Team link (flag-gated) |
| `apps/web-platform/components/settings/settings-shell.tsx` | Add Team nav item + notification dot |
| `apps/web-platform/components/settings/invite-member-modal.tsx` | Remove "must have account", use new API |
| `apps/web-platform/server/dsar-export-allowlist.ts` | Add `workspace_invitations` |
| `apps/web-platform/server/account-delete.ts` | Add anonymise cascade |
| `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` | Render PendingInviteBanner |
| `knowledge-base/legal/article-30-register.md` | Add invite processing activity |
| `docs/legal/privacy-policy.md` | Add invite data category |
| `docs/legal/data-protection-disclosure.md` | Expand Resend purpose |

## Open Code-Review Overlap

None — no open `code-review` labeled issues touch the files in scope.

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Product (CPO) — carry-forward

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Operator overrides deferral to bundle now. Token security + non-user signup are product-critical surfaces. Invite modal accepts any email.

### Engineering (CTO) — carry-forward

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Separate `workspace_invitations` table (66 consumer audit avoided). Crypto-random SHA-256 hashed tokens, 7-day expiry. Direct Resend. 10-14 day estimate.

### Legal (CLO) — carry-forward

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** GDPR gate required. Resend DPA signed. Article 30 needs invite processing activity. Legal basis: contract performance for existing users, legitimate interest for non-users.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55)
**Skipped specialists:** spec-flow-analyzer (brainstorm carry-forward covers flows), copywriter (no emotional/persuasive copy)
**Pencil available:** yes

#### Findings

7 wireframes produced covering all UI surfaces. Design uses existing Soleur brand tokens (#2563eb primary, system font stack, dark sidebar pattern). Delegation acceptance modal is the template for accept/decline interactions.

## Acceptance Criteria

| AC | Criterion | Verification |
|----|-----------|--------------|
| AC1 | Settings sidebar shows "Team" when flag is ON | `curl -s /dashboard/settings \| grep -c "Team"` returns 1 with flag enabled |
| AC2 | Team page lists workspace members | Navigate to `/dashboard/settings/team`, verify member rows render |
| AC3 | Invite modal sends email | POST `/api/workspace/invite-member` → check Resend delivery log |
| AC4 | Token is 32 bytes base64url, SHA-256 hashed in DB | `SELECT length(decode(token_hash, 'hex')) FROM workspace_invitations` = 32 |
| AC5 | `/invite/[token]` shows workspace info for valid token | Navigate to invite URL, verify workspace name + inviter name render |
| AC6 | `/invite/[token]` shows generic error for invalid/expired token | Navigate with bad token, verify no workspace info leaked |
| AC7 | Authenticated user can accept from invite page | Click Accept → verify `workspace_members` row created |
| AC8 | Unauthenticated user redirects to signup | Navigate unauthenticated → verify redirect to `/signup?redirectTo=/invite/[token]` |
| AC9 | Post-signup auto-accepts invite | Complete signup via invite link → verify auto-joined workspace |
| AC10 | Dashboard banner shows pending invites | Login with pending invite → verify banner renders |
| AC11 | Accept from banner works | Click Accept on banner → verify membership created + banner dismissed |
| AC12 | Invitation is single-use | Accept, then try accepting same token again → 404/invalid |
| AC13 | Expired invitation rejected | Wait past expiry → accept returns error |
| AC14 | CSRF protection on all POST routes | POST without Origin header → 403 |
| AC15 | `workspace_invitations` in DSAR export | Run DSAR export → verify invitations included |
| AC16 | Art. 17 anonymise cascade works | Delete account → verify PII columns NULL in workspace_invitations |
| AC17 | Acceptance confirmation email sent to inviter | Accept invite → check Resend log for inviter email |

## Test Scenarios

1. **Happy path (existing user):** Owner invites → email sent → invitee clicks link → accepts → member created → confirmation sent
2. **Happy path (new user):** Owner invites → email sent → non-user clicks link → signs up → auto-accepts → member created
3. **Decline flow:** Invitee declines → invitation marked declined → inviter can re-invite
4. **Expired token:** Token past 7 days → accept/decline return error
5. **Double-accept:** Accept same invitation twice → second attempt returns error
6. **Wrong user:** User A clicks invite meant for User B (by email) → should still work (token is bearer)
7. **Cross-workspace:** Token for workspace A cannot grant access to workspace B
8. **WORM integrity:** UPDATE/DELETE on workspace_invitations → trigger rejects (except anonymise)
9. **Flag gate:** Team link invisible when `team-workspace-invite` flag is OFF

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Token brute-force on `/invite/[token]` | 256-bit entropy = 2^256 space. No timing side-channel (constant-time hash comparison). Generic error on invalid. |
| Email delivery failure | Fire-and-forget with `reportSilentFallback`. Invite record exists regardless. User can share link manually. |
| signInWithOtp creates unexpected users | Set `shouldCreateUser` deliberately in signup context only, not login. |
| Open redirect after acceptance | Set-based redirect allowlist. Only `/dashboard/*` paths allowed. |
| RESEND_API_KEY not available in main process | Verify via Doppler before merge. Already used by `notifications.ts` in production (review gate + DSAR emails). |

## Observability

```yaml
liveness_signal: invite creation rate (Resend delivery events); workspace_invitations row count growth
error_reporting: Sentry via reportSilentFallback on email failure; structured pino log on RPC errors
failure_modes:
  - mode: email delivery failure
    detection: reportSilentFallback mirrors to Sentry
    alert_route: Sentry alert rule (notifications feature tag)
  - mode: RPC failure (create/accept/decline)
    detection: pino error log + API 500 response
    alert_route: Better Stack log alert on workspace-invitations error level
  - mode: token lookup returning stale/wrong data
    detection: acceptance creates workspace_members row — absence after accept is a data integrity failure
    alert_route: Sentry via reportSilentFallback in accept flow
logs: pino structured (server/workspace-invitations.ts) → Better Stack via existing transport | 30-day retention
discoverability_test:
  command: "curl -s https://app.soleur.ai/api/workspace/pending-invites -H 'Authorization: Bearer <jwt>' | jq '.invites | length'"
  expected_output: "0 (or count of pending invites for authenticated user)"
```

## Sharp Edges

- The `invite_workspace_member` RPC (migration 058) currently writes directly to `workspace_members`. This PR deprecates it in favor of `create_workspace_invitation` + `accept_workspace_invitation`. The old RPC remains for backward compatibility but the route no longer calls it.
- `search_path = public, pg_temp` MUST be pinned on all SECURITY DEFINER functions per `cq-pg-security-definer-search-path-pin-pg-temp`.
- The auth callback auto-accept MUST happen AFTER T&C acceptance in the redirect chain. Order: signup → callback → accept-terms → auto-accept-invite → dashboard.
- Token comparison MUST use constant-time comparison (hash then compare hashes, not raw token comparison) to prevent timing attacks.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
