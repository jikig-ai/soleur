---
date: 2026-05-29
type: fix
status: draft
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
branch: feat-one-shot-fix-invite-accept-workspace-linking
related_brainstorm: knowledge-base/project/brainstorms/2026-05-27-workspace-invite-acceptance-brainstorm.md
---

# fix: Invite acceptance loses redirect target — new-user signup never joins inviter's workspace 🐛

> **REVISED 2026-05-29 (post-#4638).** While this was in flight, PR #4638
> ("invited users trip OTP email rate limit on first sign-in") merged to main
> and implemented most of this fix's redirect threading on the `redirectTo`
> param: invite links → `/signup?redirectTo=` → `/accept-terms?redirectTo=` →
> callback `next=` → login `redirectTo`. BUT #4638 deliberately **drops the
> target for a keyless (brand-new) invitee** — `/api/accept-terms` returns
> `/setup-key` when the user has no API key (its comment: "the invitee re-opens
> the invite link post-onboarding"), and `setup-key → connect-repo` was
> hardcoded. So the EXACT reported case (jean.deruelle, new account, no key)
> was NOT auto-reconnected. **This branch was reset onto #4638 and now ships
> only the residual delta** (operator-approved "thread through funnel" option,
> 2026-05-29): `/api/accept-terms` threads the validated target onto
> `/setup-key?redirectTo=…`, and `setup-key` carries it to
> `/connect-repo?return_to=…` (connect-repo's existing terminal consumer). T&C
> is still recorded BEFORE the invite is accepted (#4638's ordering preserved);
> the invitee auto-returns to `/invite/<token>` after key + repo setup. The
> original "land on /invite directly, accept before T&C" design below was NOT
> taken (it would have accepted the invite before T&C was recorded and
> conflicted with #4638's shipped `redirectTo` convention).

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Root-Cause Analysis, Acceptance Criteria (AC1-AC3), Files to Edit, Design Decision, Sharp Edges
**Method:** Direct codebase verification (auth/onboarding flow, existing redirect validator, login-form/signup/oauth components). No SQL/infra/scheduled-job changes → precedent-diff (4.4), network-outage (4.5), PAT-halt (4.8) gates non-applicable. User-Brand Impact (4.6) + Observability (4.7) gates PASS.

### Key Improvements (load-bearing corrections vs. round-1 plan)

1. **AC3 validator is NOT net-new — an existing one exists but is TOO NARROW.** `apps/web-platform/lib/safe-return-to.ts` already implements `safeReturnTo(param)` and rejects open-redirects (absolute, `//`, `\`, `..`). BUT its allowlist is `param.startsWith("/dashboard")` ONLY — it would **reject `/invite/<token>` and silently fall back to `/dashboard`**. The fix MUST widen this allowlist (or add a sibling) to also permit the `/invite/<token>` shape. Naively "reuse the existing validator" would re-break the redirect.
2. **Param-name drift: `redirectTo` (invite links) vs `return_to` (codebase convention).** `invite-actions.tsx` emits `?redirectTo=…`, but the canonical param across the app is `return_to` (consumed by `connect-repo/page.tsx:461,473,549` via `safeReturnTo`). The fix should standardize on ONE — recommend renaming the invite links to `return_to` to match the existing validator/convention (smaller blast radius than teaching every consumer a second param name).
3. **THIRD loss point found: login OTP verify.** `components/auth/login-form.tsx:119` does `router.push("/dashboard")` on OTP-verify success — same bug as signup. The **Sign in with the invited account** invite link (`invite-actions.tsx:107`) therefore ALSO drops the target. Round-1 plan listed login as "verify/maybe"; it is confirmed broken.
4. **OAuth path nuance.** `oauth-buttons.tsx:75` sets Supabase `redirectTo: ${origin}/callback` — that is the *Supabase post-auth callback URL*, NOT the app's internal return target. To preserve the invite through OAuth, the internal target must ride as a query param ON that callback URL (e.g. `${origin}/callback?return_to=/invite/<token>`) and be consumed by `callback/route.ts`.
5. **Login "no account" bounce drops the target too.** `login-form.tsx:78-85` redirects a no-account email to `/signup?email=…&reason=…` — it must carry `return_to` forward or the invitee who clicks Sign-in-then-gets-bounced-to-signup loses the invite again.

## Overview

A user invited to the `ops@jikigai.com` workspace (`jean.deruelle@gmail.com`) received the
invite email, opened `/invite/[token]`, clicked **Create an account to join**, completed
email-OTP signup, signed in — and landed in a brand-new, isolated workspace of his own
(API-key onboarding → project onboarding → empty dashboard). The invite remained under
**Pending invites** in the inviter's Team settings; it was never accepted/consumed.

The acceptance RPC (`accept_workspace_invitation`) and the `POST /api/workspace/accept-invite`
route are **correct and intact** — they were simply **never called**. The new-user path
loses the `redirectTo=/invite/[token]` parameter, so the freshly-created user is funneled
straight into their own onboarding instead of being returned to the invite page where the
Accept button (and thus the RPC) lives.

This is a behavioral fix to the **already-built** invite flow (PR for #4516/#4519). No new
infrastructure, no schema change, no new vendor surface.

## Root-Cause Analysis (verified against code on this branch)

The `/invite/[token]` page renders, for unauthenticated visitors, two links
(`apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx:54-73`):

- `/signup?redirectTo=/invite/${token}`
- `/login?redirectTo=/invite/${token}`

The `redirectTo` query param is **dropped at three independent points** — neither the signup
page, the login form, nor the auth callback consumes it. A `grep -rn "redirectTo"` across
`app/(auth)` and `app/(public)` returns **only** the three producer links in
`invite-actions.tsx` — there is **zero** consumer of `redirectTo` anywhere in the auth or
onboarding flow. (Note the param-name drift: the app's canonical return param is `return_to`,
consumed by `safeReturnTo()` in `connect-repo/page.tsx` — the invite links diverge by using
`redirectTo`, which no validator/consumer reads.)

### Loss point 1 — signup OTP-verify success (email-OTP path; the path the bug report hit)

`apps/web-platform/app/(auth)/signup/page.tsx:68-96` — `handleVerifyOtp` on success does:

```ts
router.push("/accept-terms");   // line 94 — hardcoded, ignores searchParams.get("redirectTo")
```

The signup form never reads `redirectTo`. After OTP verify, the user is pushed into the
onboarding funnel for their **own** new workspace.

### Loss point 2 — auth callback (OAuth / PKCE / magic-link code-exchange path)

`apps/web-platform/app/(auth)/callback/route.ts:53-280` — the `GET` handler exchanges the
code, calls `ensureWorkspaceProvisioned()` (which **provisions a fresh workspace** for the
new user, `route.ts:227, 299-371`), then routes through a hardcoded onboarding funnel
(`/accept-terms` → `/setup-key` → `/connect-repo` → `/dashboard`, `route.ts:229-259`). It
**never reads any return-destination param** from the request URL. Any invitee who signed up
via an OAuth provider also loses the invite (the OAuth path lands on `/callback`, not on the
signup form). Note: `oauth-buttons.tsx:75` sets Supabase's `redirectTo: ${origin}/callback` —
that is the Supabase post-auth callback URL, NOT an app-internal return target; to survive
OAuth the internal target must be appended to that callback URL as a query param.

### Loss point 3 — login OTP-verify success (the **Sign in** invite link path)

`apps/web-platform/components/auth/login-form.tsx:119` — `handleVerifyOtp` success does
`router.push("/dashboard")`, ignoring any return param. The invite's **Sign in with the
invited account** link (`invite-actions.tsx:107`, `:66`) round-trips through this form and
loses the target. Additionally, `login-form.tsx:78-85` bounces a no-account email to
`/signup?email=…&reason=…` and drops the return target there too.

### Why the user got an isolated workspace

`ensureWorkspaceProvisioned()` (`callback/route.ts:299-371`) and/or the `handle_new_user()`
DB trigger create a `workspaces` row with `workspaces.id = owner_user_id` and a `workspace_members`
`owner` row for the brand-new user (migration 053 §1.1.7 N2 invariant, cited at
`callback/route.ts:321-323`). That is correct default behavior for a genuinely new signup —
but for an **invitee** it is exactly wrong, because the accept RPC was never reached to add
the user to the **inviter's** workspace. The invite row's `accepted_at` stays NULL, so it
keeps showing under **Pending invites** (`server/workspace-invitations.ts:78-93` filters on
`accepted_at IS NULL`).

### What is NOT broken (verified — do not "fix")

- `accept_workspace_invitation` RPC (`migrations/075_workspace_invitations.sql:272+`): locks
  the row `FOR UPDATE`, checks expiry / already-accepted / already-member, inserts into
  `workspace_members`, writes the acceptance attestation. Correct.
- `POST /api/workspace/accept-invite` (`app/api/workspace/accept-invite/route.ts`): CSRF gate,
  auth gate, invitee-identity gate (user_id OR lower-cased email), maps reasons to statuses.
  Correct.
- The authenticated-invitee path (already logged in as the invited email, opens the link):
  works today — `isIntendedInvitee` is true, the Accept button POSTs the route. The bug is
  strictly the **new-user / re-auth** path that round-trips through signup/login/callback.

## Research Reconciliation — Spec vs. Codebase

The 2026-05-27 brainstorm (`workspace-invite-acceptance-brainstorm.md`) flagged this exact
gap as an **unresolved Open Question**, never closed in the shipped PR:

| Brainstorm claim | Codebase reality (this branch) | Plan response |
|---|---|---|
| Decision #5: "Non-user invitees: signup + auto-join — `/invite/[token]` → signup flow with token preserved → post-signup callback auto-accepts" | The token is **not** preserved through signup/callback. No callback auto-accept exists. | This is the bug. Fix = thread the return target through signup + callback (and onboarding funnel). |
| Open Question #1: "Callback route extension — must check for a pending invite token after signup. How should the token be preserved through the OAuth/OTP flow? Likely `redirectTo` query param." | `redirectTo` is produced by `invite-actions.tsx` but consumed **nowhere**. Callback ignores it. | Resolve OQ#1: define a safe internal-redirect contract and consume it in both signup-verify and callback. |
| Decision #4/RPC: accept requires `accepted_at IS NULL AND ... AND expires_at > now()`, single-use | RPC enforces exactly this; route gates invitee identity | No change to RPC/route — they are correct; only the *call* is missing. |

No external premises to validate beyond the brainstorm (no `#N` blockers cited in the request).
**Premise Validation:** the invite UI, RPC, and accept route all exist on this branch
(`git grep` confirmed) — this is a *fix* (behavioral wiring gap), not a *build*.

## User-Brand Impact

**If this lands broken, the user experiences:** an invited teammate creates an account, is
dropped into an empty isolated workspace, sees onboarding prompts ("Connect your API key",
"No repo connected"), and never reaches the shared workspace — while the inviter sees the
invite stuck on "Pending" forever. The flagship multi-user feature appears completely broken
on first use.

**If this leaks, the user's data/workflow is exposed via:** the redirect-target parameter is
an **open-redirect / token-routing surface**. If `redirectTo` is consumed without strict
validation, a crafted `redirectTo=https://evil.example` could phish a freshly-authenticated
session, or a `redirectTo` pointing at a *different* workspace's invite path could be used to
mis-route. The accept RPC's invitee-identity gate is the security floor, but the redirect
consumer MUST be locked to **internal same-origin paths only** (allowlist `/invite/<token>`
shape, reject absolute URLs, protocol-relative `//host`, and backslash variants).

**Brand-survival threshold:** `single-user incident` — carried forward from the brainstorm
(`USER_BRAND_CRITICAL=true`). One mis-routed redirect or one invitee landing in the wrong
workspace is brand-survival territory. **CPO sign-off required at plan time before `/work`.**
`user-impact-reviewer` runs at review time.

## Acceptance Criteria

### Pre-merge (PR)

> **Implementation note (work Phase 0):** `/invite` is in `PUBLIC_PATHS`
> (`apps/web-platform/lib/routes.ts`) — it has NO T&C / auth funnel gate. A
> freshly-authenticated invitee can therefore land on `/invite/<token>`
> **directly** post-auth and click Accept; T&C is enforced by middleware only
> when they subsequently enter `/dashboard*`. This makes the plan's
> "carry-forward through the onboarding funnel" (accept-terms/setup-key edits)
> **unnecessary** — the smaller, correct fix threads the validated `return_to`
> through the three auth-completion points (signup-verify, login-verify,
> callback) + the OAuth callback URL, and lets the invitee reach the existing
> Accept button directly. `accept-terms` / `setup-key` are left untouched.
> **Decision: Option A (land-on-invite-page, explicit Accept)** — per CTO/CPO
> assessment in Domain Review.

- [x] **AC1 — Signup OTP verify preserves return target.** `signup/page.tsx` `handleVerifyOtp`
  success redirects to a **validated** `redirectTo` (internal-path only) when present, else
  `/accept-terms` as today. Verify: `grep -n "redirectTo" app/(auth)/signup/page.tsx` shows
  the param is read and passed to a validator before any `router.push`.
- [x] **AC2 — Callback preserves return target through the onboarding funnel.** The auth
  callback (`callback/route.ts`) reads a validated return target and, when the user has
  completed the mandatory gates (T&C accepted), redirects to it instead of `/dashboard`;
  when a gate is still pending (`/accept-terms`/`/setup-key`/`/connect-repo`), the target is
  **carried forward** (re-appended) so it survives the funnel. Verify by branch test in
  `test/app/auth/callback-route-branches.test.ts`.
- [x] **AC3 — Redirect-target validation reuses + widens the existing validator.** The
  canonical validator already exists at `apps/web-platform/lib/safe-return-to.ts`
  (`safeReturnTo(param)`) and already rejects absolute URLs, protocol-relative (`//`),
  backslash (`\`), and `..`. Its allowlist is currently `param.startsWith("/dashboard")` ONLY
  — which **rejects `/invite/<token>` and falls back to `/dashboard`**. Widen the allowlist to
  also accept the `/invite/<token>` shape (e.g. `/invite/` prefix with a safe token charset),
  keeping all existing rejection vectors. Do NOT add a parallel validator. Unit test
  (`safe-return-to.test.ts`) must cover: valid `/dashboard*`, valid `/invite/<token>`,
  `https://evil`, `//evil`, `/\evil`, `\\evil`, `/invite/../dashboard` → each maps to the
  expected accept/reject. Verify: `grep -n "/invite" apps/web-platform/lib/safe-return-to.ts`
  shows the widened allowlist.
- [ ] **AC4 — New-user invitee becomes a member.** End-to-end (or integration-with-mocks, NOT
  against prod per `hr-dev-prd-distinct-supabase-projects`): invited email → `/invite/[token]`
  → signup → OTP verify → lands back on `/invite/[token]` authenticated as the invitee →
  Accept → `accept_workspace_invitation` is invoked → `workspace_members` gains a row for the
  invitee in the **inviter's** workspace → invite `accepted_at` is set → it disappears from
  Pending. Assert the RPC-call / membership-row shape, not just an HTTP 200.
- [x] **AC5 — Auto-accept vs. land-on-page decision is explicit.** The plan/work must choose
  ONE and document it (see "Design Decision" below). If auto-accept-on-callback is chosen,
  AC4's "Accept click" step is replaced by "callback invokes accept and redirects to
  `/dashboard/settings/team`"; the invitee-identity gate (email match) MUST still hold inside
  the auto-accept path.
- [x] **AC6 — Existing authenticated-invitee path unchanged.** The already-logged-in-as-invitee
  happy path still works (regression guard): `test/invite-actions-gating.test.tsx` and any
  accept-route test stay green.
- [x] **AC7 — Onboarding funnel still fires for genuine new signups.** A non-invitee new
  signup (no `redirectTo`) still goes `/accept-terms` → `/setup-key` → `/connect-repo` →
  `/dashboard`. No `redirectTo` ⇒ identical behavior to today.

### Post-merge (operator)

- [ ] **AC8 — Live verification (automatable, NOT a manual checklist).** Re-run the original
  scenario via Playwright MCP against the dev environment OR re-invite a synthetic dev-only
  address and confirm membership lands. `Automation: feasible` via `mcp__playwright__*` +
  `mcp__plugin_supabase_supabase__*` (read `workspace_members` for the new row). Must run
  against **dev**, never prod.

## Design Decision (resolve in plan-review / work Phase 0)

Two valid fixes; pick one and record the rationale:

- **Option A — Land back on `/invite/[token]`, user clicks Accept (minimal).** Thread a
  validated `redirectTo` through signup-verify + callback (+ funnel carry-forward). The
  invitee returns to the invite page authenticated and matched; the existing Accept button
  POSTs the route. Smallest diff; reuses the entire existing accept path; the user makes an
  explicit consent click (good for the WORM acceptance attestation). **Recommended.**
- **Option B — Auto-accept in the callback.** Callback detects the pending-invite token,
  calls `acceptWorkspaceInvitation` server-side after the identity gate, redirects to the
  team page. Fewer clicks, but moves the consent act out of an explicit UI action (attestation
  semantics — see brainstorm Open Question #2), and adds an accept call-site that must
  duplicate the invitee-identity gate. More surface, more review cost.

**Lean Option A** unless plan-review/CPO prefers the zero-click UX. Either way, the
return-target validator (AC3) is mandatory.

## Files to Edit

- `apps/web-platform/lib/safe-return-to.ts` — **widen the allowlist** to accept `/invite/<token>`
  in addition to `/dashboard*`, preserving every existing rejection vector (`//`, `\`, `..`,
  absolute). This is the single security-critical edit.
- `apps/web-platform/lib/safe-return-to.test.ts` (exists? grep — add if absent) — add
  `/invite/<token>` accept + reject-vector cases (AC3).
- `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx` — standardize the link
  param from `redirectTo` to `return_to` (3 links: `:58`, `:66`, `:107`) to match the codebase
  convention + the validator's consumer.
- `apps/web-platform/app/(auth)/signup/page.tsx` — read `return_to` via `useSearchParams`,
  pass through `safeReturnTo`, use it in `handleVerifyOtp` success instead of the hardcoded
  `/accept-terms` (loss point 1).
- `apps/web-platform/components/auth/login-form.tsx` — read `return_to`, validate, use it in
  `handleVerifyOtp` success instead of hardcoded `router.push("/dashboard")` (`:119`, loss
  point 3); carry `return_to` forward on the no-account → `/signup` bounce (`:78-85`).
- `apps/web-platform/components/auth/oauth-buttons.tsx` — append the validated `return_to` to
  the Supabase `redirectTo` callback URL (`:75`) so it survives the OAuth round-trip.
- `apps/web-platform/app/(auth)/callback/route.ts` — read + validate `return_to` from the
  request URL; redirect to it after all mandatory gates pass (instead of `/dashboard`); carry
  it forward when funneling to `/accept-terms`/`/setup-key`/`/connect-repo` (loss point 2).
- **(Option B only)** `apps/web-platform/server/workspace-invitations.ts` /
  `callback/route.ts` — add a guarded server-side accept call (must re-apply the invitee-email
  identity gate).
- The accept-terms / setup-key / connect-repo onboarding pages — **only if** they perform
  their own post-completion `router.push` that would drop the carried-forward `return_to`.
  `connect-repo/page.tsx` already consumes `return_to` via `safeReturnTo` (`:461,473,549`) —
  read it to confirm it forwards rather than hardcodes; check accept-terms + setup-key the
  same way and list any that need the carry-forward threaded.

## Files to Create

- `apps/web-platform/lib/safe-return-to.test.ts` — unit test for AC3 vectors if the file does
  not already exist (grep first). Cases: valid `/dashboard*`, valid `/invite/<token>`,
  `https://evil`, `//evil`, `/\evil`, `\\evil`, `/invite/../dashboard`. (Runner per
  `package.json scripts.test` — vitest expected; verify at work time.)
- `apps/web-platform/test/.../invite-new-user-join.test.ts` — AC4 integration test
  (mocked Supabase; asserts membership row + `accepted_at` set + invite leaves Pending).

## Open Code-Review Overlap

To be populated at work time: run
`gh issue list --label code-review --state open --json number,title,body --limit 200`
and `jq` each file path in **Files to Edit** against the bodies. Record matches + disposition
(fold-in / acknowledge / defer), or `None`.

## Hypotheses

(No network-outage trigger pattern — skipped.) Primary hypothesis is **confirmed by code
reading**, not speculative: the `redirectTo` param has zero consumers in the auth/onboarding
flow. The only open question is Option A vs B and whether login + onboarding pages need the
carry-forward (resolved by reading those files at work Phase 0).

## Observability

```yaml
liveness_signal:
  what: "POST /api/workspace/accept-invite 200 + new workspace_members row for invitee"
  cadence: per-acceptance (event-driven, not periodic)
  alert_target: "Sentry — existing reportSilentFallback path in accept-invite route on RPC failure"
  configured_in: "app/api/workspace/accept-invite/route.ts (existing reason->status map) + server/workspace-invitations.ts log.error"
error_reporting:
  destination: "Sentry via reportSilentFallback / warnSilentFallback (existing observability module)"
  fail_loud: "callback redirect-validator rejection MUST emit warnSilentFallback (feature: auth, op: redirect_target_rejected) so a phishing-attempt redirect is visible, not silently dropped"
failure_modes:
  - mode: "redirectTo dropped (regression of this fix)"
    detection: "invite-new-user-join integration test (AC4) goes red; invite stays Pending"
    alert_route: "CI test failure (pre-merge)"
  - mode: "redirectTo points at non-invite/cross-origin target"
    detection: "validator rejects + warnSilentFallback op=redirect_target_rejected"
    alert_route: "Sentry auth-feature alert"
  - mode: "accept RPC fails after redirect lands (expired/already-member)"
    detection: "accept-invite route returns 404/409; reason mapped; client shows humanized copy"
    alert_route: "Sentry (RPC error) + UI error box"
logs:
  where: "pino child logger 'workspace-invitations' + auth callback structured logs"
  retention: "per existing Better Stack / pino sink policy (unchanged)"
discoverability_test:
  command: "grep -rln redirectTo apps/web-platform/app/api/accept-terms"
  expected_output: "route.ts"
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed (plan-author assessment; spawn leader at deepen-plan if depth warranted)
**Assessment:** Fix is a wiring gap, not an architectural change. Risk concentrated in the
redirect-target validator (open-redirect class). The validator already exists
(`lib/safe-return-to.ts`) but its allowlist is `/dashboard`-only and silently rejects
`/invite/<token>` — widening it (preserving all reject vectors) is the security-critical edit.
Three drop points (signup-verify, login-verify, callback) all hardcode their destination;
plus the OAuth callback-URL append and the login no-account bounce. Carry-forward through the
onboarding funnel is the common case for a new invitee (no T&C/key/repo yet), not an edge case.
Prefer Option A (smaller surface, reuses accept path, preserves explicit consent click for the
WORM attestation).

### Product (CPO)

**Status:** requires sign-off (threshold = single-user incident; `requires_cpo_signoff: true`)
**Assessment:** This is the flagship multi-user onboarding moment failing on first use.
Option A (land-on-page, explicit Accept) vs Option B (zero-click auto-accept) is a product
call — Option A keeps an explicit consent act (better for attestation + clarity) at the cost
of one click. CPO must sign off on the chosen option before `/work`.

### Legal (CLO)

**Status:** reviewed
**Assessment:** No new data surface. The acceptance attestation (WORM
`workspace_member_attestations`) already captures consent at accept time. If Option B
(auto-accept) is chosen, confirm the attestation still records an affirmative acceptance act
(brainstorm Open Question #2). GDPR gate (Phase 2.7) applies because the flow touches auth +
membership; no new processing activity beyond what #4519 already registered. Run
`/soleur:gdpr-gate` against the diff at work Phase 2 exit.

## Test Scenarios

1. New invitee, email-OTP: invite → signup → OTP verify → returns to `/invite/[token]`
   authenticated + matched → Accept → member of inviter's workspace; invite no longer Pending.
2. New invitee, OAuth provider: same end state via the callback path.
3. Existing-user invitee using **Sign in** link: returns to invite page + accepts.
4. Genuine new signup, no invite: onboarding funnel unchanged, own workspace.
5. Hostile `redirectTo`: `https://evil.example`, `//evil.example`, `/\evil.example`,
   `\\evil.example` → all rejected → safe default; `warnSilentFallback` emitted.
6. Email mismatch: signed-in account ≠ invited email → invitee-identity gate blocks accept
   (existing 403 path), neutral mismatch copy shown.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **The existing `safeReturnTo()` validator silently rejects `/invite/<token>`** (allowlist is
  `/dashboard`-only). The single most likely fix-mistake is "reuse the existing validator" →
  every invite redirect falls back to `/dashboard` and the bug persists in a new disguise.
  Widening the allowlist (AC3) is mandatory and is the security-critical edit — the widened
  pattern must still reject `/invite/../dashboard` and any non-`/invite` / non-`/dashboard`
  path.
- **Param-name drift:** invite links use `redirectTo`; the validator + every other consumer
  use `return_to`. Pick `return_to` (the convention) and rename the 3 invite links — do not
  teach consumers a second param name.
- Carry-forward is the easy-to-miss half: fixing only the final callback redirect but not the
  intermediate funnel hops (`/accept-terms`/`/setup-key`/`/connect-repo`) leaves the target
  dropped for any invitee who hasn't yet accepted T&C or set a key. Trace the full funnel
  before claiming the fix complete. The new-user invitee ALWAYS hits the funnel (no T&C, no
  key, no repo) — so the carry-forward path is the common case, not the edge case.
- The OAuth path's `redirectTo` (`oauth-buttons.tsx:75`) is the *Supabase callback URL*, not
  the app's return target — do not conflate them. The return target rides as a query param on
  that callback URL.
- AC4 must run against **dev**, never prod (`hr-dev-prd-distinct-supabase-projects`) — creating
  synthetic invitee/`workspace_members` rows in prod leaves DSAR/billing residue.
- Test runner: the package uses **vitest** (per the `bunfig.toml` `pathIgnorePatterns` note in
  AGENTS.md Sharp Edges) — confirm via `package.json scripts.test` at work time; do not assume
  `bun test`.
