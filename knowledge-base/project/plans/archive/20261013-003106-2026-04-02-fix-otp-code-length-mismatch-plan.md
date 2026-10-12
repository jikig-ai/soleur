---
title: "fix: OTP code length mismatch between Supabase config and UI input"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# fix: OTP code length mismatch between Supabase config and UI input

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 4 (Supabase config, UI constant, E2E tests, security)
**Research sources:** Supabase Management API docs (Context7), Playwright OTP testing patterns (web search), 5 institutional learnings, Supabase community discussion #40187, database trigger testing approach

### Key Improvements

1. Added concrete `configure-auth.sh` payload showing exact JSON fields to set
2. Added database trigger approach for deterministic E2E OTP testing (eliminates need for email interception)
3. Added `autoComplete="one-time-code"` verification to E2E tests (WebOTP API compatibility)
4. Added Supabase Management API response verification pattern for CI smoke tests

## Overview

The login and signup pages display a 6-digit OTP input field (`maxLength={6}`, placeholder `000000`, submit gate `otp.length !== 6`), but the Supabase project is configured to send 8-digit OTP codes (`mailer_otp_length: 8`). Users cannot paste or type the full 8-digit code, and even if they could, the submit button remains disabled because the length check expects exactly 6. Verification always fails.

## Problem Statement / Motivation

This is a production auth blocker. Any user attempting email OTP sign-in or sign-up receives an 8-digit code via email but encounters a 6-digit input field that truncates the code and refuses to submit. The mismatch was introduced when the auth flow was switched from magic links to OTP codes (documented in learning `2026-03-30-pkce-magic-link-same-browser-context.md`) -- the UI was written assuming 6-digit codes, but the Supabase project's `mailer_otp_length` was never updated from its default of 8.

### Root Cause

The Supabase Management API confirms the current production configuration:

- `mailer_otp_length: 8` (email OTP sends 8 digits)
- `sms_otp_length: 6` (SMS OTP sends 6 digits)
- `mfa_phone_otp_length: 6` (MFA phone OTP sends 6 digits)

The UI in both `app/(auth)/login/page.tsx` and `app/(auth)/signup/page.tsx` hardcodes 6 in three places each:

1. `maxLength={6}` on the input element (truncates pasted codes)
2. `otp.length !== 6` on the submit button disabled check (blocks submission)
3. `"We sent a 6-digit code"` in the instructional text (misleads users)

The `configure-auth.sh` script does not set `mailer_otp_length` at all, so the Supabase project default (8) persists.

The email template (`supabase/templates/magic-link.html`) says "This code expires in 10 minutes" but `mailer_otp_exp` is set to 3600 seconds (1 hour) -- a secondary inconsistency.

## Proposed Solution

Two-pronged fix: align the Supabase config to send 6-digit codes (simpler UX, industry standard), AND extract the OTP length into a shared constant so UI and config cannot diverge.

### Phase 1: Fix the Supabase configuration (immediate)

Update `configure-auth.sh` to explicitly set `mailer_otp_length: 6` in the PATCH payload. Run the script against production to fix the live config immediately.

**File:** `apps/web-platform/supabase/scripts/configure-auth.sh`

Add `"mailer_otp_length": 6` and `"mailer_otp_exp": 600` to the JSON payload in the curl PATCH request (line ~36-52).

#### Research Insights

**Exact PATCH payload fields** (confirmed via Supabase Management API docs and Context7):

```json
{
  "mailer_otp_length": 6,
  "mailer_otp_exp": 600
}
```

These fields are accepted alongside the existing SMTP and template fields in the same PATCH request -- no separate API call needed.

**Institutional learning** (`2026-03-18-supabase-resend-email-configuration.md`): The `smtp_port` field must be a string, not an integer. While `mailer_otp_length` and `mailer_otp_exp` are numeric, verify the API accepts them as integers in the `jq` payload (use `--argjson` not `--arg` for numeric values).

### Phase 2: Extract OTP length constant and fix UI

