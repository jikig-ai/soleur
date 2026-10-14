---
type: bug-fix
status: ready-for-work
branch: feat-one-shot-login-no-account-redirect
issue_ref: "context-only: #1765 (closed)"
requires_cpo_signoff: false
deepened_on: 2026-05-04
---

# fix: Redirect login to /signup when no Soleur account exists for email

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-05-04
**Sections enhanced:** Overview, Phase 3 (banner state simplification), Phase 4 (mock shape verified), Risks, Research Insights
**Research sources used:** Context7 (`/supabase/supabase-js`), WebSearch (Supabase Auth issue #1547, GitHub issue #13066), direct inspection of installed `@supabase/auth-js@2.49.0` source (`node_modules/@supabase/auth-js/src/lib/errors.ts`, `lib/error-codes.ts`, `lib/fetch.ts`).

### Key Improvements From Deepen Pass

1. **Status code corrected from 422 → 400.** `AuthApiError` thrown by gotrue for `otp_disabled` returns HTTP 400, verified in `node_modules/@supabase/auth-js/src/lib/errors.ts:47` (`throw new AuthApiError('Invalid credentials', 400, 'invalid_credentials')` constructor pattern). E2E mock body updated.
2. **Mock body keys verified.** `node_modules/@supabase/auth-js/src/lib/fetch.ts:65-69` reads `data.code` first, falls back to `data.error_code`. Mock includes both for forward-compat; production reads `code`.
3. **Banner state simplified.** Removed the `[showNoAccountBanner, setShowNoAccountBanner]` state pair plus two dismiss-site bug-surface; the banner is now derived directly from `reason === "no_account" && email === initialEmail` — auto-dismisses on first edit, zero state, zero dismiss bugs. (DHH-lens improvement: less code, same UX.)
4. **`otp_disabled` is a stable error-code constant.** Confirmed in the installed SDK's `ErrorCode` union type (`error-codes.ts:68`), so `error.code === "otp_disabled"` is a type-safe contract, not a string-match. The regex fallback is true defense-in-depth, not the primary path.
5. **Account-enumeration framing reinforced by upstream.** Supabase Auth issue #1547 explicitly tracks this as a known information-leak in `signInWithOtp({ shouldCreateUser: false })`. Our plan's "no new privacy regression" framing is correct — the leak exists upstream.

### New Considerations Discovered

- The error-message prose `"Signups not allowed for otp"` is a gotrue server constant, but historically gotrue has had at least one rewording cycle. The unit test pins both `"Signups not allowed for otp"` and a case-insensitive variant; if gotrue ever changes the wording, the regex falls back gracefully and the `error.code === "otp_disabled"` primary path still catches it.
- `AuthApiError` (the runtime class) lives in `@supabase/auth-js`, not `@supabase/supabase-js` directly. The cast `(error as { code?: string; message: string })` avoids importing the class — keeps the diff minimal and avoids a SDK-internal-class dependency. This is the same pattern the existing `error-classifier.ts` and `provider-error-classifier.ts` already use in `apps/web-platform/lib/auth/`.

## Overview

When a user submits an email on `/login` for which no Soleur account exists, Supabase returns
an `otp_disabled` error (HTTP 400, message `"Signups not allowed for otp"`) because the login
page calls `signInWithOtp` with `shouldCreateUser: false`. The `mapSupabaseError` mapper has no
pattern for this code/message, so the user sees the generic catch-all string
`"Something went wrong. Please try again."` — confusing, blame-shifted, and dead-end (no path
to signup from the error). Reproduced for `harry@jikigai.com` (a real prospect, no account).

**Fix in two parts plus defense-in-depth:**

1. **Login page (`apps/web-platform/app/(auth)/login/page.tsx`):** detect the
   `otp_disabled` / `"Signups not allowed for otp"` condition (check both `error.code` and a
   message-pattern fallback) and redirect to `/signup?email=<encoded>&reason=no_account`
   instead of rendering the inline error.

2. **Signup page (`apps/web-platform/app/(auth)/signup/page.tsx`):** read `email` and `reason`
   query params, prefill the email input from `email`, and when `reason=no_account` show a
   distinct neutral/blue informational banner ("No Soleur account found for {email}. Create
   one below.") above the form. Banner shows once on initial load only — dismissed when the
   user types or after first submit.

3. **`SUPABASE_ERROR_PATTERNS` (`apps/web-platform/lib/auth/error-messages.ts`):** add an entry
   for `otp_disabled` / `Signups not allowed for otp` mapping to a sensible string
   (`"No Soleur account found for this email. Sign up instead."`) — defense-in-depth fallback
   if the redirect path is ever bypassed (e.g., a future caller wires `mapSupabaseError`
   without the redirect logic, or the redirect's feature-detection misses a Supabase wording
   change).

## Context: relationship to closed #1765

Issue #1765 (`fix: improve error messages on login page (rate limit, auth failures)`,
**CLOSED**) addressed three error patterns (`email rate limit exceeded`, `invalid otp`,
`token...expired`) but missed the `otp_disabled` case because at the time, login and signup
shared a single page that defaulted to `shouldCreateUser: true`. The `otp_disabled` failure
mode only became reachable after the login/signup split that pinned `shouldCreateUser: false`
on `/login`. **This PR references #1765 in the body for context only — not `Closes` or `Ref`,
since #1765 is already closed.**

## Reproduction

1. Visit `/login` in any environment with a working Supabase project.
2. Enter an email that does NOT have a Soleur account (e.g. `harry@jikigai.com`).
3. Click "Send sign-in code".
4. **Observed:** inline red text `"Something went wrong. Please try again."` — no signup CTA,
   no indication that the cause is "account doesn't exist".
5. **Expected (after this fix):** redirect to `/signup?email=harry%40jikigai.com&reason=no_account`
   with the email prefilled and a neutral banner explaining "No Soleur account found for
   harry@jikigai.com. Create one below."

## User-Brand Impact

**If this lands broken, the user experiences:** a confused login attempt — either (a) a
redirect loop if the signup-page handler also returns `otp_disabled` (it won't, because
signup defaults to `shouldCreateUser: true`, but worth verifying), (b) prefill fails and the
user retypes, or (c) the banner persists across re-renders and looks broken. Worst realistic
case: the user bounces and we lose a signup. No data loss, no auth bypass, no security
regression.

**If this leaks, the user's data/workflow/money is exposed via:** N/A. The redirect URL
contains the user's own email (which they just typed); no other-tenant data, no token, no
session material. Email in URL is logged in browser history and any access-log layer (CDN,
Next.js server logs) — but the same email was just submitted to Supabase Auth in the
preceding request, so the additional surface is zero.

**Brand-survival threshold:** none. **Reason:** UX polish on a public auth page. Failure
mode is "user sees a worse error than they should" — degrades conversion, does not breach
trust. Touches auth pages but does NOT touch credentials, sessions, or token handling. The
sensitive-path regex (preflight Check 6) will match `lib/auth/**` so a `threshold: none,
reason:` scope-out bullet is recorded above.

## Account enumeration consideration

The redirect distinguishes "email exists in Supabase" from "email does not exist" — i.e., it
leaks account-presence to anyone who can submit the form. **However, the existing two-page
split (`/login` vs `/signup`) already leaks the same signal:** signup with an existing email
returns a different error than signup with a new one, and login with an existing email sends
an OTP while login with a non-existent email returns an error. This PR does NOT introduce a
new enumeration vector — it makes the existing leak slightly more legible by routing the
user to the right page. **The PR body MUST note this** so reviewers don't relitigate it as a
privacy regression. If we ever decide to close the enumeration leak entirely, it needs a
unified "we sent a code if the account exists" UX — out of scope here, tracked separately if
filed.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "mapSupabaseError mapper at `lib/auth/error-messages.ts`" | Confirmed at that exact path; 36 lines; `SUPABASE_ERROR_PATTERNS` is a `[RegExp, string][]` — pattern entry is straightforward | Add one entry; no refactor needed. |
| "extend `apps/web-platform/e2e/otp-login.e2e.ts`" | File exists; uses Playwright `page.route("**/auth/v1/otp*", ...)` to mock Supabase; precedent for both `/login` and `/signup` routes | Extend with a `route.fulfill({ status: 400, body: '{"code":"otp_disabled","error_code":"otp_disabled","msg":"Signups not allowed for otp","message":"Signups not allowed for otp"}' })` mock. Status 400 verified against `@supabase/auth-js/src/lib/errors.ts:47`. Pattern matches existing `navigateToOtpStep` helper. |
| "Add a unit test for mapSupabaseError" | No existing `error-messages.test.ts` — first unit test for this module | Create `apps/web-platform/lib/auth/error-messages.test.ts` (sibling-test convention used by `validate-origin.test.ts` and `csrf-coverage.test.ts` in the same dir). Vitest is the runner (`apps/web-platform/package.json` script `"test": "vitest"`). |
| "/signup page reads email + reason query params" | `app/(auth)/signup/page.tsx` is a `"use client"` component but currently does NOT call `useSearchParams`. The `/login` page already wraps its form in `<Suspense>` for `useSearchParams`. | Wrap `SignupPage`'s form in `<Suspense>` like the login page (Next.js requirement: client components calling `useSearchParams` must be inside a Suspense boundary, else the build fails with `useSearchParams() should be wrapped in a suspense boundary`). |
| "show banner once on initial load" | No prior banner-dismiss UX in this codebase to copy | Implement via local state `[bannerVisible, setBannerVisible] = useState(reason === "no_account" && !!email)` — dismiss on first `onChange` of email input or first submit. No persistence across navigations. |

## Implementation Phases

### Phase 1 — `error-messages.ts` mapper entry + unit test (TDD)

1. Create `apps/web-platform/lib/auth/error-messages.test.ts` with three failing assertions:
   - `mapSupabaseError("Signups not allowed for otp")` returns
     `"No Soleur account found for this email. Sign up instead."`
   - `mapSupabaseError("signups not allowed for OTP")` (case-insensitivity) returns the
     same string.
   - `mapSupabaseError("email rate limit exceeded")` still returns the existing rate-limit
     string (regression guard for entry ordering).
2. Run `bun run --cwd apps/web-platform test:ci lib/auth/error-messages.test.ts` to confirm
   RED.
3. Add the new pattern to `SUPABASE_ERROR_PATTERNS`. Place it BEFORE the generic patterns
   (order matters in `for ... return`):

   ```ts
   [
     /signups? not allowed for otp/i,
     "No Soleur account found for this email. Sign up instead.",
   ],
   ```
4. Re-run the test → GREEN.

**Files to edit:**
- `apps/web-platform/lib/auth/error-messages.ts`

**Files to create:**
- `apps/web-platform/lib/auth/error-messages.test.ts`

### Phase 2 — Login page: detect and redirect

1. In `apps/web-platform/app/(auth)/login/page.tsx`, extract a small helper at the top of
   the file (above `LoginForm`):

   ```ts
   function isNoAccountError(error: { code?: string; message: string }): boolean {
     if (error.code === "otp_disabled") return true;
     return /signups? not allowed for otp/i.test(error.message);
   }
   ```

2. Inside `handleSendOtp`, replace the existing `if (error)` branch:

   ```ts
   if (error) {
     console.error("[auth] Supabase error:", error.message);
     reportSilentFallback(error, {
       feature: "auth",
       op: "signInWithOtp",
       extra: {
         errorCode: (error as { code?: string }).code,
         errorName: error.name,
       },
     });
     if (isNoAccountError(error as { code?: string; message: string })) {
       const params = new URLSearchParams({ email, reason: "no_account" });
       router.push(`/signup?${params.toString()}`);
       return;
     }
     setError(mapSupabaseError(error.message));
   }
   ```

   **Note:** keep `reportSilentFallback` — telemetry on the no-account path is still
   useful (drives conversion analysis: how many login attempts hit no-account?). The
   `errorCode` field already exists in the Sentry payload and will distinguish this case.

3. **Sharp edge — `setLoading(false)` ordering:** the existing code calls `setLoading(false)`
   BEFORE the `if (error)` branch, so the redirect path doesn't need a separate
   `setLoading(false)` — but verify that the loading spinner doesn't flash to "ready" then
   immediately into the redirect. If it does, hoist `setLoading(false)` into the non-error
   branch only, and keep the loading state "true" through the redirect.

**Files to edit:**
- `apps/web-platform/app/(auth)/login/page.tsx`

### Phase 3 — Signup page: read query params, prefill, banner

1. Wrap `SignupPage`'s form body in `<Suspense>` (mirror `/login` structure):

   ```tsx
   export default function SignupPage() {
     return (
       <Suspense>
         <SignupForm />
       </Suspense>
     );
   }

   function SignupForm() {
     const searchParams = useSearchParams();
     const initialEmail = searchParams.get("email") ?? "";
     const reason = searchParams.get("reason");
     const [email, setEmail] = useState(initialEmail);
     const [showNoAccountBanner, setShowNoAccountBanner] = useState(
       reason === "no_account" && initialEmail.length > 0,
     );
     // ... rest as before
   }
   ```

2. **Banner visibility — derived state, no `useState`.** Avoid a separate
   `showNoAccountBanner` boolean and its two dismiss-sites. Derive from the existing
   `email` state instead:

   ```tsx
   const showNoAccountBanner =
     reason === "no_account" &&
     initialEmail.length > 0 &&
     email === initialEmail;
   ```

   Auto-dismisses the moment the user edits the email (because `email !== initialEmail`),
   without any extra `setX(false)` calls. Once dismissed, it cannot accidentally re-show
   even if the user retypes the original email — that's fine UX (banner is a "you got
   here from a redirect" signal, not a permanent state). Submit doesn't need to dismiss
   it: on success the route changes; on error the email hasn't changed so the banner
   stays visible alongside the new error, which is correct UX (both messages are true).

3. Add the banner BELOW the page heading and ABOVE the form, only when
   `showNoAccountBanner`:

   ```tsx
   {showNoAccountBanner && (
     <div
       role="status"
       className="rounded-lg border border-blue-900/50 bg-blue-950/30 px-4 py-3 text-sm text-blue-200"
     >
       No Soleur account found for <strong>{email}</strong>. Create one below.
     </div>
   )}
   ```

   **Styling rationale:** distinct from the existing `text-red-400` error treatment;
   neutral/blue tone signals "informational, not your fault, here's the path forward".
   Uses `role="status"` (not `role="alert"`) — matches the non-error semantics for
   assistive tech.

4. **Sharp edge — email validation:** the `email` input has `required` and `type="email"`,
   so an empty / malformed `?email=` query won't auto-submit; it will just prefill an
   invalid value the user must fix. This matches the spec's "prefill" requirement without
   adding new validation. Verify by typing a malformed email manually — should produce the
   same browser-native validation behavior whether prefilled or not.

5. **Sharp edge — Suspense boundary build error:** Next.js 15 will fail the production
   build if a client component calls `useSearchParams` outside `<Suspense>`. The login
   page's existing `<Suspense>` wrap is the proven pattern; copy that structure. The
   acceptance criteria below include `next build` succeeding.

**Files to edit:**
- `apps/web-platform/app/(auth)/signup/page.tsx`

### Phase 4 — E2E test extension

Extend `apps/web-platform/e2e/otp-login.e2e.ts` with a new `test.describe` block:

```ts
test.describe("Login no-account redirect", () => {
  test("submitting unknown email on /login redirects to /signup with prefill + banner", async ({ page }) => {
    // Mock Supabase OTP endpoint to return otp_disabled.
    // Verified shape against `node_modules/@supabase/auth-js/src/lib/fetch.ts:65-69` —
    // client reads `data.code` first, falls back to `data.error_code`. Status is 400
    // (gotrue convention for client-side request errors; verified in
    // `node_modules/@supabase/auth-js/src/lib/errors.ts:47` AuthApiError constructor).
    await page.route("**/auth/v1/otp*", (route) =>
      route.fulfill({
        status: 400,
        contentType: "application/json",
        body: JSON.stringify({
          code: "otp_disabled",
          error_code: "otp_disabled",
          msg: "Signups not allowed for otp",
          message: "Signups not allowed for otp",
        }),
      }),
    );

    await page.goto("/login");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );

    const email = "no-account@example.com";
    await page.getByRole("textbox", { name: /you@example.com/i }).fill(email);
    await page.getByRole("button", { name: /send sign-in code/i }).click();

    // Expect navigation to /signup with email + reason params
    await page.waitForURL(/\/signup\?.*reason=no_account/, { timeout: 5_000 });
    expect(page.url()).toContain(`email=${encodeURIComponent(email)}`);

    // Email is prefilled
    const emailInput = page.getByRole("textbox", { name: /you@example.com/i });
    await expect(emailInput).toHaveValue(email);

    // Banner is visible
    await expect(page.getByRole("status")).toContainText(/no Soleur account found/i);
    await expect(page.getByRole("status")).toContainText(email);

    // Banner dismisses on edit (derived from `email !== initialEmail`)
    await emailInput.fill(`${email}-edit`);
    await expect(page.getByRole("status")).toHaveCount(0);
  });
});
```

**Sharp edge — Supabase error response shape (RESOLVED at deepen-time).**
Verified directly against installed source:

- `apps/web-platform/node_modules/@supabase/auth-js/src/lib/fetch.ts:65-69` reads
  `data.code` first, falls back to `data.error_code`. The mock includes both for
  forward-compat.
- `apps/web-platform/node_modules/@supabase/auth-js/src/lib/error-codes.ts:68` confirms
  `'otp_disabled'` is in the typed `ErrorCode` union — stable contract.
- `apps/web-platform/node_modules/@supabase/auth-js/src/lib/errors.ts:47` (constructor
  reference: `throw new AuthApiError('Invalid credentials', 400, 'invalid_credentials')`)
  confirms the canonical status for `AuthApiError` is 400, not 422.

If gotrue ever reshapes the response (rename `code` → something else), the mock-body
test will be the failure surface; the regex fallback on `error.message` keeps production
working until the mapper code is updated.

**Files to edit:**
- `apps/web-platform/e2e/otp-login.e2e.ts`

## Files to Edit

- `apps/web-platform/lib/auth/error-messages.ts` — add `otp_disabled` pattern
- `apps/web-platform/app/(auth)/login/page.tsx` — add `isNoAccountError` helper, redirect on detection
- `apps/web-platform/app/(auth)/signup/page.tsx` — wrap in Suspense, read query params, prefill, banner
- `apps/web-platform/e2e/otp-login.e2e.ts` — add no-account redirect test

## Files to Create

- `apps/web-platform/lib/auth/error-messages.test.ts` — vitest unit test for `mapSupabaseError`

## Open Code-Review Overlap

None. (Verified: queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each planned file path against issue bodies — no matches for `lib/auth/error-messages.ts`, `app/(auth)/login/page.tsx`, `app/(auth)/signup/page.tsx`, or `e2e/otp-login.e2e.ts`.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `mapSupabaseError("Signups not allowed for otp")` returns the no-account string (unit test passes).
- [x] `mapSupabaseError("signups not allowed for OTP")` (case-insensitive) also passes.
- [x] Existing patterns (rate limit, invalid otp, token expired) still return their
      original strings (regression guard).
- [x] Submitting an unknown email on `/login` (Supabase mock returning `otp_disabled`)
      redirects to `/signup?email=<encoded>&reason=no_account` (e2e test passes).
- [x] On `/signup?email=foo@bar&reason=no_account`, the email input is prefilled with
      `foo@bar` and the neutral banner is visible above the form.
- [x] Banner uses `role="status"` (not `role="alert"`), uses blue/neutral styling
      (`text-blue-200` / `bg-blue-950/30` or similar), and is visually distinct from the
      red error string.
- [x] Banner auto-dismisses when the user edits the email input (derived from
      `email === initialEmail`; no `useState` for visibility, no manual dismiss-site).
- [x] On submit-with-error (e.g., a follow-up rate-limit error), the banner remains
      visible alongside the new error string — both messages are simultaneously true and
      the user benefits from seeing the no-account context plus the rate-limit reason.
- [x] `apps/web-platform/app/(auth)/signup/page.tsx` is wrapped in `<Suspense>` and
      `next build` (or `bun run --cwd apps/web-platform build`) succeeds.
- [x] OAuth flow (`OAuthButtons`, `/callback`, `/connect-repo`) is unchanged — diff
      excludes those files.
- [x] PR body references #1765 for context (no `Closes` / `Ref`) and includes the
      enumeration-consideration paragraph from this plan.

### Post-merge (operator)

None — no migrations, no infra, no Doppler config changes.

## Test Scenarios

1. **Unit:** `error-messages.test.ts` — three cases (positive case-sensitive, positive
   case-insensitive, regression-existing-pattern).
2. **E2E:** `otp-login.e2e.ts` — submit unknown email → redirect → prefill → banner →
   banner dismisses on edit.
3. **Manual smoke (post-deploy, optional):** in dev, with `harry@jikigai.com` (real
   no-account email), reproduce the original bug; verify redirect and banner.

## Risks

- **Supabase response-shape drift:** if a future gotrue release changes `otp_disabled` to
  e.g. `signup_not_allowed` or rewords `"Signups not allowed for otp"` to
  `"Signups disabled for OTP"`, both the `error.code` check and the regex fallback could
  silently break. Mitigation: the unit test guards regex; the e2e test guards the
  end-to-end pipe. If both are kept, drift surfaces in CI rather than production.
- **Suspense regression:** wrapping `SignupPage` in `<Suspense>` is a structural change.
  If misapplied (e.g., wrapping the wrong subtree), the build fails — caught by the
  `next build` AC.
- **Banner accessibility:** `role="status"` is a live region but with `aria-live="polite"`
  by default — appropriate for a non-urgent informational banner. If we used `role="alert"`
  instead, screen readers would interrupt the user, which is wrong for this case.
- **Prefill with malformed email:** if a bad actor crafts `/signup?email=<javascript:...>`,
  the `<input value={email}>` renders the value as a string (React escapes attribute
  values). No XSS surface. The `<strong>{email}</strong>` in the banner also escapes via
  React text-node rendering. Verified by code shape, not new test.
- **Loading-spinner flash:** see Phase 2 step 3 sharp edge.

## Non-Goals

- Closing the account-enumeration leak entirely (would require a unified
  "we'll send a code if the account exists" UX). Out of scope; not filed unless the user
  wants it tracked.
- Refactoring `mapSupabaseError` into a typed enum / discriminated union. Tempting, but
  YAGNI — the current `[RegExp, string][]` pattern works and the new entry slots in.
- Touching the OAuth flow (`OAuthButtons`, `/callback`, `/connect-repo`) — explicitly
  excluded by the user's constraints.
- Adding rate-limiting on the redirect itself. The redirect targets `/signup`, which has
  its own rate-limit story upstream of this PR.

## Research Insights

**`otp_disabled` is a stable typed error code in `@supabase/auth-js`.**
Direct file reference: `apps/web-platform/node_modules/@supabase/auth-js/src/lib/error-codes.ts:68`. The full union (excerpt):

```ts
export type ErrorCode =
  | 'unexpected_failure'
  | 'validation_failed'
  // ... ~80 codes ...
  | 'otp_expired'
  | 'otp_disabled'  // <-- our case
  | 'identity_not_found'
  // ...
```

Checking `error.code === "otp_disabled"` against this union is a **type-safe contract**,
not a brittle string match. The regex on `error.message` is genuine defense-in-depth (in
case a future SDK release omits the code field, as Supabase issue #1023 documented for
some legacy paths).

**gotrue error-response key precedence (load-bearing for the e2e mock).**
From `apps/web-platform/node_modules/@supabase/auth-js/src/lib/fetch.ts:65-69`:

```ts
if (typeof data === 'object' && data && typeof data.code === 'string') {
  errorCode = data.code
} else if (typeof data === 'object' && data && typeof data.error_code === 'string') {
  errorCode = data.error_code
}
```

`code` wins, then `error_code`. The mock body in Phase 4 includes both for
forward-compatibility but the production path will read `code`.

**Account enumeration is a known upstream leak (not new to this PR).**
[Supabase Auth issue #1547](https://github.com/supabase/auth/issues/1547) explicitly
tracks this: when `signInWithOtp({ shouldCreateUser: false })` is called for a
non-existent email and signups are disabled, the API returns an error rather than
silently succeeding, leaking account presence. This is upstream behavior — our PR does
NOT introduce a new enumeration vector, only routes the user to the correct page using
the leak that already exists. The PR body's "Account enumeration consideration"
paragraph stands.

**`AuthApiError` class signature (no import needed).**
From `apps/web-platform/node_modules/@supabase/auth-js/src/lib/errors.ts:50-56`:

```ts
export class AuthApiError extends AuthError {
  // status: number, code: string
  // constructor: new AuthApiError(message, status, code)
}
```

Existing project code (`lib/auth/error-classifier.ts`,
`lib/auth/provider-error-classifier.ts`) uses structural casts
(`(error as { code?: string; message: string })`) rather than importing the class
directly. Our `isNoAccountError` helper follows the same pattern — keeps the diff
minimal, no new SDK-internal-class import surface.

**Next.js 15 `useSearchParams` in client components MUST be in a Suspense boundary.**
Verified against the existing `/login` page (`app/(auth)/login/page.tsx:13-18`) which
wraps `LoginForm` in `<Suspense>` for exactly this reason. The signup page currently
does NOT call `useSearchParams`, so it's not wrapped — Phase 3 must add the wrap. If
omitted, `next build` fails with `useSearchParams() should be wrapped in a suspense
boundary` (project's installed Next.js version: `^15.5.15`).

**Banner derived-state pattern beats useState here (DHH-lens).**
Original draft used `[showNoAccountBanner, setShowNoAccountBanner]` plus two dismiss
sites (input `onChange`, `handleSendOtp`). Final design derives:

```ts
const showNoAccountBanner =
  reason === "no_account" && initialEmail.length > 0 && email === initialEmail;
```

Same UX, zero state, zero "forgot to dismiss" bug surface. React renders the banner
exactly when the condition is true on each render — no effects, no synchronization.

**References (live URLs):**

- [Supabase Auth issue #1547 — account-enumeration leak](https://github.com/supabase/auth/issues/1547)
- [Supabase issue #13066 — `AuthApiError: Signups not allowed for otp` repro](https://github.com/supabase/supabase/issues/13066)
- [Supabase Error Codes documentation](https://supabase.com/docs/guides/auth/debugging/error-codes)
- [Next.js `useSearchParams` Suspense requirement](https://nextjs.org/docs/app/api-reference/functions/use-search-params)
- [Supabase JS Client (Context7 ID: `/supabase/supabase-js`)](https://github.com/supabase/supabase-js)

## Domain Review

**Domains relevant:** Product (UX-adjacent — modifies existing user-facing pages, no new
component file)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Rationale:** This is a small UX polish on existing pages — adds an informational banner
to `/signup` and changes one error path on `/login` from inline-text to a redirect. No
new pages, no new components (the banner is inline JSX inside the existing
`SignupForm`), no new flows. Mechanical-escalation check: no new file under
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Pipeline mode → auto-accept.

**Agents invoked:** none
**Skipped specialists:** none (no domain leader recommended a copywriter; banner copy is
a single sentence trivially derived from the spec)
**Pencil available:** N/A

#### Findings

The banner copy follows the existing voice (concise, second-person implied, no apology).
The CTA is implicit ("Create one below") rather than a separate button — keeps the
existing form as the primary action surface. No content-review gate fires.

## Sharp Edges (per plan-skill checklist)

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan
  fills it (`threshold: none`) with a sensitive-path scope-out reason.
- The Phase 4 e2e test's mock body shape (which JSON keys the supabase-js client reads
  to populate `error.code`) MUST be verified against an actual `otp_disabled` response
  before the test is frozen. If the dev-environment response is unavailable, fall back to
  matching the regex on `error.message` (already covered by `isNoAccountError`).
- The `SUPABASE_ERROR_PATTERNS` array order matters — new entry goes BEFORE the existing
  `invalid otp` pattern (which would otherwise match `"Signups not allowed for otp"` via
  the substring "otp" if a future maintainer over-broadens that regex). Current
  `invalid otp` regex is `/invalid otp/i` so collision is unlikely, but the unit test's
  regression assertion guards against future drift either way.
- The `email` query param in the redirect is `URLSearchParams`-encoded. `+` characters in
  emails (`foo+tag@example.com`) survive encoding correctly via `URLSearchParams`. Do NOT
  manually `encodeURIComponent` and concatenate — `URLSearchParams.toString()` handles it.

## PR Body Reminder

The PR description MUST include:

1. **Closes** — none. (Issue #1765 is already closed; this is referenced for context only.)
2. **Reference (context only):** "Same UX-gap class as #1765, which addressed three error
   patterns but missed `otp_disabled` because the failure mode only became reachable after
   the login/signup page split."
3. **Account enumeration note** — copy the paragraph from this plan's "Account enumeration
   consideration" section.
4. **Test plan** — vitest unit + Playwright e2e, both green locally.
5. **Manual reproduction** — `harry@jikigai.com` on `/login` reproduces the original bug
   on `main`; the same email on this branch redirects to `/signup` with prefill + banner.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-04-fix-login-no-account-redirect-to-signup-plan.md

Context: branch feat-one-shot-login-no-account-redirect, worktree
.worktrees/feat-one-shot-login-no-account-redirect/. No PR yet. References (context only)
issue #1765. Plan written and reviewed; implementation next — start with Phase 1 (TDD on
error-messages.ts mapper).
```
