---
date: 2026-05-27
status: committed
decision: bundled-members-tab-plus-invite-acceptance-flow
brand_survival_threshold: single-user incident
lane: cross-domain
parent: knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
related:
  - knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md
  - knowledge-base/project/brainstorms/2026-05-22-feat-team-workspace-legal-scaffolding-brainstorm.md
  - knowledge-base/project/learnings/2026-03-18-supabase-resend-email-configuration.md
  - knowledge-base/project/learnings/2026-03-20-server-side-tc-acceptance-security-pattern.md
closes_issues:
  - 4516
  - 4519
---

# Workspace Invite Acceptance + Members Tab Brainstorm

## What We're Building

A complete team workspace invite flow that bundles #4516 (Members tab UI) and #4519 (invite acceptance + email notifications) into a single PR. The scope includes:

1. **Settings Members tab** — flag-gated sidebar link, member list page with role display, invite modal accepting any email address
2. **`workspace_invitations` table** — separate from `workspace_members`, stores pending invites with hashed tokens, expiry, and status tracking
3. **Invite acceptance flow** — `/invite/[token]` public page handling both authenticated and unauthenticated users, with signup + auto-join for non-users
4. **Email notifications** — invite email to invitee + acceptance confirmation to inviter via Resend (existing SDK integration at `server/notifications.ts`)
5. **In-app acceptance surfaces** — dashboard banner for pending invites, Settings notification dot, pending invites section in Team page

## Why This Approach

The parent brainstorm (2026-05-21) shipped the organizations + workspace_members schema, RLS predicates, WORM attestation pattern, and feature flag infrastructure. PR #4518 (auth prereqs) merged 2026-05-27. The Members tab UI and invite acceptance are natural completions of the team workspace feature.

Bundling both pieces avoids shipping a Members tab with a synchronous-only invite flow that would need immediate rework for the token-based acceptance. The architecture decisions (separate invitations table, token hashing, public route) apply regardless of timing — capturing them now while the context from #4516's auth work is fresh eliminates rework.

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — all three failure modes apply:

1. **Cross-tenant read via token** — invite tokens that map to workspace IDs could grant access to the wrong workspace if not properly scoped. Mitigated by separate `workspace_invitations` table (no `workspace_members` row exists until acceptance) + token bound to specific workspace_id + invitee_email.
2. **Token compromise / auth bypass** — leaked invite URL allows unauthorized workspace join. Mitigated by SHA-256 hashed storage, single-use enforcement, 7-day expiry, constant-time comparison.
3. **Non-functional worst case** — invite flow breaks, users cannot accept invites. Safe failure mode (no data exposure).

**Threshold:** `single-user incident` — one mis-scoped token that leaks workspace contents to an unauthorized user is brand-survival territory.

## Lane

`cross-domain` (auto-set by USER_BRAND_CRITICAL=true).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** The deferral rationale was sound — re-evaluation trigger (external prospect requesting invite-by-email) hasn't fired. However, operator overrides to bundle #4516 + #4519 now, capturing architecture while context is fresh. Token security model and non-user signup flow are the product-critical surfaces. The invite modal should accept any email (removing the "must have account" constraint).

### Engineering (CTO)

**Summary:** Strongly recommends separate `workspace_invitations` table over adding status column to `workspace_members`. 66 non-test TypeScript files reference `workspace_members`; the `is_workspace_member()` helper is the RLS substrate for every workspace-scoped table — adding a status filter cascades to every RLS policy. Separate table has zero regression surface. Crypto-random tokens (SHA-256 hashed in DB), 7-day expiry, single-use. Direct Resend fire-and-forget matching existing `server/notifications.ts` pattern. Total estimate: 10-14 days for bundled scope.

### Legal (CLO)

**Summary:** GDPR gate required per `hr-gdpr-gate-on-regulated-data-surfaces`. Resend DPA already signed (AUTO, 2026-04-13, compliance-posture.md line 63) — processing purpose needs expansion from "review gate notifications" to include "workspace invite notifications." Article 30 register needs new processing activity. Legal basis: contract performance (Art. 6(1)(b)) for existing users; legitimate interest (Art. 6(1)(f)) for non-user invitees. `/soleur:gdpr-gate` must run at plan Phase 2.7 and work Phase 2 exit.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope | Bundle #4516 (Members tab) + #4519 (invite acceptance) in one PR | Avoids shipping synchronous-only invite that needs immediate rework; architecture decisions apply regardless |
| 2 | Token storage | Separate `workspace_invitations` table | 66 existing `workspace_members` consumers; `is_workspace_member()` is RLS substrate; separate table = zero regression risk |
| 3 | Token format | `crypto.randomBytes(32).toString('base64url')`, SHA-256 hashed in DB | Existing pattern from `kb-share.ts`; DB leak doesn't compromise unaccepted tokens |
| 4 | Token expiry | 7 days, single-use (`accepted_at IS NULL AND declined_at IS NULL AND expires_at > now()`) | Industry standard; balance between convenience and security |
| 5 | Non-user invitees | Signup + auto-join: `/invite/[token]` → signup flow with token preserved → post-signup callback auto-accepts | Best UX for external onboarding; `signInWithOtp` `shouldCreateUser` must be set deliberately |
| 6 | Invite modal | Accept any email address (remove "must have account" constraint) | Invite email with token link handles both existing and new users |
| 7 | Acceptance surfaces | Dashboard banner + Settings notification dot + Team page pending section + `/invite/[token]` page | Full coverage; delegation acceptance modal as UI template |
| 8 | Email types | Invite notification (to invitee) + acceptance confirmation (to inviter) | Two email types, different recipients |
| 9 | Email sending | Direct Resend API, fire-and-forget, following `server/notifications.ts` pattern | Existing infrastructure; invite write succeeds regardless of email delivery |
| 10 | RPC architecture | New `create_workspace_invitation` RPC + `accept_workspace_invitation` RPC; existing `invite_workspace_member` deprecated | Clean separation of create-invite from create-membership |
| 11 | CSRF/security | `validateOrigin()` + `rejectCsrf()` on all POST routes; exact-or-slash path matching; Set-based redirect allowlist | Learnings from T&C acceptance, middleware bypass, and open redirect patterns |
| 12 | Implementation order | Database-first, UI-last: migration → server → email → API routes → public page → Members tab → acceptance surfaces → GDPR | Data model solid before UI wiring |
| 13 | Legal | Resend DPA already signed; expand processing purpose; Article 30 update; GDPR gate at plan Phase 2.7 | CLO assessment |

