---
feature: invite-accept-membership-byok
issue: 4715
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-01-fix-keyless-invitee-membership-deadlock-plan.md
status: ready
---

# Tasks: Keyless Invitee Membership Deadlock + Owner Delegation Prompt

Single PR (#4713), no migration. TDD: failing test → code → green. Contract-before-consumer ordering. All tests under `test/**` (or `lib/**/*.test.ts`); component tests under `test/**/*.test.tsx` (happy-dom). Co-located `components/**/*.test.tsx` are NOT collected.

## Phase 0 — Preconditions
- [x] 0.1 Grep `vitest.config.ts` `include:` globs; confirm test placement targets.
- [x] 0.2 Grep `nextParam` validation at `callback/route.ts:64` (safeReturnTo); cite.
- [x] 0.3 Grep that the redirect path never references `FLAG_TEAM_WORKSPACE_INVITE` (TR4); record in PR body.

## Phase 1 — Shared predicate (Group A, contract first)
- [x] 1.1 RED: unit tests for `isInviteReturnTarget` (`/invite/abc`→true; `/dashboard`→false; `null`→false; `/invitedX`→false).
- [x] 1.2 GREEN: add `isInviteReturnTarget(nextHop)` to `lib/onboarding/setup-key-gate.ts`.

## Phase 2 — accept-terms redirect (Group A)
- [x] 2.1 RED: `getRedirectDestination` cases — keyless+invite→`/invite`; keyless+other/none→`/setup-key`; keyed→`nextHop ?? /dashboard`; keyless+open-redirect-body→`/setup-key` (nextHop null).
- [x] 2.2 GREEN: guard the setup-key wrap with `!isInviteReturnTarget(nextHop)` (`accept-terms/route.ts:41-46`).

## Phase 3 — callback redirect (Group A)
- [x] 3.1 RED: callback cases — T&C-unaccepted→`/accept-terms`; keyless-not-skipped+invite→`/invite`; keyless-not-skipped+none→`/setup-key`; keyless-**skipped**+invite→`/invite` (regression guard); keyed→unchanged.
- [x] 3.2 GREEN: edit ONLY the keyless-not-skipped branch (`callback/route.ts:259-260`): `redirectPath = isInviteReturnTarget(nextParam) ? nextParam : "/setup-key"`. Do not touch the skipped/keyed branches.

## Phase 4 — Accept-screen disclosure + J7 CTA (Group A)
- [x] 4.1 GREEN: add Art. 13 shared-data/billing line near `InviteActions` in `invite/[token]/page.tsx`; add forward CTA to the "Invitation not available" card.
- [x] 4.2 Test: disclosure string present; unavailable card renders a forward CTA.

## Phase 5 — TR2 ordering regression test (Group A)
- [x] 5.1 Test (exercising the redirect fns): no site returns `/invite/<t>` before T&C recorded. (TR4 = grep from 0.3, not a test.)
- [x] 5.2 Open-redirect reject-vector tests (raw + percent-decoded) green.

## Phase 6 — Member empty state (Group B)
- [x] 6.1 Extend `app/api/byok/effective-status/route.ts` to return `isSharedWorkspaceMember` (session-derived; preserve IDOR guard).
- [x] 6.2 RED: banner cases — shared-member keyless→joiner copy + "Add your own key"; pendingDelegation→consent branch (unchanged); solo→original copy.
- [x] 6.3 GREEN: update `components/dashboard/no-api-key-banner.tsx`.

## Phase 7 — Recovery banner on dashboard shell (Group B; REQUIRED)
- [x] 7.1 GREEN: client wrapper self-fetching `GET /api/workspace/pending-invites`, rendering `PendingInviteBanner`; mount in `(dashboard)/layout.tsx`; `usePathname().startsWith("/dashboard/chat")` → render nothing.
- [x] 7.2 Test: pending-invite user on `/dashboard` sees banner; Accept fires RPC; exactly one banner on chat routes.

## Phase 8 — Per-member own-key status (Group C, contract first)
- [x] 8.1 RED: resolver tests — own valid key→true; keyless→false; resolver error→false.
- [x] 8.2 GREEN: add `hasEffectiveKey` to `TeamMembershipRow` via `userHasEffectiveByokKey(r.user_id,{onErrorReturn:false})`. Own-key signal only; do NOT OR `delegationsByGrantee`.

## Phase 9 — Owner "Share a key" prompt (Group C)
- [x] 9.1 RED: row cases — keyless+undelegated+non-self→hint+CTA; `delegationFromMe`→no prompt; `hasEffectiveKey`→no prompt; self→no prompt.
- [x] 9.2 GREEN: `components/settings/team-membership-list.tsx` + `delegation-toggle.tsx` label "Share a key" (reuse toggle; GRANT-only, TR3). Low-emphasis "or ask them to add their own" link.

## Phase 10 — Gates
- [x] 10.1 `vitest run` (web-platform) + `tsc --noEmit` clean.
- [x] 10.2 Acceptance Criteria (plan) all checked.

## Post-merge (operator)
- P.1 Playwright (dev) new-user invite→signup→accept: `workspace_members` row lands, invite leaves Pending.
- P.2 Playwright (dev) existing-user/OAuth: callback returns `/invite/<token>`, does not drop `nextParam`.
