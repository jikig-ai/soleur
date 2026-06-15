---
title: "fix: Unexpected session disconnect + over-aggressive login-attempt blocking"
type: fix
date: 2026-06-15
status: planned
branch: feat-one-shot-session-disconnect-login-blocking
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
semver: patch
related:
  - knowledge-base/project/plans/2026-05-22-feat-workspace-member-session-invalidation-plan.md
  - knowledge-base/project/plans/2026-05-29-fix-invited-user-signin-otp-rate-limit-plan.md
  - knowledge-base/project/learnings/2026-03-20-middleware-error-handling-fail-open-vs-closed.md
  - knowledge-base/project/learnings/2026-05-23-service-role-revoke-strip-and-dual-shape-cookie-clear.md
  - knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md
  - knowledge-base/engineering/operations/runbooks/supabase-magiclink-rate-limit.md
---

# 🐛 fix: Unexpected session disconnect + over-aggressive login-attempt blocking

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Overview/root-cause, Research Reconciliation, Hypotheses, Implementation Phases, ACs, Risks (precedent-diff added), Sharp Edges.
**Research agents used:** learnings-researcher, git-history-analyzer, framework-docs-researcher (×2), Explore (verify-the-negative pass).

### Key Improvements (all live-verified this pass)
1. **Clock-skew hypothesis was BACKWARDS — corrected.** Migration 067's `check_my_revocation` predicate uses a strict `revoked_after > p_jwt_iat` that the migration comment (line 81-82) states **"absorbs ±1s clock skew on the safer (deny) side per AC6"** — the design *deliberately* prefers revoking on skew. A non-removed user has NO `workspace_member_removals` row, so cannot get a false-positive revocation. Phase 1 no longer "adds skew tolerance" (which would have re-opened the leak); the clock-skew hypothesis is downgraded — see corrected Hypotheses.
2. **Login already sets `shouldCreateUser: false`.** `login-form.tsx:60-61` calls `useOtpFlow({ shouldCreateUser: false })` — the signup-backdoor concern (learnings #2) is already handled; no fix needed there. Recorded so /work does not chase it.
3. **AC6 over-stated — the two rate-limit messages are ALREADY distinct.** `over_request_rate_limit` → `RATE_LIMIT_MESSAGE` ("wait a minute"); `email rate limit exceeded` → `EMAIL_SEND_RATE_LIMIT_MESSAGE` ("wait a few minutes"). Phase 2's copy work is tone-refinement (surface the recovery window), not "make them distinguishable." AC6 re-scoped to a regression guard.
4. **GoTrue Management-API field names confirmed** (`rate_limit_email_sent`, `rate_limit_verify`, `rate_limit_otp`, `rate_limit_token_refresh`): integer, per-HOUR; **email/OTP counts are project-wide**, verify/token-refresh per-IP; the PATCH is a true partial update. The per-user 60s OTP send window is a separate min-frequency knob, NOT one of these count fields — do not conflate.
5. **vitest `include:` globs corrected.** Actual: `["test/**/*.test.ts", "lib/**/*.test.ts"]` (node project) + `["test/**/*.test.tsx"]` (jsdom). A `useOtpFlow` test MAY be co-located under `lib/auth/*.test.ts` (the `lib/**` glob collects it); a `.test.tsx` component test must live under `test/`. Sharp Edge corrected.
6. **Cited PRs verified MERGED:** #4345 (revocation gate / #4307), #4638 (invited-user OTP fix), #4664 (skew test backdate).

### New Considerations Discovered
- The 503-for-all transient-RPC failure is the strongest single hypothesis for Symptom 1 and is independently fixable from the skew/decode concerns. Prioritize it.
- Because the strict-`>` skew handling is deny-favoring *by design*, the residual Symptom-1 surface is narrowed to: (a) transient RPC error → 503-for-all, (b) non-removal JWT-decode (`malformed`/`no_iat`) forcing logout, and (c) the redundant `getSession()` round trip. Item (a) is the priority.

## Overview

Two distinct production symptoms on the Soleur web platform (`apps/web-platform`,
Next.js 15 App Router + Supabase GoTrue auth, single Hetzner node):

1. **Session appears to drop / user is signed out unexpectedly.** Authenticated
   users are bounced to `/login` mid-session without taking any logout action.
2. **Login attempts get blocked easily / lockout.** A user requesting a sign-in
   code a second time (or after a failed attempt) hits *"Too many sign-in
   attempts"* / *"Too many attempts right now"* after only a few tries.

Both symptoms trace to specific, already-shipped surfaces — this is a behavioral
fix against provisioned code plus one externalized Supabase auth config change, not
a green-field build. The two symptoms are independent and are fixed in independent
phases.

### Root cause — Symptom 1 (session disconnect)

The **#4307 revocation gate** in `apps/web-platform/middleware.ts` (shipped in PR
#4345, commit `33293aae`, 2026-05-25) runs on **every authenticated request**:

- Calls `supabase.auth.getUser()` (line 190) **and then** `supabase.auth.getSession()`
  (line 206) — the redundant double round-trip the @supabase/ssr docs warn against
  (`getUser()` already refreshes; calling `getSession()` afterward is the
  recommended-against pattern per framework-docs research §2.4).
- Decodes the access-token JWT `iat` via the inline `decodeJwtPayloadEdgeSafe`.
  On **malformed JWT** or **missing `iat`** it does NOT treat the case as "not
  revoked" — it **clears all `sb-*` cookies and redirects to `/login?revoked=session-error`**
  (middleware.ts, `clearSessionAndRedirect`). A transient decode hiccup or an
  unusually-shaped-but-valid token forces a logout.
- Calls `check_my_revocation` RPC per-request with **NO cache** and **fail-CLOSED
  to HTTP 503** on any RPC error (`revokeError` branch). A transient Supabase
  connectivity blip, connection-pool exhaustion, or read-replica lag returns 503
  for *every* authenticated request until the DB recovers — and the user-visible
  effect is "the site stopped working / signed me out."
- The revocation predicate compares JWT `iat` against `revoked_after` with a strict
  inequality; **GoTrue↔Postgres clock skew** can produce a false-positive revocation
  (already a known edge — PR #4664 `7e2d792a` backdated test iat to absorb skew, but
  that hardened the *test*, not the runtime predicate).

Per framework-docs research §2.5, a per-request DB RPC in middleware that can 503 on
transient errors is a documented anti-pattern for session stability. The original
#4307 fail-closed posture was a *deliberate security decision* (a removed member's
stale JWT must not be trusted) — so the fix must preserve the security boundary while
removing the collateral self-inflicted logouts on transient/non-removal failures.

