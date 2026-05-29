---
title: "fix: Invited user trips OTP email rate limit on first sign-in"
date: 2026-05-29
type: fix
status: deepened
branch: feat-one-shot-fix-invited-user-signin-rate-limit
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related:
  - knowledge-base/project/brainstorms/2026-05-27-workspace-invite-acceptance-brainstorm.md
  - knowledge-base/project/learnings/2026-03-20-supabase-signinwithotp-creates-users.md
  - knowledge-base/project/learnings/2026-04-11-map-supabase-errors-to-friendly-messages.md
  - knowledge-base/project/learnings/2026-04-02-supabase-otp-length-ui-config-mismatch.md
---

# 🐛 fix: Invited user trips OTP email rate limit on first sign-in

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Reconciliation, ACs, Implementation Phases, Risks (precedent-diff), Test Strategy.

### Key Improvements (deepen-plan, all live-verified)
1. **Precedent found — reuse, do not invent.** `apps/web-platform/lib/safe-return-to.ts` already exists (`safeReturnTo(param)`), with tests at `test/safe-return-to.test.ts`. It rejects open-redirect via `startsWith("/dashboard")` + `includes("//")`/`includes("\\")`/`includes("..")`. **BUT it only accepts `/dashboard*` paths — it would REJECT `/invite/<token>`.** Plan changed: generalize `safeReturnTo` to accept an allowlist of permitted path prefixes (`/dashboard`, `/invite/`) rather than create a parallel `lib/auth/redirect.ts`. This is a cross-consumer edit (existing consumer: `app/(auth)/connect-repo/page.tsx`) — sweep + update its test.
2. **Test runner verified: `vitest`** (`package.json` `"test": "vitest"`), and `bunfig.toml` has `pathIgnorePatterns = ["**"]` → `bun test` reports "filter did not match" (PR #4173 class). AC9 command MUST be `./node_modules/.bin/vitest run <paths>` (or `npx vitest run`), NOT `bun test`.
3. **Middleware T&C enforcement confirmed** (`middleware.ts:325-326`): an unaccepted-T&C user is redirected to `/accept-terms` from ANY route. Resolves brainstorm OQ#4 and the Phase 2 open question — routing the invited user to `/invite/<token>` is safe; middleware interposes `/accept-terms`.
4. **Residual gap surfaced (accept-terms loses return_to):** `app/api/accept-terms/route.ts` `getRedirectDestination` returns only `/setup-key` or `/dashboard` (lines 22, 67-68) — it does NOT honor any return_to. So an unaccepted-T&C invited user routed to `/invite` → bounced to `/accept-terms` → after accept, sent to `/setup-key|/dashboard`, **invite link lost from the redirect chain.** See "New Considerations" below for why this is acceptable (no rate-limit recurrence) plus the optional fold-in.

### New Considerations Discovered
- **Once authenticated, re-opening `/invite/<token>` requires NO OTP.** The invite page (`app/(public)/invite/[token]/page.tsx`) is server-rendered; for an authenticated, email-matched invitee it shows the "Accept invitation" button directly (`invite-actions.tsx:160`) with no `signInWithOtp` call. Therefore **the rate-limit symptom cannot recur for an authenticated user** — the only OTP sends are on `/login` and `/signup`. The cause-fix's job is narrowly: get the invited user *authenticated with exactly one OTP send*, then either land them on the invite or let them re-open the link (no OTP). The resend cooldown (Phase 3) is what guarantees the "exactly one send in the 60s window" invariant.
- **Therefore the accept-terms return_to gap (point 4) is NOT a rate-limit regression** — worst case the user finishes onboarding and re-clicks the invite link (authenticated, no OTP, one click to accept). Folding return_to through accept-terms is a UX polish, scoped as optional Phase 4b, not a blocker.

## Overview

A freshly invited+created user, immediately after creating an account through the invite flow, hits **"Too many sign-in attempts. Please wait a few minutes and try again."** on the regular "Sign in to Soleur" screen (email pre-filled). This is the friendly-mapped form of Supabase GoTrue's **`email rate limit exceeded`** error (`apps/web-platform/lib/auth/error-messages.ts:25-27`), NOT the in-app per-user rate limiter (`server/with-user-rate-limit.ts`, which returns `"Too many requests"`).

**Verified root cause (context7 Supabase Auth Rate Limits, retrieved 2026-05-29):** The `/auth/v1/otp` endpoint is rate-limited **"by last request — defaults to a 60-second window before a new request is allowed to the same user."** A second `signInWithOtp` for the same email within 60s returns HTTP 429 `email rate limit exceeded`. The invite flow forces exactly this double-send because the post-signup redirect path is broken:

1. `/invite/[token]` (unauthenticated) renders "Create an account to join" → `/signup?redirectTo=/invite/${token}` (`app/(public)/invite/[token]/invite-actions.tsx:57-59`).
2. Signup sends OTP #1 for the invitee's email at `t=0` (`app/(auth)/signup/page.tsx:47`), then on `verifyOtp` success **hardcodes `router.push("/accept-terms")`** (`signup/page.tsx:94`) — **the `redirectTo` query param is read nowhere in the signup flow.** The invite token is dropped on the floor.
3. The user lands in the post-signup funnel (accept-terms → setup-key → connect-repo → dashboard) and never reaches `/invite/[token]`. To accept the invite they re-open the invite link → "Sign in" → `/login?redirectTo=/invite/${token}`, with email pre-filled, and request a fresh code.
4. That second `signInWithOtp` for the same email lands inside GoTrue's 60s per-user OTP window → **429 `email rate limit exceeded`** → mapped to "Too many sign-in attempts."

Neither auth form has a client-side resend cooldown (`grep` confirms no `cooldown`/timer in `login-form.tsx` or `signup/page.tsx`), so the UI cannot prevent a same-email re-send inside the 60s window, and the message conflates a transient 60s cooldown with a genuine abuse rate limit.

**Fix has two load-bearing halves:**

- **(A) Stop the forced double-send.** Honor `redirectTo` end-to-end through the invite→signup→verify path so a successfully-created invited user is taken straight to `/invite/[token]` (or auto-accept) and never needs to request a second OTP. This eliminates the *cause*.
- **(B) Make the UI resilient to the 60s window.** Add a client-side resend cooldown (≥ 60s, matching GoTrue's `auth.rate_limits.otp.period`) on both `login-form.tsx` and `signup/page.tsx`, and give the 60s-cooldown case distinct, accurate copy ("You can request a new code in Ns") separate from the genuine project-wide email-rate-limit message. This makes the *symptom* non-reproducible even on legitimate re-sends.

This is a behavioral fix against already-provisioned surfaces (Next.js client components + a shared error-map module). No new infrastructure. The Supabase auth config (`supabase/scripts/configure-auth.sh`) is read-only context here — we are NOT widening any server-side rate limit (that would be a defense-relaxation; see Risks).

## Research Reconciliation — Spec vs. Codebase

| Claim (bug report / brainstorm) | Codebase reality (verified) | Plan response |
|---|---|---|
| "Too many sign-in attempts" = in-app rate limiter | That string lives ONLY in `error-messages.ts:26-27` as the map for GoTrue `email rate limit exceeded`. The in-app limiter (`with-user-rate-limit.ts:87`) returns `"Too many requests"` and gates authenticated GETs, never the unauthenticated OTP send. | Fix targets the GoTrue OTP path + UI, not `with-user-rate-limit.ts`. |
| Brainstorm decision #5: "signup + auto-join: `/invite/[token]` → signup flow with token preserved → post-signup callback auto-accepts" | `invite-actions.tsx:57-59` links to `/signup?redirectTo=/invite/${token}`, but `signup/page.tsx` never reads `redirectTo` and hardcodes `router.push("/accept-terms")` (line 94). The "post-signup callback auto-accepts" mechanism described in the brainstorm's Open Question #1 was **never implemented**. | The redirect-preservation is a *build*, not a *patch*: thread `redirectTo` through signup verify and (for OAuth) the `/callback` route. |
| Brainstorm Open Question #1: "How should the token be preserved through the OAuth/OTP flow? Likely `redirectTo` query param." | OTP path: `redirectTo` dropped. OAuth path: `oauth-buttons.tsx:75` hardcodes `redirectTo: \`${window.location.origin}/callback\`` and `/callback/route.ts:229-259` computes its own next-hop ignoring any invite. | Plan resolves OQ#1: preserve `redirectTo` as a validated relative path through both flows. |
| `mailer_otp_exp: 600`, `mailer_otp_length: 6` configured | Confirmed in `configure-auth.sh:43-44`. The script does NOT set any `rate_limit_*` field → GoTrue defaults apply (60s per-user OTP window). | Cooldown set to ≥ 60s to match the GoTrue default; documented as the binding constraint. |

## User-Brand Impact

**If this lands broken, the user experiences:** an invited teammate who cannot complete sign-in on their first attempt — they are bounced to a "Too many sign-in attempts" wall on the regular sign-in screen and abandon onboarding. The invite the operator sent appears broken; the new user's first impression of Soleur is a dead end.

**If this leaks, the user's data / workflow is exposed via:** the `redirectTo` parameter is an open-redirect / token-smuggling vector if not strictly validated. An attacker-supplied `redirectTo=https://evil.example` (or `//evil`, `/\evil`, a path with embedded credentials) appended to a `/signup` or `/login` link could bounce an authenticated session to an external page or leak the freshly-minted session via referer. The fix MUST allow only same-origin relative paths matching a strict allowlist shape.

**Brand-survival threshold:** `single-user incident` — carried forward from the parent brainstorm (`USER_BRAND_CRITICAL=true`). One invited user blocked at the door is a brand-survival event for a feature whose entire purpose is multi-user onboarding; and one open-redirect on the auth path is a credential-exposure event. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — redirectTo honored (OTP).** After `verifyOtp` success on `/signup?redirectTo=/invite/<token>`, the user is routed to the validated `redirectTo` target (`/invite/<token>`), NOT unconditionally to `/accept-terms`. Verify via the new RTL test asserting `router.push`/`router.replace` is called with the sanitized `redirectTo` when present and `/accept-terms` (existing behavior) when absent. (`signup/page.tsx`)
- [x] **AC2 — redirectTo honored (login).** `login-form.tsx` `handleVerifyOtp` routes to a validated `redirectTo` when present (currently hardcodes `/dashboard`, line 119), else `/dashboard`. RTL test covers both branches. (`login-form.tsx`)
- [x] **AC3 — redirectTo sanitization (REUSE existing `safeReturnTo`).** Generalize the existing `apps/web-platform/lib/safe-return-to.ts` `safeReturnTo(param)` to accept an allowlist of permitted path prefixes (currently hardcoded `/dashboard`-only at line 9). New signature accepts `/dashboard` AND `/invite/` paths. Keep its existing reject guards verbatim (`includes("//")`, `includes("\\")`, `includes("..")`). Extend `test/safe-return-to.test.ts` to assert: rejects `https://evil`, `//evil`, `/\evil`, `/dashboard/../x`, `/evil` (non-allowlisted prefix); accepts `/invite/<token>`, `/dashboard`, `/dashboard/settings/team`. Falls back to a per-caller default (login → `/dashboard`, signup → `/accept-terms`) when the param is rejected. Do NOT create a parallel `lib/auth/redirect.ts`.
- [x] **AC4 — resend cooldown (login).** After a successful OTP send, the "Send sign-in code" / resend control is disabled for `OTP_RESEND_COOLDOWN_MS` (≥ 60_000) with a visible countdown; a second send to the same email cannot fire inside the window. RTL test uses fake timers to assert the button is disabled at t=1s and re-enabled at t=cooldown. (`login-form.tsx`)
- [x] **AC5 — resend cooldown (signup).** Same as AC4 for `signup/page.tsx`.
- [x] **AC6 — cooldown message distinct from rate-limit message.** When the cooldown is active the UI shows "You can request a new code in Ns" (or equivalent), NOT "Too many sign-in attempts." The genuine GoTrue `email rate limit exceeded` mapping in `error-messages.ts` is unchanged. (assert both strings present in the respective render paths)
- [x] **AC7 — no server rate-limit relaxation.** `git diff` shows ZERO change to any `rate_limit_*` field in `configure-auth.sh` and ZERO change to `with-user-rate-limit.ts` / `rate-limiter.ts`. (grep gate in PR body)
- [x] **AC8 — error-messages map regex unchanged for the genuine case.** `error-messages.test.ts` still maps `"email rate limit exceeded"` → "Too many sign-in attempts…" (regression guard).
- [x] **AC9 — full suite green (vitest, verified 2026-05-29).** `cd apps/web-platform && ./node_modules/.bin/vitest run test/safe-return-to.test.ts <new login/signup test paths>` passes. Runner is `vitest` (`package.json` `"test": "vitest"`); `bunfig.toml` has `pathIgnorePatterns = ["**"]` so `bun test` reports "filter did not match" — MUST use vitest, not bun. (PR #4173 Sharp Edge.)
- [x] **AC10 — CSRF/origin unchanged on accept-invite.** The accept-invite POST route's `validateOrigin()`/`rejectCsrf()` gate is untouched (this fix does not alter the accept path, only how the user arrives at it). Confirm via no-diff on `app/api/workspace/accept-invite/route.ts`.

### Post-merge (operator)

- [x] **AC11 — none.** No operator action; this is a pure client+lib code change deployed by the standard `web-platform-release.yml` pipeline on merge to main. (Automation: PR merge IS the remediation per the path-filtered `on.push` container restart.)

## Implementation Phases

> **Phase order is load-bearing:** Phase 1 (shared sanitizer) ships the contract BEFORE Phase 2/3 consume it. Per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

### Phase 0 — Preconditions (verify, do not assume)

- [x] Confirm test runner: read `apps/web-platform/package.json` `scripts.test` and check `apps/web-platform/bunfig.toml` for `[test] pathIgnorePatterns`. Record the exact command in the spec. (Per Sharp Edge: PR #4173 hardcoded `bun test` against a vitest package.)
- [x] Confirm `router` import shape in `signup/page.tsx` and `login-form.tsx` (`useRouter` from `next/navigation`, already present).
- [x] `grep -n "redirectTo" app/(auth)/signup/page.tsx app/(auth)/callback/route.ts` → confirm zero current reads (proves the gap; baseline for the build).
- [x] Read the 2-3 most recent RTL tests under `apps/web-platform/test/` (or co-located) to match the existing mocking convention for `useRouter`/`createClient` before writing new tests.

### Phase 1 — Generalize existing `safeReturnTo` (RED→GREEN)

> **Reuse, don't invent.** `lib/safe-return-to.ts` is the established precedent (consumer: `connect-repo/page.tsx`; test: `test/safe-return-to.test.ts`). Extend it; do not add a parallel helper. Per AGENTS.md `hr-type-widening-cross-consumer-grep`, sweep all consumers when widening the signature.

- [x] Extend `test/safe-return-to.test.ts` (RED) with the AC3 vectors against the new allowlist signature, preserving all existing `/dashboard` assertions.
- [x] Generalize `lib/safe-return-to.ts` to accept an allowlist and return `null` on reject so each caller supplies its own fallback (login → `/dashboard`, signup → `/accept-terms`). Current consumer `connect-repo/page.tsx` calls `safeReturnTo(param)` expecting a non-null `/dashboard` fallback — preserve a back-compat default OR update that one call site (verified: only one external consumer). Proposed shape:
  ```ts
  const ALLOWED_PREFIXES = ["/dashboard", "/invite/"] as const;

  /** Returns the param iff it is a same-origin relative path under an allowed
   *  prefix; else null. Caller picks its fallback. Guards mirror the original
   *  (//, \\, .. rejection) so the open-redirect surface is unchanged. */
  export function safeReturnTo(param: string | null): string | null {
    if (!param) return null;
    if (!param.startsWith("/") || param.includes("//") || param.includes("\\") || param.includes("..")) return null;
    if (!ALLOWED_PREFIXES.some((p) => param.startsWith(p))) return null;
    return param;
  }
  ```
  (`startsWith("/")` + the explicit `//` reject already excludes protocol-relative and absolute URLs — an absolute `https://` does not start with `/`; `//evil` is rejected by `includes("//")`. The original's substring `includes` guards are deliberately retained — they are the verified precedent shape, simpler and proven by the existing test.)
- [x] `connect-repo/page.tsx`: if the back-compat default is dropped, replace `safeReturnTo(p)` with `safeReturnTo(p) ?? "/dashboard"`. Re-run its render path test.

### Phase 2 — Honor redirectTo in OTP verify (signup + login)

- [ ] `signup/page.tsx`: read `const redirectTo = safeReturnTo(searchParams.get("redirectTo"))`; in `handleVerifyOtp` success, `router.push(redirectTo ?? "/accept-terms")`. **T&C safety (VERIFIED):** middleware (`middleware.ts:325-326`) redirects any unaccepted-T&C user to `/accept-terms` from ANY route, so pushing a freshly-created (T&C-unaccepted) user to `/invite/<token>` is safe — middleware interposes `/accept-terms`. No `redirectTo` is threaded through accept-terms in this phase (see Phase 4b for the optional polish).
- [x] `login-form.tsx`: read `const redirectTo = safeReturnTo(searchParams.get("redirectTo"))`; in `handleVerifyOtp` success, `router.push(redirectTo ?? "/dashboard")` (currently hardcodes `/dashboard` at line 119).
- [x] RTL tests for AC1/AC2 (present + absent branches).

### Phase 3 — Resend cooldown + distinct cooldown copy

- [x] Add `OTP_RESEND_COOLDOWN_MS = 60_000` to `lib/auth/constants.ts` (co-located with `EMAIL_OTP_LENGTH`).
- [x] In both forms: on successful send, start a countdown; disable the send/resend control and the "Send" button until it elapses; render "You can request a new code in {n}s" while active. Clear timer on unmount.
- [x] Distinct cooldown copy is local UI state — does NOT touch `mapSupabaseError`. The genuine 429 path (if a user somehow still hits it) keeps the existing "Too many sign-in attempts" mapping.
- [x] RTL tests for AC4/AC5/AC6 using fake timers.

### Phase 4 — OAuth redirectTo continuity (FOLD IN)

> **Resolved in deepen-plan:** `OAuthButtons` IS rendered on `/signup` (`signup/page.tsx:246`), so an invited user CAN choose "Continue with Google" instead of email OTP. Today `oauth-buttons.tsx:75` hardcodes `redirectTo: \`${window.location.origin}/callback\`` and `/callback/route.ts:229-259` computes its own next-hop (accept-terms/setup-key/connect-repo/dashboard) ignoring any invite. At `single-user incident` threshold the "OAuth is the second-most-likely entry, scope it out" framing is an anti-pattern (Sharp Edge) — **fold in.**

- [x] `oauth-buttons.tsx`: accept an optional `returnTo` prop (or read `redirectTo` from `useSearchParams`); pass it as `redirectTo: \`${window.location.origin}/callback?next=${encodeURIComponent(safeNext)}\`` where `safeNext` is `safeReturnTo(raw)`. Supabase preserves the `redirectTo` query string through the OAuth round-trip.
- [x] `/callback/route.ts`: after a successful `exchangeCodeForSession` + the existing T&C/key/repo routing, if `searchParams.get("next")` passes `safeReturnTo`, prefer it as the final hop (still subject to the T&C/setup gates — only override the terminal `/dashboard` hop, never skip `/accept-terms` or `/setup-key`). Add the `next` param to the keys-only Sentry allowlist already present (`SEARCH_PARAM_KEY_RE`, line 28).
- [x] RTL/route test: `/callback?next=/invite/<token>` with a T&C-accepted, keyed, repo-connected user lands on `/invite/<token>`; an unaccepted-T&C user still lands on `/accept-terms`.

### Phase 4b — (Optional polish) Thread return_to through accept-terms

- [x] **IMPLEMENTED at review time (promoted from deferral; #4643 closed).** Multi-agent review (security-sentinel + user-impact-reviewer) found that routing signup straight to `/invite/<token>` bypasses server-recorded T&C — `/invite` is a `PUBLIC_PATH` so middleware does NOT interpose `/accept-terms` (the plan's "middleware enforces from any route" claim was wrong). Fix: signup verify routes through `/accept-terms?redirectTo=<validated>`; accept-terms records T&C then honors the validated redirectTo as the terminal hop (after `/setup-key` if no key). This makes AC1 land via `/accept-terms` rather than directly, preserving the invite WITHOUT a T&C bypass. Not a rate-limit fix; UX/Legal correctness. `getRedirectDestination` in `app/api/accept-terms/route.ts:22` returns only `/setup-key`/`/dashboard`. An invited user who hits `/accept-terms` mid-flow loses the invite link from the redirect chain. Worst case is benign: they finish onboarding, re-open the invite link (authenticated → NO OTP → one click to accept). Threading `return_to` through accept-terms expands scope into a separate route + persistence + tests, so it is filed as a follow-up rather than folded in.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Security (via Product/UX gate + GDPR gate)

### Engineering (CTO)
**Status:** carried-forward from parent brainstorm `2026-05-27-workspace-invite-acceptance` Domain Assessments.
**Assessment:** The invite acceptance flow's redirect continuity is the product-critical surface (brainstorm CTO). The fix stays entirely in client components + the existing pure `lib/safe-return-to.ts` helper (generalized, not replaced); zero RLS/schema/RPC surface, zero regression risk to the 66 `workspace_members` consumers.

### Legal (CLO)
**Status:** carried-forward.
**Assessment:** No new processing activity. The redirectTo fix changes navigation only. The T&C acceptance gate (accept-terms) must remain enforced on the invited user before they can act in a workspace — Phase 2 must not let `redirectTo` bypass `/accept-terms` for a user who hasn't accepted current T&C. GDPR gate (Phase 2.7) covers the auth-flow surface.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings
This modifies existing auth screens (no new page/component file — escalation scan: no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` created; the cooldown is added to existing forms). Tier is ADVISORY. The visual change is a disabled button + countdown text using existing tokens. Wireframes from the parent brainstorm (`workspace-invite-acceptance.pen` screenshots 16/17) cover the invite-landing states; no new design needed.

## Infrastructure (IaC)

No new infrastructure. `configure-auth.sh` is read-only context. Skip — pure code change against an already-provisioned surface.

## Observability

```yaml
liveness_signal:
  what: existing reportSilentFallback("auth","signInWithOtp"/"verifyOtp") breadcrumbs already fire on every OTP error
  cadence: per failed auth attempt
  alert_target: Sentry auth feature dashboard (existing)
  configured_in: login-form.tsx + signup/page.tsx (unchanged emit sites)
error_reporting:
  destination: Sentry via reportSilentFallback (typed enum fields only — no email PII, per existing comment login-form.tsx:68-69)
  fail_loud: yes (errorCode + errorName forwarded)
failure_modes:
  - mode: redirectTo sanitizer rejects a legitimate path (over-strict regex)
    detection: user lands on default (/accept-terms or /dashboard) instead of /invite — degrades to current broken behavior, NOT a crash
    alert_route: unit-test coverage (AC3) is the primary guard; add a dev-only console.warn on reject for local debugging
  - mode: cooldown timer leaks across unmount
    detection: RTL test asserts clearInterval on unmount
    alert_route: test-time only
  - mode: genuine GoTrue 429 still reached (project-wide email cap, not per-user 60s)
    detection: existing Sentry breadcrumb errorCode=over_email_send_rate_limit
    alert_route: existing auth dashboard
logs:
  where: Sentry breadcrumbs (client) — no server log change
  retention: existing Sentry retention
discoverability_test:
  command: "cd apps/web-platform && <test-runner> test/<redirect + login-form + signup tests> (NO ssh)"
  expected_output: all green; sanitizer rejects open-redirect vectors; verify routes to redirectTo
```

## Test Scenarios

1. **Happy path (cause fixed):** invite (unauth) → signup with `redirectTo=/invite/<token>` → one OTP send → verify → lands on `/invite/<token>` → accept. Exactly ONE `signInWithOtp` for the email. (RTL: assert single send + final route.)
2. **Symptom resilience:** user requests a code, then tries to resend within 60s → button disabled, countdown shown, NO second `signInWithOtp` fired, NO "Too many sign-in attempts" text.
3. **Open-redirect rejection:** `redirectTo=https://evil`, `//evil`, `/\evil`, `/%2Fevil` → sanitizer returns null → safe default route. (unit)
4. **T&C still enforced:** invited user who hasn't accepted current T&C is still routed through `/accept-terms` before reaching the workspace (deepen-plan to confirm middleware vs explicit route).
5. **Genuine rate-limit unchanged:** mock GoTrue `email rate limit exceeded` → still maps to "Too many sign-in attempts" (regression).

## Open Code-Review Overlap

Two open scope-outs touch files in this plan's `## Files to Edit` (scanned 2026-05-29 against 74 open `code-review` issues):

- **#3184** — `review: extract useOtpFlow hook + OtpCodeStep component (login/signup duplication)` — touches `app/(auth)/signup/page.tsx` (and login-form by topic). **Disposition: Acknowledge.** This plan adds the SAME logic (redirectTo read, resend cooldown) to BOTH `signup/page.tsx` and `login-form.tsx`, which deepens the very duplication #3184 wants to extract. Folding in the hook extraction would balloon the PR scope and entangle a security/onboarding fix with a refactor. Rationale: ship the behavioral fix duplicated across both forms (as today's code already is), and let #3184 extract the shared `useOtpFlow` hook afterward — the cooldown + redirectTo logic will be cleaner to hoist once it's proven correct in both. Leave #3184 open; add a note to it that the OTP flow now also carries cooldown + redirectTo state to lift.
- **#3739** — `review: extract reportSilentFallbackWithUser helper (collapse 11-site withIsolationScope+setUser duplication)` — touches `app/(auth)/callback/route.ts` and `app/api/accept-terms/route.ts`. **Disposition: Acknowledge.** This plan only adds a `next`-param terminal-hop branch to `callback/route.ts` (Phase 4) and optionally a `return_to` honor to `accept-terms/route.ts` (Phase 4b); it does not touch the `withIsolationScope`+`setUser` emit sites #3739 targets. Different concern. Leave #3739 open.

## Files to Edit

- `apps/web-platform/lib/safe-return-to.ts` — generalize `safeReturnTo` to an allowlist (`/dashboard`, `/invite/`), return `null` on reject.
- `apps/web-platform/test/safe-return-to.test.ts` — extend with AC3 vectors (preserve existing `/dashboard` assertions).
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` — only consumer of `safeReturnTo`; update to `safeReturnTo(p) ?? "/dashboard"` if back-compat default is dropped.
- `apps/web-platform/app/(auth)/signup/page.tsx` — read `redirectTo` via `safeReturnTo`; route on verify; resend cooldown.
- `apps/web-platform/components/auth/login-form.tsx` — read `redirectTo` via `safeReturnTo`; route on verify; resend cooldown.
- `apps/web-platform/lib/auth/constants.ts` — add `OTP_RESEND_COOLDOWN_MS = 60_000`.
- `apps/web-platform/components/auth/oauth-buttons.tsx` — (Phase 4) thread `redirectTo` → `/callback?next=`.
- `apps/web-platform/app/(auth)/callback/route.ts` — (Phase 4) honor validated `next` terminal hop; add `next` to Sentry keys allowlist.
- `apps/web-platform/app/api/accept-terms/route.ts` — (Phase 4b, optional) honor `return_to`.

## Files to Create

- RTL test additions for signup + login. **Verify location/convention in Phase 0** — extend existing co-located/`test/` files matching the `useRouter`+`createClient` mock convention rather than creating new ones. No new `lib/auth/redirect.ts` (reusing `safe-return-to.ts`).

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Raise the GoTrue per-user OTP window / project email rate limit in `configure-auth.sh` | Defense relaxation on an auth abuse control (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`). It treats the symptom, not the forced double-send, and weakens brute-force/email-bomb protection. Rejected. |
| Only add the cooldown (symptom), skip redirectTo (cause) | Leaves the broken onboarding loop: user still gets bounced away from the invite and must re-request. Cooldown alone makes the wall friendlier but the invite still fails to complete. Both halves required. |
| Auto-accept the invite server-side in `/callback` for OTP signups | Larger blast radius (changes accept semantics, attestation timing — brainstorm OQ#2). Out of scope; `redirectTo` to the existing `/invite/[token]` accept UI is the minimal correct fix. |

## Risks & Mitigations

### Precedent-diff (Phase 4.4) — redirect sanitizer

`git grep` found exactly one existing redirect-sanitizer: `lib/safe-return-to.ts` (consumer `connect-repo/page.tsx`, test `test/safe-return-to.test.ts`). No parallel implementation in `/callback/route.ts` (its `uri_allow_list` is a Supabase *server-config* concept, not a client path validator). **Decision: generalize the existing helper, do not invent a new one.** Side-by-side:

| | Current `safeReturnTo` | Generalized (this plan) |
|---|---|---|
| Accept | `startsWith("/dashboard")` only | `startsWith` any of `["/dashboard","/invite/"]` |
| Reject guards | `//`, `\\`, `..` (substring) + non-`/dashboard` | identical `//`, `\\`, `..` guards + non-allowlisted prefix |
| Return on reject | `"/dashboard"` (fallback baked in) | `null` (caller picks fallback) |

The guard shape (`includes("//")` / `includes("\\")` / `includes("..")`) is the proven precedent — retained verbatim. An absolute URL (`https://evil`) fails `startsWith("/")`; protocol-relative (`//evil`) fails `includes("//")`.

### Other risks

- **Open redirect via `redirectTo`** — primary security risk. Mitigated by the generalized `safeReturnTo` (same-origin relative, allowlisted prefix) + unit tests for every vector (AC3). Encoded-slash (`/%2Fevil`) does not contain a literal `//`/`\\`/`..` — confirm the allowlisted-prefix check (`/invite/` requires a literal `/invite/` prefix) plus the leading-`/` check is sufficient; add an explicit `/%2F` reject test and, if it slips, a `decodeURIComponent`-then-recheck guard.
- **T&C bypass** — RESOLVED (verified): middleware (`middleware.ts:325-326`) redirects unaccepted-T&C users to `/accept-terms` from any route, so `redirectTo=/invite/<token>` cannot skip T&C. No additional mitigation needed.
- **Cooldown UX on "wrong email" correction** — a user who mistypes then corrects their email should send to the *new* email immediately. Mitigation: reset the cooldown timer when the email input value changes, AND the existing "Try a different email" button (`login-form.tsx:160`) already resets form state — extend it to clear the cooldown. Specify in Phase 3.
- **`safeReturnTo` signature change breaks `connect-repo`** — the one existing consumer expects a non-null `/dashboard` fallback. Mitigation: update that call site to `?? "/dashboard"` in the same PR (Phase 1) and keep its render test green. Per `hr-type-widening-cross-consumer-grep`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)
- The error string "Too many sign-in attempts" is GoTrue email-rate-limit copy, NOT the in-app limiter — do not "fix" `with-user-rate-limit.ts`; it is unrelated (returns "Too many requests").
- Do not assume the test runner. Verify `package.json scripts.test` + `bunfig.toml pathIgnorePatterns` in Phase 0 before writing AC9's command (PR #4173 class).
- `redirectTo` sanitizer regex with Unicode/encoded-slash vectors: test `/%2F`, `/\`, `//`, and decode-once bypasses; do not ship a regex that passes `tsc` but leaks an absolute URL.
