---
feature: invite-accept-membership-byok
date: 2026-05-31
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-05-31-invite-accept-membership-byok-brainstorm.md
---

# Spec: Keyless Invitee Membership Deadlock + Owner Delegation Prompt

## Problem Statement

A keyless workspace invitee never completes membership acceptance. PR #4641
coupled acceptance to a mandatory key+repo onboarding funnel
(`accept-terms → /setup-key?redirectTo=<invite> → connect-repo → /invite`). An
invitee with no paid Anthropic account stalls at `/setup-key`, abandons, and on
next login lands in their own isolated solo workspace. Result: the owner's invite
stays `Pending` and the invitee can't see the shared workspace. The accept RPC,
`/invite/[token]` page, and `/api/workspace/accept-invite` route are all correct
but never reached.

## Goals

- G1: A keyless invitee becomes a real `workspace_members` row immediately after
  signup + T&C, landing in the **shared** workspace (not an isolated solo one).
- G2: The owner's invite transitions `Pending → Active` as a direct consequence.
- G3: A keyless member sees a non-dead-end empty state and the owner is prompted
  to delegate a BYOK key (post-membership, consent-gated).
- G4: No regression to the existing-user invite path or the #4638/#4641 T&C-first
  ordering; no new open-redirect surface.

## Non-Goals

- NG1: Suppressing solo-workspace provisioning (`workspace.id === user.id` is a
  permanent invariant; accept *adds* a membership, doesn't replace home workspace).
- NG2: BYOK delegation at invite time (architecturally locked: DB CHECK requires
  both parties be members; consent-gated lease).
- NG3: Workspace-shared keys (keys are per-user HKDF on userId).
- NG4: Re-running `connect-repo`/`setup-key` for invitees (repo is workspace-level).
- NG5: Owner email/push notification on keyless join (deferred follow-up).
- NG6: Any schema/migration change.

## Functional Requirements

- FR1: A valid `/invite/<token>` next-hop short-circuits to the invite page
  BEFORE `shouldRouteToSetupKey` is consulted. Edit `accept-terms/route.ts`
  `getRedirectDestination` (19-47) to return the invite hop directly (unwind the
  `/setup-key?redirectTo=` wrapper) when `nextHop` matches `/invite/`; mirror in
  `callback/route.ts:238-275`. (Maps: G1, G2)
- FR2: Accept screen renders the shared-data/billing visibility disclosure
  (Art. 13) co-temporally with the Accept action. (Maps: CLO guardrail)
- FR3: Member-side keyless empty state replaces the solo "requires a separate
  paid Anthropic account" copy with joiner-appropriate copy ("browse the
  workspace; running tasks needs a key — ask your owner to share one, or add your
  own"). Reuse the `pendingDelegation` branch + `no-api-key-banner.tsx`. (Maps: G3)
- FR4: Members tab surfaces, per member row, a keyless indicator + "Share a key"
  CTA (reusing the existing `DelegationToggle`) when the member has no effective
  key AND no inbound delegation. Secondary low-emphasis "or ask them to add their
  own" text link. No modal, no auto-delegate. (Maps: G3)
- FR5: Membership resolver gains a `hasEffectiveKey` field computed via
  `userHasEffectiveByokKey(memberUserId, {onErrorReturn:false})` — never reading
  `api_keys` directly. (Maps: G3)
- FR6: Optionally mount `PendingInviteBanner` on the dashboard shell (not only
  `dashboard/chat/layout.tsx`) as defense-in-depth recovery. (Maps: G1; defer if
  FR1 fully resolves)

## Technical Requirements

- TR1: Every redirect hop re-validates via `safeReturnTo()` (allowlist already
  includes `/invite/`); reject-vector tests on raw + percent-decoded forms are
  mandatory (open-redirect / phishing surface).
- TR2: T&C-record-before-membership-write ordering is preserved and asserted by
  test; a refactor must not reorder it.
- TR3: Owner delegation prompt code path creates a `byok_delegations` GRANT only
  and is forbidden from writing any `byok_delegation_acceptances` (074) row.
- TR4: Confirm the accept-first redirect is NOT gated behind
  `FLAG_TEAM_WORKSPACE_INVITE` (flag-OFF invitees must not be stranded).
- TR5: No migration. App-layer routing + resolver field + UI only.

## Delivery (two PRs)

- **PR1 — redirect-precedence fix** (FR1, FR2, TR1, TR2, TR4): brand-survival
  item; ships first, independent of UI.
- **PR2 — owner delegation prompt + member empty state** (FR3, FR4, FR5, TR3;
  FR6 optional): closes the onboarding loop using shipped delegation infra.

## Edit Sites (from CTO assessment)

- `apps/web-platform/app/api/accept-terms/route.ts` (19-47, 103)
- `apps/web-platform/app/(auth)/callback/route.ts` (236, 238-275, 317-389)
- `apps/web-platform/lib/onboarding/setup-key-gate.ts` (`shouldRouteToSetupKey`)
- `apps/web-platform/lib/safe-return-to.ts`
- `apps/web-platform/server/byok-resolver.ts` (`userHasEffectiveByokKey`, ~215)
- `apps/web-platform/server/team-membership-resolver.ts`,
  `app/api/workspace/list-memberships/route.ts`,
  `components/settings/team-membership-list.tsx`,
  `components/settings/delegation-toggle.tsx`
- `apps/web-platform/components/dashboard/no-api-key-banner.tsx`
- `apps/web-platform/components/dashboard/pending-invite-banner.tsx` (FR6)

## User-Brand Impact

- **Artifact:** the post-onboarding redirect destination for a keyless invitee +
  their `workspace_members` membership + (PR2) the owner's BYOK key spend.
- **Vector:** keyless invitee stranded in isolated workspace (current live bug);
  open-redirect/phishing if a carried target were unvalidated; cross-tenant data
  exposure if membership were written without recorded T&C; owner key drained if
  delegation auto-fired without grantee consent.
- **Mitigation:** per-hop `safeReturnTo()` re-validation; T&C-before-membership
  invariant; owner prompt creates GRANT only (lease stays SQL-gated on grantee
  consent + cap + withdrawal at `resolve_byok_key_owner`).
- **Brand-survival threshold:** `single-user incident`