### Root cause — Symptom 2 (login blocking)

The login flow is **email OTP** (`signInWithOtp` + `verifyOtp`, `lib/auth/useOtpFlow.ts`)
plus GitHub/Google OAuth. `apps/web-platform/supabase/scripts/configure-auth.sh`
patches `site_url`, SMTP, `mailer_otp_length`, `mailer_otp_exp`, and OAuth providers
but **sets ZERO `rate_limit_*` fields** (`grep -c rate_limit` → 0, verified). GoTrue
therefore runs at its **aggressive defaults** (framework-docs research §1.1):

- `rate_limit_email_sent`: **30 / hour, project-wide** (email OTP sends).
- `rate_limit_verify`: **30 / hour** (token verifications — `over_request_rate_limit`).
- Per-user OTP send window: **60 s** between `signInWithOtp` to the same email →
  HTTP 429 `over_email_send_rate_limit` (`email rate limit exceeded`).

A prior narrow fix (PR #4638, 2026-05-29, `2026-05-29-fix-invited-user-signin-otp-rate-limit-plan.md`)
added a **client-side 60 s resend cooldown** (`OTP_RESEND_COOLDOWN_MS = 60_000`) and
fixed the invited-user forced-double-send. That addressed *one* trigger of the symptom
but left two gaps:

- **The project-wide `30/hour` email-send ceiling is never raised from default.**
  On a single shared egress IP / small user base, a handful of legitimate users (or one
  user across a few failed-then-retry cycles, password manager re-fills, multi-tab) can
  exhaust the project-wide bucket and lock everyone out. This is the over-aggressive
  blocking the report describes.
- **Copy still conflates a transient 60 s cooldown with a genuine abuse lockout.**
  `error-messages.ts` maps both `over_request_rate_limit` and `email rate limit exceeded`
  to "wait a few minutes" copy, which reads as a hard lockout rather than a short wait.

The fix raises the GoTrue ceilings to sane-for-a-small-SaaS values via
`configure-auth.sh` (a **defense relaxation** — must name the new ceiling per
`2026-05-05-defense-relaxation-must-name-new-ceiling.md`) and tightens the user-facing
copy. It does NOT touch the in-app `with-user-rate-limit.ts` limiter (authenticated GET
budget) nor the WS `rate-limiter.ts` — those are unrelated surfaces (see Research
Reconciliation).

## Research Reconciliation — Spec vs. Codebase

| Claim (bug report / inference) | Codebase reality (verified) | Plan response |
|---|---|---|
| "It disconnects the user / session drops" = a session-storage or cookie-expiry bug | The sign-outs are produced by the **#4307 revocation gate** in `middleware.ts`: fail-closed 503 on transient RPC error + cookie-clear-to-/login on malformed/no-`iat` JWT + clock-skew false-positive on the `revoked_after > iat` predicate. JWT lifetime is the GoTrue default 1h with refresh-token rotation; no evidence of a cookie-expiry defect. | Fix the revocation gate's transient-failure handling (grace, not 503-for-all; do not log out on non-removal JWT-decode failures); collapse the redundant `getUser()`+`getSession()`. Do NOT chase a cookie-expiry phantom. |
| "Login blocked easily" = the in-app rate limiter | "Too many requests" (in-app `with-user-rate-limit.ts:87`) gates **authenticated GET** routes only and is keyed on `user.id` — it cannot fire on the unauthenticated OTP-send path. The login-blocking copy ("Too many sign-in attempts" / "Too many attempts right now") lives in `error-messages.ts` and maps **GoTrue 429s**. | Fix targets GoTrue config (`configure-auth.sh`) + OTP copy, NOT `with-user-rate-limit.ts` and NOT WS `rate-limiter.ts`. |
| `configure-auth.sh` already tunes rate limits | `grep -c rate_limit configure-auth.sh` → **0**. GoTrue runs at defaults (30/hour email + verify, 60s per-user OTP). | Add `rate_limit_*` fields to the PATCH payload with named new ceilings + drift note. |
| The invited-user fix (#4638) already solved login blocking | #4638 added a client-side cooldown + fixed the invited double-send. It did **not** raise the project-wide `30/hour` send ceiling, which is the broader lockout cause for non-invited users. | This plan raises the server-side ceiling (the gap #4638 explicitly scoped out as "not widening any server-side rate limit"). |
| Middleware follows the recommended @supabase/ssr pattern | Middleware calls BOTH `getUser()` (L190) and `getSession()` (L206) per request. Framework-docs §2.4: `getSession()` after `getUser()` is redundant. | Derive the access token from the `getUser()`-refreshed session without a second `getSession()` round trip where feasible; verify cookie propagation on the redirect/clear paths. |

## User-Brand Impact

**If this lands broken, the user experiences:** Symptom 1 — the founder is in the
middle of a real chat/work session and the site bounces them to `/login` ("Your session
ended unexpectedly"), losing in-flight context; worst case a transient DB blip 503s the
entire app for every authenticated user at once. Symptom 2 — a paying user cannot get
back in: every sign-in code request returns "Too many sign-in attempts," with no clear
recovery window — a hard lockout from their own product. Either is demo-killing and
trust-destroying for a single user.

**If this leaks, the user's session/workflow is exposed via:** The opposite failure mode
is the real leak risk — if the revocation-gate fix is over-corrected into **fail-OPEN**,
a removed/role-changed workspace member's stale JWT (valid up to ~1h) is no longer bounced
by the middleware gate. The fix MUST preserve the fail-closed security boundary for genuine
revocations while only relaxing the response to *transient infrastructure* errors and
*non-removal* JWT-decode hiccups.

**Boundary clarification (review correction — security-sentinel + user-impact).** The
middleware revocation gate is **defense-in-depth + UX**, NOT the sole removal boundary. The
actual data-plane boundary for a *removed* member is RLS: `remove_workspace_member` DELETEs
the `workspace_members` row, and every `conversations`/`messages`/`attachments`/BYOK read or
write is gated by `is_workspace_member(...)` against the **live** table. So even during a
grace window (transient revocation-RPC error → fall-through) a fully-removed member is
RLS-denied at the data layer — grace does NOT re-open the removal leak. The one **bounded,
accepted residual**: a *role-changed* member's `workspace_members` row PERSISTS (only `role`
is updated), so during a transient `check_my_revocation` outage a just-demoted member retains
their pre-demotion effective role for actions gated solely by the middleware gate, until the
RPC recovers (next-request re-check) or the JWT expires (~≤1h). This is not client-inducible
(the RPC takes no client input beyond the JWT iat) and is strictly better than the
503-for-all it replaces. Accepted as the deliberate grace tradeoff.

**Brand-survival threshold:** `single-user incident` — both symptoms harm a single user
directly (lockout / mid-session logout), and the over-correction risk re-opens the exact
#4307 data-plane leak.

**CPO sign-off:** required at plan time (`requires_cpo_signoff: true`). The revocation
gate is the load-bearing prerequisite that gated the `team-workspace-invite` Flagsmith
flip; any change to its failure semantics is a product-blast-radius decision.

**Review-time:** `user-impact-reviewer` invoked at PR review per
`plugins/soleur/skills/review/SKILL.md` conditional-agent block. Must enumerate per
failure mode: (a) transient-RPC-503-for-all regression, (b) fail-open revocation leak
(the over-correction), (c) clock-skew false-positive logout, (d) non-removal JWT-decode
forced logout, (e) raised GoTrue ceiling as an abuse-defense relaxation, (f) cookie
non-propagation on the refreshed-session path.

## Research Insights (consolidated)

- **Premise validation (Phase 0.6):** No external GitHub issue/PR cited by reference in
  the task. Internal artifacts verified live: `configure-auth.sh` has 0 `rate_limit`
  fields; `middleware.ts` calls both `getUser()` (L190) + `getSession()` (L206); the
  #4307 revocation gate + `clearSessionAndRedirect` exist as described; prior plans
  `2026-05-22-feat-workspace-member-session-invalidation` (introduced the gate) and
  `2026-05-29-fix-invited-user-signin-otp-rate-limit` (narrow OTP fix) both exist and
  are read. The `durable-session-resume` brainstorm/plans (2026-06-14) are about
  **backend agent chat-sessions**, NOT web auth sessions — confirmed NOT this surface.
- **GoTrue defaults (framework-docs):** `rate_limit_email_sent` 30/hr project-wide;
  `rate_limit_verify` 30/hr; per-user OTP send window 60s → 429 `over_email_send_rate_limit`;
  token-verification 429 → `over_request_rate_limit`. Management API field names:
  `rate_limit_email_sent`, `rate_limit_verify`, `rate_limit_token_refresh`,
  `rate_limit_signup`, `rate_limit_otp`. JWT default lifetime 1h; refresh-token rotation
  with ~10s reuse window. **Verify exact field names + accepted units against the live
  `PATCH /v1/projects/{ref}/config/auth` API at Phase 0 before editing the script** —
  the framework-docs values are doc/source-derived, not live-probed (see Sharp Edges).
- **Defense-relaxation rule:** Raising any GoTrue ceiling MUST name the new value and the
  threat the old value bounded (abuse/spam-email cost), per
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md`. Proposed new ceilings (to be
  confirmed at CPO sign-off): `rate_limit_email_sent` 30 → 100/hr; `rate_limit_verify`
  30 → 150/hr. The per-user 60s OTP window is left at default (the client cooldown already
  matches it; relaxing it would re-open the invited-user double-send class).
- **Middleware fail-open vs fail-closed (`2026-03-20-middleware-error-handling-fail-open-vs-closed.md`):**
  revocation is a security boundary (fail-closed correct for *genuine* revocation), but
  transient infra errors and non-removal JWT-decode failures are NOT revocations — they
  should not force a logout/503-for-all. Distinguish "RPC says revoked=true" (act) from
  "RPC errored" (degrade gracefully).
- **Dual-shape cookie clear (`2026-05-23-service-role-revoke-strip-and-dual-shape-cookie-clear.md`):**
  the existing clear uses `headers.append("Set-Cookie", …)` (NOT `cookies.set`, which
  dedupes by name) — preserve this if the clear path is touched.
- **Open Code-Review Overlap:** see section below.
- **Labels verified present:** `bug`, `priority/p1-high`, `domain/engineering`,
  `semver:patch` all exist (`gh label list`).

## Hypotheses (ranked, falsify before fixing — per constitution "verify root cause")

1. **[Symptom 1, primary]** Transient `check_my_revocation` RPC errors return 503 for all
   authenticated requests → user-visible "site died / logged out." *Falsify:* search
   Sentry for `op: revocation_gate.db_error` events and 503 spikes correlated with logout
   reports; reproduce by forcing the RPC to error in a local middleware test.
2. **[Symptom 1, DOWNGRADED — likely NOT the cause]** Clock-skew false-positive revocation.
   *Deepen-plan finding:* `check_my_revocation` (migration 067:81-87) uses strict
   `revoked_after > p_jwt_iat` which the migration comment states "absorbs ±1s clock skew
   on the safer (deny) side per AC6" — i.e. skew is *deliberately* deny-favoring. A
   never-removed user has **no** `workspace_member_removals` row, so the predicate returns
   no rows regardless of skew → cannot false-positive. Skew could only matter for a
   genuinely-removed user whose JWT was issued in the same ±1s as `revoked_after`, and the
   design intentionally revokes that case. **Do NOT add skew tolerance** — it would relax a
   deliberate security-favoring edge. Keep this hypothesis only as a falsification target;
   do not act on it.
3. **[Symptom 1, tertiary]** Non-removal JWT-decode (`malformed_jwt`/`no_iat`) forces
   `session-error` logout on a token that is actually valid. *Falsify:* inspect a real
   refreshed access token's payload shape; reproduce with a base64url-padding edge case.
4. **[Symptom 2, primary]** GoTrue project-wide `rate_limit_email_sent = 30/hour` (default)
   exhausts under normal small-user-base OTP traffic. *Falsify:* check Supabase dashboard
   Auth Rate Limits for the prd project current values; correlate 429 `over_email_send_rate_limit`
   Sentry events (`op: signInWithOtp`) with the 30/hr boundary.
5. **[Symptom 2, secondary]** Copy conflates the 60s transient cooldown with a hard
   lockout, so users perceive blocking even when recovery is seconds away. *Falsify:*
   read `error-messages.ts` mapping + `useOtpFlow` cooldown display.

A `single-user incident` plan must reproduce/confirm each acted-on hypothesis at /work
Phase 0 before changing code; do not relax the ceiling or alter fail-closed semantics on a
guess.

## Implementation Phases

> Phase ordering is load-bearing: the diagnostic/repro phase precedes any behavioral change
> (constitution "verify root cause"); the two symptoms are independent and can land in either
> order within the same PR.

### Phase 0 — Diagnose & confirm (no code change)
- Confirm GoTrue prd current rate-limit values via Supabase Management API GET
  `/v1/projects/{ref}/config/auth` (read-only) — record actuals for the drift note.
- **Verify the exact `rate_limit_*` field names + accepted value units** against the live
  PATCH API (Sharp Edge: doc-derived names must be live-confirmed before scripting).
- Pull Sentry for `op: revocation_gate.db_error` / `revocation_gate.malformed_jwt` /
  `revocation_gate.no_iat` and `op: signInWithOtp` 429s (`hr-no-dashboard-eyeball-pull-data-yourself`
  — query the API, emit a deterministic verdict, do not eyeball the dashboard).
- Read `apps/web-platform/supabase/migrations/067_*revocation*.sql` to confirm the
  `check_my_revocation` predicate and any existing skew tolerance.

### Phase 1 — Symptom 1: harden the revocation gate (`apps/web-platform/middleware.ts`, possibly migration 067)
- **Transient-error grace (the load-bearing change):** on `revokeError` (RPC failure),
  do NOT 503-for-all and do NOT log out. Choose ONE, to be settled at deepen-plan via
  precedent-diff + CPO sign-off: (a) a short server-side **grace window** that allows the
  request through while the JWT is otherwise valid and re-checks on the next request, or
  (b) a bounded **per-isolate cache / retry** so a single transient blip doesn't cascade.
  The genuine `revoked === true` path stays fail-closed (cookie-clear → /login). Name the
  exact new failure semantics in the plan body (defense-relaxation discipline).
- **Non-removal JWT-decode failures:** `malformed_jwt` / `no_iat` should be treated as a
  *retryable session-validation hiccup*, not a definitive logout, unless the token is
  genuinely unusable (the `getUser()` call already failed). Verify a real refreshed token's
  payload always carries `iat`; if `getUser()` succeeded, a missing-`iat` decode is a
  decoder bug, not a revocation.
- **Clock-skew: NO CHANGE (deepen-plan correction).** Migration 067's strict `>` is
  deliberately deny-favoring on ±1s skew, and a never-removed user has no row to match.
  Do NOT add skew tolerance — it would relax a security-favoring edge and is not the
  Symptom-1 cause. (Hypothesis 2 is a falsification target only.)
- **Collapse redundant auth calls:** derive the access token from the `getUser()`-refreshed
  client without a second `getSession()` round trip where the SSR client exposes it; if
  `getSession()` is genuinely required for the raw token, document why (framework-docs §2.4).
- Preserve the dual-shape `headers.append` cookie clear on any genuine-revocation path.
- **No migration needed** (deepen-plan correction): the fix lives entirely in
  `middleware.ts`. The `check_my_revocation` RPC body (migration 067) is correct as-is —
  the strict-`>` skew handling is deliberate; do NOT re-issue 067 or add a skew migration.
- Files to edit: `apps/web-platform/middleware.ts`.

### Phase 2 — Symptom 2: raise GoTrue ceilings + tighten copy
- **`apps/web-platform/supabase/scripts/configure-auth.sh`:** add `rate_limit_email_sent`,
  `rate_limit_verify` (and any sibling the Phase 0 probe confirms is load-bearing) to the
  PATCH payload with the named new ceilings (proposed: email 100/hr, verify 150/hr — final
  values at CPO sign-off). Add an inline comment documenting old→new and the abuse-cost
  tradeoff. This is externalized config, not server code — see Infrastructure (IaC).
- **`apps/web-platform/lib/auth/error-messages.ts`:** the two messages are ALREADY distinct
  (deepen-plan confirmed). The only change is to *soften the lockout tone / surface the
  recovery window* on the transient send-429 path so a 60s cooldown does not read as a hard
  lockout. Do NOT regress the existing code/status-first mapping. If, after raising the
  project-wide ceiling, the residual blocking is only ever the 60s per-user window, the copy
  + visible countdown is the complete UX fix for the "blocked easily" perception.
- Optionally surface the resend countdown more prominently in `useOtpFlow.ts` /
  `OtpCodeStep` so the user sees the recovery window (UX polish, scope-confirm at review).
- Files to edit: `apps/web-platform/supabase/scripts/configure-auth.sh`,
  `apps/web-platform/lib/auth/error-messages.ts` (+ `__tests__`/`test/` siblings).

### Phase 3 — Tests + observability
- Add/extend tests (vitest — `./node_modules/.bin/vitest run`, NOT `bun test`; see Sharp
  Edges). Cover: transient-RPC-error does NOT log out / 503-for-all; genuine revocation
  STILL logs out (security-boundary regression guard); clock-skew within tolerance is not
  revoked; error-messages mapping for `over_email_send_rate_limit` vs `over_request_rate_limit`.
- Observability section below; ensure the new grace/transient path emits a distinct Sentry
  op slug so operators can see transient-RPC degradation without SSH.

## Files to Edit
- `apps/web-platform/middleware.ts` (revocation-gate transient-error grace; collapse double auth call; skew tolerance)
- `apps/web-platform/supabase/scripts/configure-auth.sh` (add `rate_limit_*` fields)
- `apps/web-platform/lib/auth/error-messages.ts` (distinct cooldown vs lockout copy)
- `apps/web-platform/lib/auth/useOtpFlow.ts` / `components/auth/otp-code-step.tsx` (optional: surface countdown — scope-confirm)
- Test siblings under `apps/web-platform/test/**` (vitest) for the above

## Files to Create
- New test file(s): `apps/web-platform/test/<...>.test.ts` for the revocation-gate transient/genuine paths (jsdom component tests for the OTP copy must live under `test/`; a `useOtpFlow` logic test may be co-located `lib/auth/*.test.ts` per the `lib/**/*.test.ts` include glob — see Sharp Edges).
- (No migration is created — deepen-plan confirmed migration 067's RPC is correct as-is.)

## Open Code-Review Overlap
3 open code-review issues mention the touched files:
- **#2591** (docs(security): document CSP middleware + route intersection for binary types) — touches `middleware.ts`. **Acknowledge:** different concern (CSP/binary-type docs), not the revocation gate. Leave open.
- **#2196** (refactor(rate-limiter): dedupe prune-interval/compaction, unref, test helper) — touches `rate-limiter.ts`. **Acknowledge:** this plan does NOT touch `rate-limiter.ts` (WS limiter, unrelated surface). Leave open.
- **#2197** (refactor(billing): SubscriptionStatus + throttle doc + Sentry breadcrumb UUID) — touches `rate-limiter.ts`. **Acknowledge:** same — out of scope. Leave open.

## Acceptance Criteria

### Pre-merge (PR)
- [x] AC1 — A transient `check_my_revocation` RPC error no longer returns 503 for an
  otherwise-valid authenticated session; a vitest covering the `revokeError` branch asserts
  the request is allowed through (grace) and the user is NOT redirected to `/login`.
  *(middleware.revocation-redirect.test.ts "transient … → GRACE"; op `revocation_gate.transient_grace`.)*
- [x] AC2 — A genuine `revoked === true` row STILL clears cookies and redirects to
  `/login?revoked=<reason>` (security-boundary regression guard); test asserts the
  `Set-Cookie` clear headers are present on the redirect (dual-shape). *(unchanged genuine-revocation tests stay green.)*
- [x] AC3 — (Skew is deliberately deny-favoring; NO change.) Regression guard: a test
  confirms `check_my_revocation`'s strict `>` semantics are unchanged and a never-removed
  user is never revoked (no row). *(migration 067 untouched; verified.)*
- [x] AC4 — Middleware retains exactly ONE `getSession()` call, documented: it reads the
  raw access-token bytes for the local `iat` decode (getUser() authenticates but does not
  expose the token); NOT a redundant re-auth round trip. `grep -c getSession middleware.ts` → 1-with-rationale.
- [x] AC5 — `grep -cE "rate_limit_email_sent|rate_limit_verify" apps/web-platform/supabase/scripts/configure-auth.sh`
  returns ≥ 2 (the new fields are present as JSON keys in the PATCH payload), with an inline
  old→new comment present (actual prd `2 -> 100` / `30 -> 150`). *(configure-auth-rate-limits.test.ts AC5 guard.)*
- [x] AC6 — (The two messages are ALREADY distinct — deepen-plan confirmed:
  `over_request_rate_limit`→`RATE_LIMIT_MESSAGE`, `email rate limit exceeded`→`EMAIL_SEND_RATE_LIMIT_MESSAGE`.)
  Regression guard: a test pins that these two codes/patterns continue to map to their two
  distinct constants (no accidental collapse during the copy-tone refinement). The Phase-2
  change is to soften the lockout *tone* / surface the recovery window, not to introduce a
  distinction that already exists.
- [x] AC7 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes. *(TSC_EXIT=0.)*
- [x] AC8 — `cd apps/web-platform && ./node_modules/.bin/vitest run <touched test paths>` passes. *(65/65 touched; full webplat shard 9901 passed.)*

### Post-merge (operator)
- [ ] AC9 — `configure-auth.sh` re-run against **prd** (and dev) so the new ceilings take
  effect; verify via Management API GET. **Tracked in #5330** (operator + CPO sign-off on the
  100/150 ceilings; the script has no automated deploy path, so apply is genuinely post-merge).
- [ ] AC10 — PR body uses `Ref #5330` (not `Closes`); #5330 is closed after AC9 verifies the
  applied ceilings. Drift baseline (prd actuals 2026-06-15) recorded in #5330 + PR body.

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)
**Status:** carry-forward (assessed inline; this is the primary domain)
**Assessment:** Behavioral fix to a security-boundary middleware gate + an externalized
auth-config change. Key risk is the fail-open over-correction (data-plane leak). The
revocation gate's fail-closed posture for *genuine* revocations is non-negotiable; only the
*transient-error* and *non-removal-decode* responses are relaxed. CTO to confirm the
grace-window vs cache approach at deepen-plan precedent-diff (Phase 4.4).

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no new user-facing page/flow; edits are error copy on the existing
`/login` form + middleware redirect reasons)
**Skipped specialists:** none — no UI-surface file under `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` is CREATED. The only client-facing change is
copy in `error-messages.ts` (and an optional countdown surface in an existing component),
which is ADVISORY, not BLOCKING. A copywriter pass on the two error strings is recommended
at review but not gating.
**Pencil available:** N/A (no UI surface)