Create a shared constant so the OTP length is defined once and consumed by both pages.

**File (new):** `apps/web-platform/lib/auth/constants.ts`

```typescript
/** Length of the email OTP code. Must match Supabase mailer_otp_length. */
export const EMAIL_OTP_LENGTH = 6;
```

**Files (modify):**

- `apps/web-platform/app/(auth)/login/page.tsx` -- replace all three hardcoded `6` references with `EMAIL_OTP_LENGTH`
- `apps/web-platform/app/(auth)/signup/page.tsx` -- replace all three hardcoded `6` references with `EMAIL_OTP_LENGTH`

The instructional text should derive from the constant:

- Text: `` `We sent a ${EMAIL_OTP_LENGTH}-digit code to` `` instead of `"We sent a 6-digit code to"`
- Placeholder: keep hardcoded `"000000"` with a comment referencing `EMAIL_OTP_LENGTH` -- the placeholder is a visual hint, not a functional contract

### Phase 3: Fix secondary inconsistency in email template

Update `apps/web-platform/supabase/templates/magic-link.html` to match the actual `mailer_otp_exp` value. Either:

- Change the template text from "10 minutes" to "60 minutes" (matches current config), OR
- Change `mailer_otp_exp` from 3600 to 600 (10 minutes) in `configure-auth.sh` (recommended -- shorter OTP expiry is more secure)

Recommended: set `mailer_otp_exp: 600` in the configure script and keep the "10 minutes" text.

### Phase 4: E2E test improvements

The current E2E tests in `e2e/otp-login.e2e.ts` only verify:

1. Form rendering (email input, send code button present)
2. Instructional text content
3. Callback error handling

They do NOT test:

- OTP input field accepts the correct number of digits
- OTP input field rejects more digits than expected
- Submit button enables only at the correct digit count
- The instructional text matches the expected digit count
- The OTP verification flow end-to-end (mocked or real)

**File (modify):** `apps/web-platform/e2e/otp-login.e2e.ts`

Add tests for:

- `test("OTP input truncates pasted 8-digit code to EMAIL_OTP_LENGTH digits")` -- paste an 8-digit string, verify only 6 characters accepted (primary regression test -- directly reproduces this bug)
- `test("OTP input accepts exactly EMAIL_OTP_LENGTH digits")` -- fill input, verify value length
- `test("submit button is disabled until OTP is complete")` -- type partial code, check disabled; complete code, check enabled
- `test("instructional text shows correct digit count")` -- verify text contains the expected digit count
- `test("OTP input maxLength matches EMAIL_OTP_LENGTH")` -- verify the input's maxLength attribute

**File (modify):** `apps/web-platform/supabase/scripts/configure-auth.sh`

Add a comment documenting that `mailer_otp_length` must match `EMAIL_OTP_LENGTH` in `lib/auth/constants.ts`.

**Note:** Phase 3 (expiry text fix) should be a separate commit from the OTP length fix -- it is a separate concern.

### Phase 5: Future consideration -- deterministic OTP testing via database trigger

