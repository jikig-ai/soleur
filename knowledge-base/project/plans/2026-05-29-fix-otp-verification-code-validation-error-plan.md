---
title: "fix: OTP verification fails with generic \"Something went wrong\" — code-aware error mapping + observability"
date: 2026-05-29
type: fix
status: planned
branch: feat-one-shot-fix-otp-verification-code-validation-error
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
issues: []
related:
  - "#3363 / PR #3983 — Custom Access Token Hook (migrations 047-050)"
  - "#1765 / 2026-04-11-map-supabase-errors-to-friendly-messages.md"
  - "PR #4038 — bounded retry on GoTrue over_request_rate_limit 429 (tenant.ts only)"
  - "2026-05-18-supabase-custom-access-token-hook-discriminator.md"
  - "knowledge-base/engineering/ops/runbooks/supabase-magiclink-rate-limit.md"
---

# fix: OTP verification fails with generic "Something went wrong"

🐛 **Bug.** Login fails for `ops@jikigai.com`: after entering the 6-digit email
verification code on the "Enter verification code" screen, the app spends a long
time validating and then renders a red `Something went wrong. Please try again.`
The code field showed `997473`. This is an OTP verification failure at the auth
step. The generic message means the underlying GoTrue error fell through every
branch of the error-mapping layer, so the user (and operator triage) gets no
actionable signal and no path forward.

## Overview

`components/auth/login-form.tsx:handleVerifyOtp` calls
`supabase.auth.verifyOtp({ email, token, type: "email" })` and, on any error,
sets `setError(mapSupabaseError(error.message))`. `mapSupabaseError`
(`lib/auth/error-messages.ts:38`) matches **only four freetext message regexes**
(`signups not allowed for otp`, `email rate limit exceeded`, `invalid otp`,
`token … expired`) and falls back to `DEFAULT_ERROR_MESSAGE =
"Something went wrong. Please try again."` for everything else.

The Supabase auth-js SDK error (`AuthError`) carries a **structured `code` field**
(`node_modules/@supabase/auth-js/dist/module/lib/errors.d.ts:20` —
`code: ErrorCode | (string & {}) | undefined`) and an HTTP `status`. The
canonical codes (`error-codes.d.ts`) include `otp_expired`,
`over_request_rate_limit`, `over_email_send_rate_limit`, `otp_disabled`,
`session_expired`, `validation_failed`, plus generic transport failures
(network/`fetch` throw, GoTrue 5xx). **None of these are matched by the freetext
regexes** — so the most operationally-likely failures all render the dead-end
generic copy:

- **`over_request_rate_limit` (HTTP 429)** — GoTrue's per-IP token-verification
  ceiling (30 / 5 min, per `supabase-magiclink-rate-limit.md`). The dashboard
  login `verifyOtp` shares this ceiling. This is the leading candidate for the
  reported "long time then error": the SDK retries/backs off internally, then
  returns a 429 whose message does not contain "email rate limit exceeded"
  (that string is the *email-send* limit, a different code). Falls through →
  generic.
- **Custom Access Token Hook 500** — `public.runtime_jwt_mint_hook`
  (migrations 047/049/050) fires on **every** token-issuance event in the project,
  including this dashboard OTP login. It has **no `EXCEPTION WHEN OTHERS`** (by
  design — security-critical), so any failure inside it (e.g. the intent-gate
  `DELETE FROM public.runtime_mint_intent` hitting a missing-table / missing-grant
  deploy-drift state, or `precheck_jwt_mint` raising `45001` if the intent row is
  consumed via the documented ~700ms race) propagates as GoTrue **HTTP 500**.
  The SDK surfaces a 500 error whose message matches no regex → generic. The
  hook is also a plausible source of the latency the user observed.
- **Network / fetch throw** — `verifyOtp` can reject (not resolve with `error`)
  on a transport failure; the current code only handles the resolved-`error`
  branch.

**The fix is twofold and surgical, no new infrastructure:**