#### Findings
The login form, OTP step, and revoked banner already exist (`login-form.tsx`,
`otp-code-step.tsx`); this plan only edits the copy they render and the middleware redirect
reasons. No wireframe needed.

## Infrastructure (IaC)

### Terraform changes
None directly. The GoTrue auth config is managed via the **Supabase Management API** through
`apps/web-platform/supabase/scripts/configure-auth.sh` (the existing, idempotent config
script), not Terraform — this matches the established pattern (the magiclink rate-limit
runbook notes the auth rate-limit settings are "dashboard-only, not yet captured in
Terraform"). This plan keeps the config in `configure-auth.sh` (the repo's externalized,
re-runnable source of truth) rather than a dashboard click — satisfying the no-manual-
provisioning rule by routing the change through the committed script.

### Apply path
Re-run `configure-auth.sh` against dev and prd with the project's existing creds
(`SUPABASE_ACCESS_TOKEN`, `PROJECT_REF`, `RESEND_API_KEY` from Doppler). The script is a
PATCH (idempotent, partial-update); re-running applies only the new `rate_limit_*` fields.
Blast radius: auth-config only; no downtime. Wire AC9 into the post-merge config-apply step,
not an operator dashboard action.

### Distinctness / drift safeguards
dev and prd are distinct Supabase projects (`hr-dev-prd-distinct-supabase-projects`); apply
to both. Record the pre-change prd values (Phase 0 GET) in the PR body for drift detection,
mirroring the magiclink runbook's "current values recorded for drift detection" pattern.

