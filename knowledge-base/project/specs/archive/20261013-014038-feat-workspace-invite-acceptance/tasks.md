---
plan: knowledge-base/project/plans/2026-05-27-feat-workspace-invite-acceptance-plan.md
created: 2026-05-27
---

# Tasks: Workspace Invite Acceptance + Members Tab

## Phase 1: Database Migration

- [ ] 1.1 Create `075_workspace_invitations.sql` with table definition, indexes, column privileges
- [ ] 1.2 Add RLS policies (deny-default, invitee SELECT)
- [ ] 1.3 Add WORM trigger (reject UPDATE/DELETE except Art. 17 anonymise shape)
- [ ] 1.4 Create `create_workspace_invitation` SECURITY DEFINER RPC (owner validation, duplicate check, attestation write)
- [ ] 1.5 Create `accept_workspace_invitation` SECURITY DEFINER RPC (expiry check, single-use enforcement, workspace_members INSERT)
- [ ] 1.6 Create `decline_workspace_invitation` SECURITY DEFINER RPC (set declined_at)
- [ ] 1.7 Create `anonymise_workspace_invitations` SECURITY DEFINER RPC
- [ ] 1.8 Create `075_workspace_invitations.down.sql` rollback
- [ ] 1.9 Apply migration to local dev DB and verify

## Phase 2: Server Layer

- [ ] 2.1 Create `server/workspace-invitations.ts` with `generateInviteToken()`, `hashToken()`, `lookupInvitationByToken()`, `getPendingInvitesForUser()`
- [ ] 2.2 Add `createWorkspaceInvitation()` to `server/workspace-membership.ts` (calls RPC, returns token)
- [ ] 2.3 Add `acceptWorkspaceInvitation()` to `server/workspace-membership.ts` (calls RPC)
- [ ] 2.4 Add `declineWorkspaceInvitation()` to `server/workspace-membership.ts` (calls RPC)
- [ ] 2.5 Add `sendInviteEmail()` to `server/notifications.ts` (inline HTML, fire-and-forget)
- [ ] 2.6 Add `sendInviteAcceptedEmail()` to `server/notifications.ts` (inline HTML, fire-and-forget)
- [ ] 2.7 Add `workspace_invitations` to `server/dsar-export-allowlist.ts`
- [ ] 2.8 Add `anonymise_workspace_invitations` call to `server/account-delete.ts` cascade

## Phase 3: API Routes

- [ ] 3.1 Refactor `app/api/workspace/invite-member/route.ts` — use `createWorkspaceInvitation()` + fire-and-forget email
- [ ] 3.2 Create `app/api/workspace/accept-invite/route.ts` — CSRF, auth, call `acceptWorkspaceInvitation()`
- [ ] 3.3 Create `app/api/workspace/decline-invite/route.ts` — CSRF, auth, call `declineWorkspaceInvitation()`
- [ ] 3.4 Create `app/api/workspace/pending-invites/route.ts` — GET, auth, return pending invites for user

## Phase 4: Public Invite Page

- [ ] 4.1 Add `/invite` to `PUBLIC_PATHS` in `lib/routes.ts`
- [ ] 4.2 Create `app/(public)/invite/[token]/page.tsx` — server component: hash token, lookup, render
- [ ] 4.3 Create `app/(public)/invite/[token]/invite-actions.tsx` — client component: accept/decline buttons
- [ ] 4.4 Handle invalid/expired token — generic "no longer valid" message (no info disclosure)
- [ ] 4.5 Handle unauthenticated user — "Create account to join" CTA → `/signup?redirectTo=/invite/[token]`
- [ ] 4.6 Extend `app/(auth)/callback/route.ts` — detect `/invite/[token]` in redirectTo, auto-accept after signup

## Phase 5: Members Tab UI

- [ ] 5.1 Create `app/(dashboard)/dashboard/settings/team/page.tsx` — server component with flag gate
- [ ] 5.2 Add Team link to `app/(dashboard)/dashboard/settings/layout.tsx` (flag-gated via `resolveMembersTab()`)
- [ ] 5.3 Add Team nav item to `components/settings/settings-shell.tsx` with notification dot
- [ ] 5.4 Create `components/settings/team-members-list.tsx` — member table with avatar, name, email, role badge, date
- [ ] 5.5 Create `components/settings/pending-invites-list.tsx` — pending invites section with expiry, revoke
- [ ] 5.6 Refactor `components/settings/invite-member-modal.tsx` — accept any email, use new API, add attestation checkbox

## Phase 6: Dashboard Acceptance Surfaces

- [ ] 6.1 Create `components/dashboard/pending-invite-banner.tsx` — dismissible info banner with accept/decline
- [ ] 6.2 Integrate banner in `app/(dashboard)/dashboard/chat/layout.tsx` — server-side pending invites query

## Phase 7: GDPR Compliance

- [ ] 7.1 Update `knowledge-base/legal/article-30-register.md` — add invite processing activity
- [ ] 7.2 Update `docs/legal/privacy-policy.md` — add invite data to Section 4.7
- [ ] 7.3 Update `docs/legal/data-protection-disclosure.md` — expand Resend processing purpose
- [ ] 7.4 Update `knowledge-base/legal/compliance-posture.md` — expand Resend purpose from "review gate notifications" to include "workspace invite notifications"

## Phase 8: Tests

- [ ] 8.1 Create `test/workspace-invitations.test.ts` — unit tests for token gen, hashing, server functions
- [ ] 8.2 Create `test/api/accept-invite.test.ts` — API route tests (CSRF, auth, single-use, expiry)
- [ ] 8.3 Update `test/team-membership-resolver.test.ts` — verify pending invites excluded from member counts
- [ ] 8.4 Create `e2e/workspace-invite.e2e.ts` — full flow E2E tests
- [ ] 8.5 Run full test suite, fix any regressions