1. **Code-aware error mapping.** Extend the mapping layer to inspect
   `error.code` / `error.status` first (structured, version-stable), then fall
   back to the existing freetext regexes (preserved for back-compat). Give
   `over_request_rate_limit`, `otp_expired`, server-5xx, and network failures
   their own actionable copy. This converts the dead-end generic message into a
   correct, recoverable instruction (wait / request a new code / retry).
2. **Observability.** The existing `reportSilentFallback` call already mirrors
   `errorCode`/`errorName` to Sentry — but only the *code*, not `status`. Add
   `status` and the GoTrue request-id (if present) so an operator can
   distinguish a 429-rate-limit from a 500-hook-failure without SSH or a repro.
   This is the discoverability_test surface (see `## Observability`).

This plan does **not** change the hook, the migrations, or the runtime-mint
substrate — those are correct as shipped (#3363 / PR #3983). It hardens the
*user-facing dashboard login* error surface so a failing `verifyOtp` produces an
accurate, recoverable message and a triage-able Sentry event instead of a silent
dead end.

## Research Reconciliation — Spec vs. Codebase

No spec file exists for this branch (direct one-shot entry). The bug report's
claims were validated against the codebase:

| Report claim | Codebase reality | Plan response |
|---|---|---|
| "Something went wrong. Please try again." on verify screen | Exact literal at `lib/auth/error-messages.ts:1` (`DEFAULT_ERROR_MESSAGE`), rendered at `login-form.tsx:149` via `mapSupabaseError` fallthrough | Confirmed surface; fix the fallthrough cause |
| "spends a long time then fails" | No client-side timeout; latency comes from GoTrue (hook execution, SDK internal retry/backoff on 429) | Add code-aware copy for 429 + 5xx; add `status` to Sentry so latency-source is identifiable |
| Generic OTP/magic-code verification failure | `verifyOtp` error path maps only 4 freetext regexes; structured `error.code` (incl. `over_request_rate_limit`, `otp_expired`) is ignored | Map on `error.code`/`status` first, freetext fallback preserved |
| Single login surface | TWO identical surfaces: `login-form.tsx:99` AND `signup/page.tsx:74`; `oauth-buttons.tsx:94` also calls `mapSupabaseError` | Sweep both verifyOtp call sites; oauth path inherits the improved mapping for free |

**Premise validation:** `gh issue list --search "otp verification code something went
wrong"` and `"login verify otp in:title"` returned zero — this is a fresh bug
report, not a stale/closed premise. No external blocker issues cited.

## User-Brand Impact

**If this lands broken, the user experiences:** the dashboard login screen they
hit today — a correct 6-digit code rejected with a dead-end "Something went
wrong" and no instruction on what to do, after a multi-second wait. The founder
(`ops@jikigai.com`, the operator themselves) cannot get into their own product.

**If this leaks, the user's data/workflow is exposed via:** N/A for the mapping
change (it only widens which raw GoTrue error strings → which friendly copy;
`reportSilentFallback` already forwards only typed enum fields, never
`error.message`, because that string embeds the email and Sentry is a shared
project). The plan MUST preserve that PII discipline: the new mapping reads
`error.code`/`error.status` (enums/ints, no PII) and the Sentry payload adds only
`status` + request-id (no PII). Do **not** add `error.message` to the Sentry
`extra`.

**Brand-survival threshold:** single-user incident. A single founder locked out
of the product by an uninformative auth error is the canonical brand-survival
failure — the first impression is a broken front door. `requires_cpo_signoff:
true` set; CPO must ack the approach before `/work`. `user-impact-reviewer` runs
at review time.

## Hypotheses

Ranked by likelihood given "long wait → generic error on a code the user
believes is correct":

1. **`over_request_rate_limit` (HTTP 429) on `verifyOtp`** *(most likely)* —
   GoTrue per-IP token-verification ceiling (30/5min). Shared by dashboard +
   runtime-mint paths from the same egress IP. The "long wait" is the SDK's
   internal handling + GoTrue processing. Message does NOT contain "email rate
   limit exceeded" → falls through to generic. **Verification:** the new Sentry
   payload (`errorCode: "over_request_rate_limit"`, `status: 429`) confirms or
   refutes this directly from the next reproduction; no SSH needed.
2. **Custom Access Token Hook 500** — `runtime_jwt_mint_hook` raises (no `WHEN
   OTHERS`) on this dashboard login due to either (a) deploy-drift: migration
   049/050 `runtime_mint_intent` table/grants absent in the target project while
   the hook is registered, so the hook's `DELETE` errors; or (b) the documented
   ~700ms intent-row race consuming a leftover row → `precheck_jwt_mint`
   `45001`. Surfaces as GoTrue 500 → generic. **Verification:** Sentry
   `status: 500` distinguishes from (1). If (a), the post-merge operator probe
   (Supabase MCP — see `## Observability`) confirms table+grant presence; remedy
   is a migration re-apply, tracked separately, NOT this PR.
3. **Network / fetch transport failure** — `verifyOtp` rejects rather than
   resolving with `error`; current handler only covers the resolved-`error`
   branch (the throw would surface via the page's error boundary or be
   swallowed). **Verification:** add a try/catch around `verifyOtp` and map the
   thrown error through the same layer.

The fix is **robust to all three** because it gives each a distinct, recoverable
message and a distinguishable Sentry event — without needing to first prove
which one `ops@jikigai.com` hit.

## Files to Edit

- `apps/web-platform/lib/auth/error-messages.ts` — add a code/status-aware
  mapping path ahead of the freetext regexes. Introduce `mapSupabaseAuthError(error)`
  that accepts the structured `{ code?, status?, message }` shape and returns
  friendly copy; keep `mapSupabaseError(message)` as a thin back-compat shim
  delegating to the new fn with `{ message }`. New copy constants:
  - `over_request_rate_limit` / status 429 → "Too many attempts right now.
    Please wait a minute and try again." (distinct from the existing email-send
    rate-limit copy)
  - `otp_expired` (and freetext `token … expired`) → existing expired-code copy
  - status ≥ 500 → "Sign-in is temporarily unavailable. Please try again in a
    moment." (covers the hook-500 + GoTrue-5xx class)
  - network/fetch throw (no `status`, name `AuthRetryableFetchError` or generic
    `TypeError`) → "Couldn't reach the sign-in service. Check your connection
    and try again."