### Vendor-tier reality check
Supabase auth rate-limit fields are available on all tiers via the Management API; no paid-
tier gate. Raising `rate_limit_email_sent` increases Resend email volume — within Resend's
current tier per `knowledge-base/operations/expenses.md` (confirm at review).

## Observability

```yaml
liveness_signal:
  what: revocation-gate transient-error rate + OTP 429 rate
  cadence: per-request (middleware); aggregated in Sentry
  alert_target: Sentry (existing project) + Better Stack if a threshold rule exists
  configured_in: apps/web-platform/middleware.ts (reportEdgeSilentFallback ops); lib/auth/useOtpFlow.ts (reportSilentFallback op signInWithOtp)
error_reporting:
  destination: Sentry via reportEdgeSilentFallback (edge) / reportSilentFallback (client)
  fail_loud: true (existing ops are mirrored; the new transient-grace path adds a distinct op slug)
failure_modes:
  - mode: transient revocation-RPC error (was 503-for-all)
    detection: new Sentry op slug e.g. revocation_gate.transient_grace
    alert_route: Sentry; spike indicates DB instability without user-facing logout
  - mode: genuine revocation
    detection: existing redirect to /login?revoked=<reason> (no error event — expected path)
    alert_route: n/a (expected)
  - mode: GoTrue OTP 429 (over_email_send_rate_limit / over_request_rate_limit)
    detection: existing op signInWithOtp / verifyOtp extra.status=429
    alert_route: Sentry; post-fix this rate should drop after the ceiling raise
logs:
  where: Sentry (cross-tenant project, PII-scrubbed) + pino structured logs on the node
  retention: per existing Sentry/Better Stack retention
discoverability_test:
  command: "curl -s 'https://sentry.io/api/0/projects/<org>/<proj>/events/?query=op:revocation_gate.transient_grace' -H 'Authorization: Bearer <token>' | jq '.[0]'"
  expected_output: a JSON event object (or empty array if no transient errors in window) — NO ssh required
```

