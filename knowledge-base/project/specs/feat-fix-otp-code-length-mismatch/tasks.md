# Tasks: fix OTP code length mismatch

## Phase 1: Fix Supabase Configuration

- [ ] 1.1 Update `apps/web-platform/supabase/scripts/configure-auth.sh` to include `mailer_otp_length: 6` and `mailer_otp_exp: 600` in the PATCH payload
- [ ] 1.2 Run `configure-auth.sh` against production to set `mailer_otp_length: 6` and `mailer_otp_exp: 600`
- [ ] 1.3 Verify via Supabase Management API that `mailer_otp_length` is now 6 and `mailer_otp_exp` is 600

## Phase 2: Extract Constant and Fix UI

- [ ] 2.1 Create `apps/web-platform/lib/auth/constants.ts` with `EMAIL_OTP_LENGTH = 6`
- [ ] 2.2 Update `apps/web-platform/app/(auth)/login/page.tsx` to import and use `EMAIL_OTP_LENGTH` for maxLength, disabled check, placeholder, and instructional text
- [ ] 2.3 Update `apps/web-platform/app/(auth)/signup/page.tsx` to import and use `EMAIL_OTP_LENGTH` for maxLength, disabled check, placeholder, and instructional text
- [ ] 2.4 Verify no hardcoded OTP length `6` remains in login or signup pages (grep check)

## Phase 3: Fix Email Template Expiry Text

- [ ] 3.1 Update `apps/web-platform/supabase/templates/magic-link.html` to match `mailer_otp_exp` (keep "10 minutes" since we are setting expiry to 600s)
- [ ] 3.2 Add cross-reference comment in `configure-auth.sh` pointing to `EMAIL_OTP_LENGTH` constant

## Phase 4: E2E Test Improvements

- [ ] 4.1 Write unit test `apps/web-platform/test/otp-constants.test.ts` verifying `EMAIL_OTP_LENGTH` is between 6 and 10
- [ ] 4.2 Add E2E test: OTP input accepts exactly `EMAIL_OTP_LENGTH` digits on login page
- [ ] 4.3 Add E2E test: OTP input rejects non-numeric characters
- [ ] 4.4 Add E2E test: submit button disabled until OTP is complete
- [ ] 4.5 Add E2E test: instructional text shows correct digit count
- [ ] 4.6 Add E2E test: OTP input maxLength attribute matches `EMAIL_OTP_LENGTH`

## Phase 5: Verification

- [ ] 5.1 Run unit tests locally
- [ ] 5.2 Run E2E tests locally
- [ ] 5.3 Verify Supabase production config via API query