- `apps/web-platform/components/auth/login-form.tsx` —
  - `handleVerifyOtp`: wrap `verifyOtp` in try/catch; route both the resolved
    `error` and any thrown error through `mapSupabaseAuthError`. Add `status`
    (and request-id if present) to the `reportSilentFallback` `extra`.
  - (Optional, low-risk) `handleSendOtp`: same `mapSupabaseAuthError` upgrade for
    parity, since `over_email_send_rate_limit` has the same dead-end today.
- `apps/web-platform/app/(auth)/signup/page.tsx` — the `verifyOtp` block
  (lines 74-92) is **structurally identical** to login-form; apply the same
  try/catch + `mapSupabaseAuthError` + `status`-in-Sentry change. (Sweep
  mandated by the verb-class grep: both surfaces share the bug.)
- `apps/web-platform/components/auth/oauth-buttons.tsx:94` — already calls
  `mapSupabaseError(error.message)`; inherits improved freetext fallback for
  free. Upgrade to `mapSupabaseAuthError(error)` only if the OAuth error object
  carries `code`/`status` (verify at /work; otherwise leave as-is with the
  back-compat shim).

## Files to Create

- `apps/web-platform/lib/auth/error-messages.test.ts` — **extend** the existing
  copy-contract test file (do not create new): add cases for each new code/status
  branch (`over_request_rate_limit` → rate copy; `{status:429}` → rate copy;
  `otp_expired` → expired copy; `{status:500}` → unavailable copy; network throw
  → connection copy) and a regression guard that `mapSupabaseError(message)`
  (string-only shim) still returns the legacy mappings.
- `apps/web-platform/test/components/login-form-verify-error.test.tsx` — new
  RTL test mirroring `login-form-revoked-banner.test.tsx` conventions
  (`vi.mock("next/navigation")`, `vi.mock("@/lib/supabase/client")` returning a
  `verifyOtp` that rejects with a `{code:"over_request_rate_limit", status:429}`
  shape): assert the rendered `role="alert"` text is the recoverable rate-limit
  copy, NOT "Something went wrong".