## Test Scenarios (Given/When/Then)

- **Given** an authenticated user with a valid (non-revoked) session **When** the
  `check_my_revocation` RPC transiently errors **Then** the request is allowed through (no
  503, no logout) and a `revocation_gate.transient_grace` Sentry op is emitted.
- **Given** a workspace member who was just removed (revocation row present) **When** they
  make any authenticated request **Then** cookies are cleared (dual-shape `Set-Cookie`) and
  they are redirected to `/login?revoked=removed` (security boundary intact).
- **Given** a valid JWT whose `iat` is within the clock-skew tolerance band of `revoked_after`
  **When** the gate evaluates **Then** the user is NOT revoked.
- **Given** `configure-auth.sh` has been re-run **When** the Management API GET is read
  **Then** `rate_limit_email_sent` = 100 (or final value) and `rate_limit_verify` = 150.
- **Given** a user requests an OTP twice within 60s **When** GoTrue returns 429
  `over_email_send_rate_limit` **Then** the UI shows the transient "wait ~Ns" copy (with the
  visible cooldown), not a hard-lockout message.

## Risks & Mitigations — Precedent Diff (deepen-plan Phase 4.4)

- **`configure-auth.sh` rate-limit PATCH — precedent EXISTS, reuse verbatim.** The script
  already issues `PATCH /v1/projects/{ref}/config/auth` with a `jq -n`-built JSON body
  (`site_url`, `mailer_otp_*`, `smtp_*`). Adding `rate_limit_email_sent` / `rate_limit_verify`
  as integer keys to that same `jq -n` object is the canonical form — the PATCH is a true
  partial update (deepen-plan verified), so existing fields are untouched. No new mechanism;
  extend the existing payload + add an `--arg`/literal for the new ints. **Mitigation:** keep
  the new keys in the same PATCH so a single re-run applies them; document old→new in a comment.