For full end-to-end OTP verification testing (beyond the UI-level tests in Phase 4), consider a database trigger approach that makes OTP codes deterministic for test email addresses. This pattern is documented in the [Supabase OTP Playwright testing community](https://www.amillionmonkeys.co.uk/blog/2025-11-06-testing-supabase-otp-playwright-database-trigger):

1. Create a PostgreSQL trigger on `auth.users` that watches for `@example.com` emails
2. When a test email is detected, set `recovery_token` to a SHA-224 hash of the email + a known code (e.g., `"123456"`)
3. E2E tests use `test+{timestamp}@example.com` addresses and always enter `"123456"` as the OTP
4. Tests exercise real Supabase auth flows without email interception or mocking

This is a separate effort tracked for post-fix implementation. The Phase 4 tests cover the immediate regression (UI-level digit count validation). This approach would enable testing the full `signInWithOtp` -> `verifyOtp` round-trip.

## Technical Considerations

- **Why change Supabase config, not UI?** 6-digit codes are the industry standard (Google, Apple, Microsoft all use 6). Longer codes increase user friction without meaningful security benefit for email OTP (the code is already rate-limited and time-bound). Supabase docs describe email OTP as "a six digit code" despite defaulting to 8. The `mailer_otp_length` field accepts values 6-10 (validated by GoTrue, [PR #513](https://github.com/supabase/auth/pull/513)).
- **Why extract a constant?** The current bug exists because the length is hardcoded in 6+ places across 2 files. A single constant prevents future divergence.
- **Security:** 6-digit OTP with 10-minute expiry and rate limiting (`rate_limit_otp: 30` per hour) provides adequate security. The code space is 1,000,000 combinations; at 30 attempts/hour max, brute force is infeasible within the expiry window.
- **Email template already uses `{{ .Token }}`:** The template renders whatever Supabase generates. No template change needed for the digit count itself -- only the expiry text needs updating.

### Research Insights

**Supabase `verifyOtp` error handling** (institutional learning: `2026-03-20-supabase-silent-error-return-values.md`): Both login and signup pages correctly destructure `{ error }` from `verifyOtp()` and display it. No silent error gap here -- but verify the error message for a wrong-length code is user-friendly (Supabase returns "Token has expired or is invalid" which is adequate).

**`autoComplete="one-time-code"` attribute** is already present on both OTP inputs. This enables the [WebOTP API](https://developer.mozilla.org/en-US/docs/Web/API/WebOTP_API) on mobile devices -- Android Chrome can auto-fill OTP codes from SMS. While this project uses email OTP, the attribute does no harm and is best practice.

**Playwright E2E testing** (institutional learning: `2026-03-29-playwright-e2e-test-setup-for-nextjs-custom-server.md`): The existing Playwright config uses `tsx server/index.ts` with dummy Supabase env vars. The Phase 4 E2E tests do not need real Supabase connectivity -- they test UI behavior only (input field constraints, button state). The OTP verification step in the form triggers a Supabase API call that will fail against the dummy URL, which is acceptable for UI-level tests. The form `onSubmit` handler can be tested by verifying the button becomes enabled at the correct digit count, not by completing the auth flow.

**E2E test for pasting 8-digit codes**: Playwright's `page.fill()` method respects `maxLength` on input elements. To test paste truncation, use `page.evaluate` to set the value directly via the DOM, or use `page.fill()` and verify the resulting value length. Example:

```typescript
test("OTP input truncates pasted 8-digit code", async ({ page }) => {
  // Navigate to login, enter email, submit to reach OTP step
  // ... (setup steps to reach OTP input)
  const otpInput = page.getByRole("textbox");
  await otpInput.fill("12345678"); // 8 digits
  const value = await otpInput.inputValue();
  expect(value.length).toBe(6); // maxLength truncates to 6
});
```

## Acceptance Criteria

- [x] Supabase production `mailer_otp_length` is set to 6
- [x] Supabase production `mailer_otp_exp` is set to 600 (10 minutes)
- [x] `configure-auth.sh` includes `mailer_otp_length: 6` and `mailer_otp_exp: 600` in the PATCH payload
- [x] `EMAIL_OTP_LENGTH` constant exists in `apps/web-platform/lib/auth/constants.ts`
- [x] Login page uses `EMAIL_OTP_LENGTH` for maxLength, disabled check, and instructional text
- [x] Signup page uses `EMAIL_OTP_LENGTH` for maxLength, disabled check, and instructional text
- [x] No hardcoded `6` for OTP length remains in login or signup pages
- [x] E2E tests verify OTP input accepts exactly the correct number of digits
- [x] E2E tests verify submit button disabled state based on OTP length
- [x] E2E tests verify instructional text contains correct digit count
- [x] E2E test reproduces the original bug (paste 8-digit code, verify truncation to 6)
- [x] Email template expiry text matches actual `mailer_otp_exp` config

## Test Scenarios

### Acceptance Tests

- Given the OTP input is rendered on the login page, when a user types 6 numeric digits, then the input value has 6 characters and the submit button is enabled
- Given the OTP input on the login page, when a user pastes an 8-digit code, then only 6 digits are accepted (maxLength truncation) and the submit button is enabled
- Given the OTP input on the login page, when a user types 5 digits, then the submit button remains disabled
- Given the OTP input on the login page, when a user types letters or special characters, then non-numeric characters are stripped
- Given the signup page OTP step, when displayed, then the instructional text reads "We sent a 6-digit code"
- Given the login page OTP step, when displayed, then the instructional text reads "We sent a 6-digit code"

### Integration Verification (for `/soleur:qa`)

- **API verify:** `doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain | xargs -I{} curl -s "https://api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/config/auth" -H "Authorization: Bearer {}" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['mailer_otp_length']==6, f'Expected 6, got {d[\"mailer_otp_length\"]}'; assert d['mailer_otp_exp']==600, f'Expected 600, got {d[\"mailer_otp_exp\"]}'; print('PASS')"` expects `PASS`
- **Browser:** Navigate to `https://app.soleur.ai/login`, enter a valid email, submit, receive OTP email, verify the code is 6 digits, enter the code in the input, verify the submit button enables, submit

## Dependencies and Risks

- **Risk:** Running `configure-auth.sh` against production changes the live auth config. Mitigated by the fact that the script already runs against production (it configured SMTP and OAuth providers).
- **Dependency:** `SUPABASE_ACCESS_TOKEN` must be available in Doppler `prd` config (confirmed present).
- **Risk:** Users who received 8-digit codes before the fix and haven't used them yet will find those codes still work (Supabase validates the token server-side regardless of length setting at generation time). No user impact from timing.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a bug fix aligning existing configuration with existing UI.

## References and Research

### Internal References

- Learning: `knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md` -- documents the switch from magic links to OTP
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-signinwithotp-creates-users.md` -- documents `shouldCreateUser: false` on login
- Login page: `apps/web-platform/app/(auth)/login/page.tsx`
- Signup page: `apps/web-platform/app/(auth)/signup/page.tsx`
- Auth config script: `apps/web-platform/supabase/scripts/configure-auth.sh`
- Email template: `apps/web-platform/supabase/templates/magic-link.html`
- E2E tests: `apps/web-platform/e2e/otp-login.e2e.ts`

### External References

- [Supabase Discussion #40187: Magic Link OTP 8 numbers long](https://github.com/orgs/supabase/discussions/40187) -- exact same issue, solution is dashboard setting
- [Supabase Auth Email Passwordless docs](https://supabase.com/docs/guides/auth/auth-email-passwordless) -- describes OTP as "six digit code"
- [Supabase GoTrue PR #513: fix: shorten email otp length](https://github.com/supabase/auth/pull/513) -- historical PR that added configurable email OTP length
- Supabase Management API: `PATCH /v1/projects/{ref}/config/auth` with `mailer_otp_length` field
- [Supabase OTP Playwright testing via database triggers](https://www.amillionmonkeys.co.uk/blog/2025-11-06-testing-supabase-otp-playwright-database-trigger) -- deterministic OTP testing without email interception
- [2FA testing with Playwright and Mailosaur](https://filiphric.com/2fa-testing-with-playwright-and-mailosaur) -- email-based OTP testing patterns

### Institutional Learnings Applied

- `2026-03-30-pkce-magic-link-same-browser-context.md` -- documents the switch from magic links to OTP (root cause context)
- `2026-03-18-supabase-resend-email-configuration.md` -- `smtp_port` is string-typed in the API; verify numeric fields
- `2026-03-29-playwright-e2e-test-setup-for-nextjs-custom-server.md` -- Playwright config with dummy Supabase env vars
- `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` -- vitest/happy-dom setup for component tests
- `2026-03-20-supabase-silent-error-return-values.md` -- always destructure `{ error }` from Supabase calls (already done in login/signup pages)