## Non-Goals

- SSO/SAML/SCIM (Enterprise tier)
- Invite expiry reminder emails (YAGNI — add when evidence shows invites expire unused)
- Bulk invite (CSV upload, API batch) — single invites only
- Invite revocation UI for the inviter (can be added later; token expiry handles stale invites)
- Rate limiting on invite creation (defer until abuse signal)
- Custom invite email templates / branding per workspace
- Inngest queue for email (direct Resend is sufficient for invite volume)

## Open Questions

1. **Callback route extension.** The `/callback/route.ts` PKCE handler must check for a pending invite token after signup. How should the token be preserved through the OAuth/OTP flow? Likely `redirectTo` query param with the `/invite/[token]` URL.
2. **Attestation flow change.** Current `invite_workspace_member` RPC creates the WORM attestation row at invite time. With the new flow, should the attestation be created at invite time (capturing the inviter's act of inviting) or at acceptance time (capturing the acceptance consent)? Likely both — invite attestation at create, acceptance attestation at accept.
3. **Column-level privilege protection.** `accepted_at`, `token_hash`, `inviter_user_id` on `workspace_invitations` must be immutable after creation. Use column-level grant revocation per learning `2026-03-20-supabase-column-level-grant-override.md`.
4. **T&C enforcement on invite acceptance.** User accepting an invite must also have accepted current T&C version. The middleware check handles this, but the `/invite/[token]` page needs to route through T&C acceptance if needed.
5. **RESEND_API_KEY availability.** Currently managed via Doppler. Verify it's available in the main app process (not just Inngest workers).

## Cross-Domain Dependencies

| From | To | Dependency |
|---|---|---|
| CTO | CLO | GDPR gate at plan Phase 2.7 and work Phase 2 exit |
| CLO | legal-document-generator | Article 30 register update, DPD processing purpose expansion |
| CTO | #4516 | Bundled — Members tab UI is part of this scope |
| CTO | #4518 | MERGED — auth prereqs are on main |
| CTO | #4289 | MERGED — legal scaffolding (ToS 2.2.0, AUP §5.5, Side Letter) shipped |

## Existing Infrastructure (verified on main)

- **Resend SDK**: `server/notifications.ts` — `getResend()` singleton, 3 email types in production, `notifications@soleur.ai` sender
- **Token pattern**: `server/kb-share.ts` — `randomBytes(32).toString('base64url')`
- **WORM pattern**: migration 058 — `workspace_member_attestations` with anonymise cascade
- **CSRF**: `lib/auth/validate-origin.ts` — `validateOrigin()` + `rejectCsrf()`
- **Feature flag**: `team-workspace-invite` in Flagsmith with per-org targeting
- **Acceptance modal template**: `components/settings/delegation-acceptance-modal.tsx`
- **Public page template**: `app/shared/[token]/page.tsx`
- **Auth callback**: `app/(auth)/callback/route.ts` — PKCE code exchange

## Visual Design

Wireframes created via ux-design-lead (Phase 3.55):

- **Design file:** `knowledge-base/product/design/command-center/workspace-invite-acceptance.pen`
- **Screenshots:** `knowledge-base/product/design/command-center/screenshots/`
  - `12-settings-sidebar-team-link.png` — Settings sidebar with Team link
  - `13-team-members-page.png` — Team Members page with member list + pending invites
  - `14-invite-member-modal.png` — Invite modal with email, role, attestation
  - `15-dashboard-pending-invite-banner.png` — Pending invite banner on dashboard
  - `16-invite-landing-authenticated.png` — /invite/[token] for authenticated users
  - `17-invite-landing-unauthenticated.png` — /invite/[token] for unauthenticated users
  - `18-invite-email-template.png` — HTML invite email template

## Session Errors

1. **CPO false negative on invite code existence.** CPO agent reported "no such code was found in the codebase" for `inviteWorkspaceMember()` and `invite-member/route.ts`. Both exist on main at `apps/web-platform/server/workspace-membership.ts` and `apps/web-platform/app/api/workspace/invite-member/route.ts`. Agent likely had a CWD/search-scope issue.
2. **CLO stale Resend DPA assessment.** CLO assessed Resend as "NOT IN SCOPE" for DPA. The compliance posture was already updated (2026-04-13) with Resend DPA signed — "Automatic DPA via Terms of Service (Section 7: Data Processing)." Only processing-purpose expansion needed, not DPA signing.