## Open Code-Review Overlap

`gh issue list --label code-review --state open` to be run at /work Phase 0
against the four edited paths above. Record `None` or fold-in disposition.
(No overlap detected at plan time; the area was last touched by #4520/#4418 with
no open scope-outs against `error-messages.ts` or `login-form.tsx`.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `mapSupabaseAuthError({ code: "over_request_rate_limit" })` and
  `mapSupabaseAuthError({ status: 429 })` both return the rate-limit copy (NOT
  the generic message). Asserted in `error-messages.test.ts`.
- [ ] `mapSupabaseAuthError({ code: "otp_expired" })` returns the expired-code
  copy.
- [ ] `mapSupabaseAuthError({ status: 503 })` returns the
  temporarily-unavailable copy.
- [ ] A thrown network error (no `status`, `AuthRetryableFetchError`/`TypeError`)
  routes to the connection-failure copy.
- [ ] `mapSupabaseError("Invalid OTP")`, `("email rate limit exceeded")`,
  `("Token has expired")`, `("Signups not allowed for otp")` still return their
  legacy mappings (back-compat shim regression guard).
- [ ] `login-form-verify-error.test.tsx`: a `verifyOtp` that rejects with
  `{code:"over_request_rate_limit",status:429}` renders the recoverable
  rate-limit copy in `role="alert"`; the literal `Something went wrong` does NOT
  appear.
- [ ] `signup/page.tsx` verifyOtp block routes through `mapSupabaseAuthError`
  with the same try/catch shape (grep: both files import `mapSupabaseAuthError`).
- [ ] `reportSilentFallback` `extra` on both verifyOtp sites includes `status`;
  it does NOT include `error.message` (PII discipline preserved — grep the diff:
  no `message:` key added to any Sentry `extra`).
- [ ] `./node_modules/.bin/vitest run lib/auth/error-messages.test.ts test/components/login-form-verify-error.test.tsx`
  passes (runner is vitest; `bunfig.toml` blocks `bun test` discovery).
- [ ] `npx tsc --noEmit` clean.

### Post-merge (operator)

- [ ] **Automatable via Supabase MCP** (not operator-only): confirm
  `public.runtime_mint_intent` table exists with the migration-049 grants in the
  target project, and that `runtime_jwt_mint_hook` is the registered Custom
  Access Token Hook — this rules in/out Hypothesis 2(a) (deploy drift). If the
  table/grants are absent, file a separate migration-reapply issue (NOT this PR's
  scope). Run at ship post-merge verification via `mcp__plugin_supabase_supabase__*`.

## Test Scenarios

1. Rate-limited verify (429) → user sees "Too many attempts… wait a minute",
   Sentry event tagged `over_request_rate_limit` / `status:429`.
2. Expired code (`otp_expired`) → "Your sign-in code has expired. Please request
   a new one."
3. Hook/GoTrue 5xx (`status:500`) → "Sign-in is temporarily unavailable…",
   Sentry tagged `status:500` (distinguishes from rate-limit for triage).
4. Network drop (fetch throw) → "Couldn't reach the sign-in service…".
5. Genuinely wrong code (`invalid otp` / `otp_expired`) → existing invalid/expired
   copy (regression).
6. Unknown novel GoTrue error → still falls back to the generic message (the
   safety net is preserved, just no longer the *first* line of defense).

## Observability

```yaml
liveness_signal:
  what: client-side reportSilentFallback → Sentry on every verifyOtp/signInWithOtp error
  cadence: per failed auth attempt (event-driven, no polling)
  alert_target: Sentry project (existing web-platform), feature=auth op=verifyOtp
  configured_in: components/auth/login-form.tsx + app/(auth)/signup/page.tsx (reportSilentFallback call)
error_reporting:
  destination: Sentry via lib/client-observability reportSilentFallback
  fail_loud: true (mirrors before the page can unload; existing pattern preserved)
failure_modes:
  - mode: rate-limit (over_request_rate_limit / 429)
    detection: Sentry extra.errorCode == "over_request_rate_limit" || extra.status == 429
    alert_route: Sentry auth dashboard; recurring spike → revisit per-IP ceiling (runbook supabase-magiclink-rate-limit.md)
  - mode: hook/GoTrue 5xx (500)
    detection: Sentry extra.status >= 500 on op=verifyOtp
    alert_route: Sentry; non-zero rate ⇒ check runtime_jwt_mint_hook + runtime_mint_intent deploy state (Supabase MCP probe)
  - mode: network/fetch throw
    detection: Sentry extra.errorName == "AuthRetryableFetchError" || no status field
    alert_route: Sentry; correlates with client connectivity, not server
logs:
  where: Sentry events (extra.errorCode, extra.errorName, extra.status) + console.error in dev tools
  retention: Sentry project default
discoverability_test:
  command: "grep -n 'status' apps/web-platform/components/auth/login-form.tsx && ./node_modules/.bin/vitest run test/components/login-form-verify-error.test.tsx"
  expected_output: "status added to reportSilentFallback extra; verify-error test asserts recoverable copy (no ssh)"
```

## Domain Review

**Domains relevant:** Product, Engineering (security-adjacent: auth surface).

### Engineering

**Status:** reviewed
**Assessment:** Pure client-side error-handling change on the user-facing auth
surface; no migration, no hook, no infra. Security-adjacent because it touches
the login path — the load-bearing constraint is PII discipline (no `error.message`
to Sentry; only enum `code`/int `status`). No regulated-data write surface
(read-only error inspection), so the GDPR gate (Phase 2.7) is a near-miss: the
change processes an auth error object but adds no new processing/storage of
personal data — the Sentry payload is *narrowed-safe* (enums only). Note carried
forward; no new lawful-basis question.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** ux-design-lead (copy-only change to an existing screen,
no new surface/flow), copywriter (no domain leader recommended; copy strings are
listed inline in Files to Edit for review)
**Pencil available:** N/A

#### Findings

Modifies copy on an existing screen (the "Enter verification code" error line) —
no new page, modal, or flow. Mechanical-escalation scan: no new file under
`components/**/*.tsx` that is a user-facing surface beyond a test file. ADVISORY,
auto-accepted in pipeline. The new copy strings are enumerated in Files to Edit so
review can sanity-check brand voice inline.

## Infrastructure (IaC)

Not applicable — no new server, service, cron, secret, vendor, DNS, cert, or
firewall rule. Pure code change against the already-provisioned web-platform
surface (`apps/web-platform/lib`, `components`, `app`). Phase 2.8 skip condition
met.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (Filled above.)
- **Runner is vitest, not bun.** `apps/web-platform/bunfig.toml` sets `[test]
  pathIgnorePatterns = ["**"]` — `bun test <file>` reports "filter did not match"
  even when the file exists. Use `./node_modules/.bin/vitest run <path>`.
- **Two identical verifyOtp surfaces.** `login-form.tsx` AND `signup/page.tsx`
  share the bug; a fix to one without the other leaves signup's verify dead-end
  live. AC enforces both via grep.
- **PII discipline is load-bearing.** `error.message` embeds the email on OTP
  errors and Sentry is a shared cross-tenant project. The new mapping reads only
  `error.code`/`error.status` and the Sentry payload adds only `status` — never
  add `error.message` to any Sentry `extra`. The diff-grep AC guards this.
- **Do not "fix" the hook here.** If the next reproduction's Sentry event shows
  `status:500`, the remedy is a `runtime_jwt_mint_hook`/`runtime_mint_intent`
  deploy-state check (Supabase MCP) and a separate migration-reapply issue — NOT
  a change to migrations 047-050, which are correct as shipped (#3363/PR #3983).
  This PR's job is to make that 500 *visible and recoverable*, not to alter the
  security-critical hook.
- `mapSupabaseError(message)` is kept as a back-compat shim so the existing
  copy-contract tests and the `oauth-buttons.tsx` caller don't break; the new
  `mapSupabaseAuthError(error)` is the structured entry point.