- **`check_my_revocation` SECURITY DEFINER RPC — NOT modified.** Migration 067 already follows
  the canonical `SECURITY DEFINER` + `SET search_path = public, pg_temp` precedent
  (`cq-pg-security-definer-search-path-pin-pg-temp`). This plan does NOT touch it (the fix is
  middleware-only), so no precedent-diff against a re-issued body is needed. Recorded so /work
  does not "improve" the RPC and inherit the diff-against-067 obligation.
- **Middleware transient-error grace — pattern is semi-novel here.** The codebase's existing
  middleware precedents are the T&C gate (fail-OPEN to `/accept-terms` on `tcError`) and the
  revocation gate (fail-CLOSED 503 on `revokeError`). The grace path is a THIRD shape: allow
  the request through (do not log out) on a *transient* revocation-RPC error while the JWT is
  otherwise valid. **Mitigation:** model it on the T&C gate's fail-open structure but scoped to
  transient errors only, and settle grace-window-vs-cache at CPO sign-off (the genuine-revoked
  branch stays fail-closed). Flag for architecture-strategist scrutiny at review — this is the
  load-bearing security-boundary decision.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled.)
- **GoTrue field names confirmed; still re-GET after PATCH.** Deepen-plan confirmed the
  Management-API config-body fields against the Supabase OpenAPI schema: `rate_limit_email_sent`,
  `rate_limit_verify`, `rate_limit_otp`, `rate_limit_token_refresh` (integer, per-hour; partial
  PATCH). The remaining risk is a typo or a stale field on a given project, so Phase 0 still
  GETs `/v1/projects/{ref}/config/auth` to record current values and AC9 re-GETs after PATCH to
  verify the change applied (a fabricated/typo'd field is silently ignored — 200 OK, no state
  change).
