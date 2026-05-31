---
date: 2026-06-01
type: fix
issue: 4715
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
user_brand_critical: true
spec: knowledge-base/project/specs/feat-invite-accept-membership-byok/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-31-invite-accept-membership-byok-brainstorm.md
branch: feat-invite-accept-membership-byok
pr: 4713
---

# Fix: Keyless Invitee Membership Deadlock — Accept-First Reorder + Owner Delegation Prompt 🐛

## Overview

A keyless workspace invitee never completes membership acceptance. PR #4641 coupled
acceptance to a mandatory key+repo onboarding funnel, so an invitee with no paid
Anthropic account stalls at `/setup-key`, abandons, and lands in their own isolated
solo workspace. The owner's invite stays `Pending`; the invitee can't see the shared
workspace. The accept RPC, `/invite/<token>` page, and `/api/workspace/accept-invite`
route are all correct — they are **never reached**.

**Fix (one PR #4713, no migration), grouped by concern:**
- **Group A (brand-survival core):** redirect-precedence reorder so a validated
  `/invite/<token>` next-hop **outranks** the `/setup-key` onboarding gate. The
  invitee accepts → becomes a real `workspace_members` row → invite flips
  `Pending → Active` → lands in the shared workspace (tasks gated at chat-time).
- **Group B (member recovery & honest state):** keyless member sees a non-dead-end
  empty state (not the solo "buy a paid Anthropic account" copy) + a dashboard-shell
  recovery banner closes the abandon-at-`/invite` strand.
- **Group C (owner prompt):** per-member "Share a key" prompt on the Members tab
  (reuses the shipped `DelegationToggle`).

Completes the partial fix in PR #4641. Carries CPO/CLO/CTO sign-offs from the
2026-05-31 brainstorm (all GO); refined by plan-time spec-flow-analyzer + 3-agent
plan-review (see `## Plan Review` and Domain Review).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified this session) | Plan response |
|------------|----------------------------------|---------------|
| Strand point is `accept-terms/route.ts` `getRedirectDestination` (19-47) wrapping the invite hop in `/setup-key?redirectTo=` | **Confirmed** (route.ts:41-44). Keyless ⇒ `shouldRouteToSetupKey`=true ⇒ wraps `nextHop` into `/setup-key?redirectTo=`. | PR1 Phase 2: guard the wrap with `!isInviteReturnTarget(nextHop)`. |
| Mirror the fix in `callback/route.ts` (238-275) | **Confirmed + worse:** callback line 259-260 keyless-not-skipped branch sets `redirectPath = "/setup-key"` and **drops `nextParam` entirely** (no `redirectTo`). | PR1 Phase 3: honor an invite target in that branch. |
| `safeReturnTo()` already allowlists `/invite/` | **Confirmed** (`safe-return-to.ts:12` `ALLOWED_PREFIXES = ["/dashboard","/invite/"]`; per-hop raw+decoded reject guards). | PR1 reuses it; no new validator (avoid the "naive reuse" mistake the brainstorm flagged). |
| FR5: per-member key status via `userHasEffectiveByokKey(memberId,{onErrorReturn:false})`; never read `api_keys` directly | **Confirmed signature** (`byok-resolver.ts:215`). N RPC round-trips for small v1 lists. | Phase 8: use the helper as the **own-key** signal only. Phase 9 gates on `!hasEffectiveKey && !delegationFromMe`, so the delegation term is already covered by the existing `delegationFromMe` field — do NOT OR `delegationsByGrantee` (plan-review: sidesteps the own-default-workspace-context nuance entirely). |
| Phase 6 member-vs-solo copy needs membership context | **P0 (plan-review):** `no-api-key-banner.tsx` self-fetches `/api/byok/effective-status` which returns only `{hasEffectiveKey, pendingDelegation}` (IDOR-guarded). No membership signal. | Extend the endpoint with `isSharedWorkspaceMember` (session-derived, IDOR guard preserved). |
| Phase 7 banner mount on `(dashboard)/layout.tsx` | **P0 (plan-review):** that layout is `"use client"` — cannot run the service-role server fetch the chat layout uses. But `GET /api/workspace/pending-invites` **already exists**. | Client wrapper self-fetches the existing route (NoApiKeyBanner precedent); `usePathname` gates off chat routes (which already mount the banner server-side). |
| Owner prompt reuses the shipped per-member `DelegationToggle` (#4508) | **Confirmed:** `TeamMembershipRow` carries `delegationFromMe`/`delegationToMe` (resolver:14-25); toggle creates GRANT only. | PR2 Phase 7 surfaces the existing toggle behind a hint — no new grant/consent logic (TR3 satisfied by reuse). |
| No migration | **Confirmed** — app-layer routing + one resolver field + UI copy only. | All phases are TS/TSX; zero DDL. |

## User-Brand Impact

**If this lands broken, the user experiences:** a keyless invitee who accepts an
invite still lands in an empty isolated workspace (current live bug), OR — if the
redirect carried an unvalidated target — an open-redirect/phishing hop.

**If this leaks, the user's data/money is exposed via:** (a) membership written
without recorded T&C → a member reads shared workspace data with no lawful-basis
record; (b) an owner's BYOK key spent by a member before the member's recorded
consent.

**Brand-survival threshold:** `single-user incident` → `requires_cpo_signoff: true`
(CPO signed at 2026-05-31 brainstorm; `user-impact-reviewer` runs at PR review).

## Implementation Phases

**Single PR (#4713).** Plan-review (DHH, concurred by Simplicity) collapsed the original two-PR split: once member-copy (Phase 6) + recovery-banner (Phase 7) had to move into "PR1" to avoid a false-state window, the "brand-survival ships first" rationale dissolved — nothing in the owner-prompt blocks the redirect fix when it's one branch; merge when green. Phases are grouped A/B/C by concern, not by PR.

### Group A — Redirect-precedence fix (the brand-survival core; Phases 1-5)

**Phase 1 — Shared predicate (contract first).**
- `lib/onboarding/setup-key-gate.ts`: add `export function isInviteReturnTarget(nextHop: string \| null): boolean` returning `nextHop?.startsWith("/invite/") ?? false`. Co-located with `shouldRouteToSetupKey` (the file already documents itself as "shared by the two redirect gates"), so the "invite outranks setup-key" rule has one unit-tested home.
- RED→GREEN unit tests: `/invite/abc` → true; `/dashboard` → false; `null` → false; `/invitedX` → false (prefix boundary).

**Phase 2 — `accept-terms/route.ts` (new-user path).**
- In `getRedirectDestination` (19-47), guard the setup-key wrap:
  `if (!isInviteReturnTarget(nextHop) && shouldRouteToSetupKey({...})) { …setup-key… }` then `return nextHop ?? "/dashboard"`.
- `nextHop` is already `safeReturnTo`-validated at route.ts:68, so `isInviteReturnTarget` only ever sees a same-origin `/invite/` value.
- Tests: keyless + `/invite/<t>` → returns `/invite/<t>` (no setup-key wrap); keyless + no/other target → `/setup-key` (unchanged); keyed → `nextHop ?? /dashboard` (unchanged); keyless + open-redirect body → `nextHop` is `null` upstream → `/setup-key` (no leak).

**Phase 3 — `callback/route.ts` (existing-user / OAuth / magic-link path).**
- The bug is **only** the keyless-**not-skipped** branch (259-260: `redirectPath = "/setup-key"`, dropping `nextParam`). The keyless-**skipped** branch (268: `nextParam ?? "/dashboard"`) and the keyed branch (270-273) **already honor `nextParam`** — do NOT touch them (plan-review: avoid double-patching an already-correct branch).
- Edit only the `shouldRouteToSetupKey` branch: `redirectPath = isInviteReturnTarget(nextParam) ? nextParam : "/setup-key"`.
- `nextParam` is `safeReturnTo`-validated at `callback/route.ts:64` (confirmed by plan-review) — no new validation.
- Tests: T&C-unaccepted → `/accept-terms`; keyless-not-skipped + `/invite/<t>` → `/invite/<t>`; keyless-not-skipped + no invite → `/setup-key`; keyless-**skipped** + `/invite/<t>` → `/invite/<t>` (already correct — regression guard); keyed → unchanged.

**Phase 4 — Art. 13 disclosure on the accept screen (CLO guardrail / FR2).**
- `app/(public)/invite/[token]/page.tsx`: add a concise shared-data/billing line near `InviteActions`, e.g. *"Members share this workspace's data, agents, and billing."* Rendered co-temporally with the Accept button (not deferred to onboarding).
- **P2 (spec-flow J7):** add a forward CTA to the terminal "Invitation not available" card — "Go to your dashboard" when authenticated, "Sign in" otherwise — so an expired/used-link landing isn't a hard dead-end. Cheap, same file.
- Test: the disclosure string is present in the rendered invite page; the unavailable card renders a forward CTA.

**Phase 5 — TR2 ordering regression test.**
- **TR2 (T&C-before-membership):** exercise the redirect functions directly and assert neither site returns `/invite/<t>` while `tcAcceptedVersion !== TC_VERSION` (callback) / before the `accept_terms` RPC succeeds (accept-terms). Structurally true today; the test is the regression lock — **load-bearing** because `/invite` is in `PUBLIC_PATHS` so the middleware T&C gate does not fire there; the redirect ordering IS the consent guarantee.
- **TR4 (flag-independence):** NOT a test (plan-review — would pass trivially). The redirect keys on `nextHop` shape and never references `FLAG_TEAM_WORKSPACE_INVITE`. Verify once by grep at implementation time; record the grep result in the PR description.

### Group B — Member recovery & honest empty state (Phases 6-7)

**Phase 6 — Member non-dead-end empty state (FR3).** _[closes spec-flow J4: a newly-landed keyless member must not see the solo "buy a paid account" copy.]_
- **Data source (plan-review P0):** `no-api-key-banner.tsx` self-fetches `/api/byok/effective-status`, which today returns only `{hasEffectiveKey, pendingDelegation}` (IDOR-guarded, ignores client params). Extend that endpoint to also return `isSharedWorkspaceMember: boolean` (one membership lookup, session-derived userId only — preserve the IDOR guard). The banner has no other membership context.
- `components/dashboard/no-api-key-banner.tsx`: when `isSharedWorkspaceMember && !hasEffectiveKey && !pendingDelegation`, render *"You can browse this workspace, but running tasks needs an API key. Ask your workspace owner to share one, or add your own."* Keep the existing `pendingDelegation` branch (grant awaiting consent) and the solo (`!isSharedWorkspaceMember`) copy unchanged.
- Tests: shared-member keyless → joiner copy + "Add your own key"; pendingDelegation → consent branch (unchanged); solo → original copy unchanged.

**Phase 7 — Global recovery banner (FR6; REQUIRED — closes spec-flow J3).** _[an invitee who abandons at `/invite` reaches `/dashboard` with the accept RPC never called — the missing-writer-path class. At single-user threshold the strand must be closed, not narrowed.]_
- **Mechanism (plan-review P0 — client/server boundary):** `(dashboard)/layout.tsx` is `"use client"`, so it CANNOT run the service-role `getPendingInvitesForUser` server fetch the chat layout uses. Mirror the `NoApiKeyBanner` precedent: a small client wrapper self-fetches the **already-existing** `GET /api/workspace/pending-invites` route and renders `PendingInviteBanner` with the result. Mount that wrapper in `(dashboard)/layout.tsx`.
- **Double-render gate (direction matters):** the chat layout already mounts the banner via server fetch, so the NEW client mount backs off on chat routes — `usePathname().startsWith("/dashboard/chat")` → render nothing.
- Tests: pending-invite user on `/dashboard` (not `/dashboard/chat`) sees the banner; one-click Accept fires the RPC; chat route renders exactly one banner (no double-render).

### Group C — Owner delegation prompt (Phases 8-9)

**Phase 8 — Per-member own-key status (FR5; contract first).**
- `server/team-membership-resolver.ts`: add `hasEffectiveKey: boolean` to `TeamMembershipRow`, computed per member via `userHasEffectiveByokKey(r.user_id, {onErrorReturn: false})` (fail-closed for UI). **Scoped to the own-key signal** — Phase 9's existing `!delegationFromMe` already owns the delegation term, so do NOT additionally OR `delegationsByGrantee` (avoids the own-default-workspace-context nuance entirely; plan-review simplification). N round-trips is fine for v1's tiny member lists; batch only if lists grow. Do NOT read `api_keys` directly (per `2026-05-29-byok-delegation-aware-onboarding-gating`).
- Tests: member with own valid key → true; keyless member → false; resolver error → false.

**Phase 9 — Owner "Share a key" prompt (FR4).**
- `components/settings/team-membership-list.tsx` (+ `delegation-toggle.tsx` label): on a member row where `byokDelegationsEnabled && !isSelf && !hasEffectiveKey && !delegationFromMe`, render an inline hint (*"No API key yet — can view the workspace but can't run tasks."*) and surface the existing `DelegationToggle` labeled **"Share a key"**, plus a low-emphasis text link *"or ask them to add their own."* No modal, no auto-delegate, no new grant logic (TR3 — the toggle already creates GRANT only).
- Tests: keyless-undelegated member renders hint + CTA; already-delegated (`delegationFromMe`) renders no prompt; keyed member (`hasEffectiveKey`) renders no prompt; self row never prompts.

## Files to Edit

**Group A (redirect core):**
- `apps/web-platform/lib/onboarding/setup-key-gate.ts` (add `isInviteReturnTarget`)
- `apps/web-platform/app/api/accept-terms/route.ts` (`getRedirectDestination` guard)
- `apps/web-platform/app/(auth)/callback/route.ts` (keyless-not-skipped branch only)
- `apps/web-platform/app/(public)/invite/[token]/page.tsx` (Art. 13 disclosure + J7 forward CTA)

**Group B (member recovery & empty state):**
- `apps/web-platform/app/api/byok/effective-status/route.ts` (add `isSharedWorkspaceMember`)
- `apps/web-platform/components/dashboard/no-api-key-banner.tsx` (member copy)
- `apps/web-platform/app/(dashboard)/layout.tsx` (mount the self-fetching pending-invite wrapper)
- a small client wrapper for `PendingInviteBanner` that self-fetches `/api/workspace/pending-invites` (new file under `components/dashboard/`)

**Group C (owner prompt):**
- `apps/web-platform/server/team-membership-resolver.ts` (`hasEffectiveKey` field)
- `apps/web-platform/components/settings/team-membership-list.tsx` (owner prompt)
- `apps/web-platform/components/settings/delegation-toggle.tsx` ("Share a key" label)

**Already mounts the banner (do not duplicate):** `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` (server-fed) — Phase 7's client mount gates off chat routes via `usePathname`.

## Files to Create

- `vitest.config.ts` (verified): node project collects `test/**/*.test.ts` **and** `lib/**/*.test.ts`; component project is **happy-dom** (not jsdom) collecting `test/**/*.test.tsx`. So a `lib/` unit test co-located as `lib/onboarding/setup-key-gate.test.ts` IS collected; **`components/**/*.test.tsx` are NOT** — component tests go under `test/**/*.test.tsx`. Likely files: `lib/onboarding/setup-key-gate.test.ts` (or `test/onboarding/...`), `test/server/accept-terms-redirect.test.ts`, `test/server/callback-redirect.test.ts`, `test/components/settings/team-membership-list-share-key.test.tsx`, `test/components/dashboard/no-api-key-banner-member.test.tsx`, `test/components/dashboard/pending-invite-banner-recovery.test.tsx`.

## Open Code-Review Overlap

`#3739` (extract `reportSilentFallbackWithUser` helper — collapse 11-site
`withIsolationScope+setUser` duplication) touches `accept-terms/route.ts` and
`callback/route.ts`, both edited here. **Disposition: Acknowledge** — distinct
concern (a Sentry-helper refactor across 11 sites); folding it in would balloon a
brand-survival redirect fix into a cross-cutting refactor. The redirect edits do
not touch the `withIsolationScope` blocks. #3739 remains open.

## Acceptance Criteria

### Pre-merge (single PR #4713)
- [x] `isInviteReturnTarget` unit tests green (prefix boundary covered).
- [x] Keyless invitee through signup → T&C → lands on `/invite/<token>` (NOT `/setup-key`); accepting writes `workspace_members` and flips the invite out of Pending. Asserted via the accept-terms + callback redirect tests.
- [x] `/setup-key` still shown for keyless **non-invite** new signups (regression); keyless-**skipped** + invite still → `/invite` (branch untouched — regression guard).
- [x] Open-redirect reject-vector tests (raw + percent-decoded) green; no `/invite/` bypass.
- [x] TR2 ordering test (exercises the redirect fns): no site yields `/invite/<t>` before T&C recorded. (TR4 is a grep recorded in the PR description, not a test.)
- [x] Art. 13 disclosure renders on the invite page; "Invitation not available" card has a forward CTA (J7).
- [x] **(J4)** Keyless shared-member empty state shows joiner copy + "Add your own key" (driven by `isSharedWorkspaceMember` from effective-status); solo + pending-delegation copy unchanged.
- [x] **(J3)** Pending-invite user on `/dashboard` (not `/dashboard/chat`) sees `PendingInviteBanner`; one-click Accept fires the RPC; exactly one banner on chat routes (no double-render).
- [x] Owner sees hint + "Share a key" only for a keyless (`!hasEffectiveKey`), undelegated (`!delegationFromMe`), non-self member; `hasEffectiveKey` resolver tests green (own-key / keyless / error); TR3 (GRANT-only, no 074 consent-row write).
- [x] `vitest run` (web-platform) + `tsc --noEmit` clean.

### Post-merge (operator)
- [ ] Re-run the invite→signup→accept flow against **dev** via Playwright (new-user path); confirm the `workspace_members` row lands and the owner's invite leaves Pending (the box PR #4641 left unchecked). `Automation:` Playwright MCP against dev.
- [ ] **(spec-flow J2)** Playwright the existing-user/OAuth path: callback returns `/invite/<token>` and does NOT drop `nextParam` (the second, worse live bug). `Automation:` Playwright MCP against dev.

## Observability

```yaml
liveness_signal:
  what: existing accept-invite success path (workspace_members INSERT + accepted_at flip in accept_workspace_invitation RPC)
  cadence: per acceptance (event-driven)
  alert_target: none (success path); failures route via error_reporting below
  configured_in: apps/web-platform/app/api/workspace/accept-invite/route.ts (existing)
error_reporting:
  destination: Sentry via reportSilentFallback (existing at accept-terms/route.ts:90, byok-resolver.ts:250, callback/route.ts:227)
  fail_loud: yes — userHasEffectiveByokKey mirrors to Sentry on resolver error before returning onErrorReturn (resolver:250)
failure_modes:
  - mode: keyless invitee still routed to /setup-key (reorder regression)
    detection: accept-terms + callback redirect unit tests (CI); no new runtime signal needed — the redirect is deterministic on nextHop shape
    alert_route: CI red on PR
  - mode: per-member key resolver throws (PR2)
    detection: existing reportSilentFallback op=userHasEffectiveByokKey (Sentry)
    alert_route: Sentry feature:byok-resolver
logs:
  where: Sentry (errors) + Next.js server logs (request-scoped); no new log surface
  retention: existing Sentry/Better Stack retention
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/accept-terms-redirect.test.ts test/server/callback-redirect.test.ts"
  expected_output: "all redirect-precedence cases pass (keyless+invite → /invite, keyless+non-invite → /setup-key)"
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from 2026-05-31 brainstorm `## Domain Assessments`; all GO).

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** GO. Single load-bearing change = redirect-precedence reordering (invite target outranks `/setup-key`); do NOT suppress solo-workspace provisioning (`workspace.id===user.id` invariant). No migration. Owner prompt needs `hasEffectiveKey` via `userHasEffectiveByokKey` (never `api_keys` directly). Ship as two PRs.

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward) — satisfies Phase 2.7 GDPR gate at single-user threshold
**Assessment:** GO. BYOK lease is SQL-gated at `resolve_byok_key_owner` (083/084) independent of membership timing → moving membership earlier cannot reach the key path or enable pre-consent spend. Guardrails encoded: FR2 (Art. 13 disclosure at accept-time), TR2 (T&C-before-membership), TR3 (owner prompt creates GRANT only, never the grantee's 074 consent row). No new Art. 33 exposure.

### Product/UX Gate
**Tier:** advisory (modifies existing components: `team-membership-list.tsx`, `no-api-key-banner.tsx`; no new component files → no mechanical BLOCKING escalation)
**Decision:** reviewed — CPO assessed at brainstorm; spec-flow-analyzer run at plan time (brainstorm-CPO-recommended specialist)
**Agents invoked:** cpo (brainstorm carry-forward), spec-flow-analyzer (plan time)
**Skipped specialists:** ux-design-lead (inline copy/hint on existing components; CPO deemed wireframes non-blocking) — recorded, not silently dropped
**Pencil available:** N/A

#### Findings
CPO (brainstorm): accept-first → land keyless in the shared workspace (read access; tasks gated at chat-time) flips the owner invite to Active for free. Inline owner hint beside `DelegationToggle`; defer owner email notification; resist workspace-shared keys.

**spec-flow-analyzer (plan time) — folded in:**
- **P1 / J3 (closed):** the recovery banner was mounted only on `dashboard/chat/layout.tsx`; the post-accept landing is `/dashboard` under `(dashboard)/layout.tsx`, which doesn't mount it → an abandoner reaches a terminal state with the accept RPC never called (missing-writer-path). Resolution: Phase 7 promoted to REQUIRED, mounted on `(dashboard)/layout.tsx`, moved to PR1.
- **P1 / J4 (closed):** PR1-alone would show a keyless member the false solo "buy a paid account" copy. Resolution: member empty-state copy (Phase 6) moved into PR1.
- **P2 / J6-J7 (partially folded):** terminal "Invitation not available" card lacks a forward CTA → added to Phase 4. Mismatch notice already has "Sign in with a different account" (no change).
- **Confirmed safe:** reorder does NOT strand non-invite keyless new signups (regression-guarded); T&C-before-membership ordering intact; email-mismatch + expired gates independent of the reorder.

## Test Scenarios

1. New keyless user via invite link → signup → T&C → **lands on `/invite/<token>`** → Accept → member + invite Active.
2. Existing keyless user clicks invite → OAuth/magic-link → callback → `/invite/<token>` (not `/setup-key`).
3. Keyless **non-invite** new signup → `/setup-key` (regression guard).
4. Open-redirect payloads (raw + `%2F%2F`, `..`, `\`) in `redirectTo` → rejected, no off-origin hop.
5. Owner Members tab: keyless undelegated member → hint + "Share a key"; after grant → no prompt.
6. Member dashboard keyless → joiner empty-state copy (not solo "buy a paid account").

## Plan Review (DHH + Kieran + Code-Simplicity, applied)

- **Collapsed two PRs → one** (DHH P1, Simplicity concurred): once member-copy + recovery-banner had to join "PR1" to avoid a false-state window, the "ships first" rationale dissolved. One branch, merge when green.
- **Phase 6 P0 (Kieran):** `no-api-key-banner.tsx` self-fetches `/api/byok/effective-status` which has no membership context → added `isSharedWorkspaceMember` to that endpoint.
- **Phase 7 P0 (Kieran+Simplicity):** `(dashboard)/layout.tsx` is `"use client"` and can't run the server fetch → client wrapper self-fetches the **already-existing** `/api/workspace/pending-invites`; `usePathname` gates off chat routes.
- **Phase 8 (Simplicity):** scoped `hasEffectiveKey` to the own-key signal only; dropped the OR-`delegationsByGrantee` probe (Phase 9's `!delegationFromMe` already owns delegation) — removes the workspace-context rabbit hole.
- **TR4 (DHH+Simplicity):** demoted from a trivially-passing test to a grep recorded in the PR description. TR2 kept (real consent guarantee given the `/invite` PUBLIC_PATHS middleware bypass).
- **Phase 3 (Kieran):** clarified the fix targets ONLY the keyless-not-skipped branch; the skipped branch already honors `nextParam` — added a regression-guard test, no edit.
- **Kept (DHH endorsed):** `isInviteReturnTarget` shared predicate (co-located with `shouldRouteToSetupKey`), reuse of `safeReturnTo`, and the explicit refusal to abstract a shared `resolvePostOnboardingRedirect`.

## Risks & Sharp Edges

- **Middleware T&C public-path trap (`#4638` learning):** `/invite` is in `PUBLIC_PATHS`, so the middleware T&C gate does NOT fire there. Accept-first is safe **only because** both redirect sites record T&C *before* returning an `/invite/` target (callback:239 routes to `/accept-terms` first; accept-terms records via the RPC before `getRedirectDestination`). Phase 5's TR2 test locks this; any future refactor that routes to `/invite` ahead of T&C reintroduces a consent bypass.
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — section is filled above.
- **`userHasEffectiveByokKey` workspace-context nuance** (Research Reconciliation row 4) — deepen-plan data-integrity decision; cosmetic worst case.
- **Test placement:** co-located `components/**/*.test.tsx` are silently skipped by `vitest.config.ts`; all tests go under `test/`. Phase 0 grep the `include:` globs.
- **Do NOT abstract a shared `resolvePostOnboardingRedirect` across the two sites** — callback carries `connect-repo`/`repo_status` logic accept-terms lacks; share only the `isInviteReturnTarget` predicate (the brainstorm's "naive reuse" warning).