- **Fail-OPEN is the catastrophic over-correction.** Relaxing the transient-error response
  must NOT relax the genuine-revocation response. AC2 is the regression guard; do not let a
  refactor collapse both branches.
- **Test runner is vitest, not bun.** `apps/web-platform/bunfig.toml` has
  `pathIgnorePatterns = ["**"]` → `bun test` reports "filter did not match." Use
  `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Typecheck is
  `./node_modules/.bin/tsc --noEmit` (NOT `npm run -w` — no root `workspaces` field).
- **Test file paths must satisfy vitest's `include:` globs (deepen-plan verified actuals):**
  node project = `["test/**/*.test.ts", "lib/**/*.test.ts"]`; jsdom project =
  `["test/**/*.test.tsx"]` (`apps/web-platform/vitest.config.ts`). So a `useOtpFlow` LOGIC
  test MAY be co-located `lib/auth/useOtpFlow.test.ts` (the `lib/**` glob collects it), but a
  jsdom/RTL `.test.tsx` component test MUST live under `test/` — a co-located
  `components/**/*.test.tsx` is silently never run.
- **Raising `rate_limit_email_sent` is a defense relaxation.** Name the new ceiling and the
  abuse-cost it no longer bounds (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`).
  Do NOT relax the per-user 60s OTP window — the client cooldown matches it and relaxing it
  re-opens the invited-user double-send class (#4638).
- **Apply to BOTH dev and prd** distinct Supabase projects; record pre-change prd values for
  drift detection (magiclink runbook pattern).
- **GoTrue field semantics (deepen-plan verified):** `rate_limit_email_sent` / `rate_limit_otp`
  are **project-wide** per-hour integers; `rate_limit_verify` / `rate_limit_token_refresh` are
  **per-IP** per-hour. The per-user **60s OTP send window** is a *separate* min-frequency knob
  (not one of these count fields) — raising the count ceilings does NOT shorten the 60s window,
  and the client cooldown already matches it. Do not conflate the two when setting values.
- **No migration in scope (deepen-plan):** the revocation fix is `middleware.ts`-only;
  migration 067's `check_my_revocation` is correct as-is. If a future change DID touch it,
  `ls supabase/migrations/` (latest is 103 → next 104) and diff against 067's body so no
  guard is dropped — but that is out of scope here.
