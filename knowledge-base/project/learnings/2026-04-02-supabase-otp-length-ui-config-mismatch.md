---
title: "Supabase OTP code length must be explicitly set and matched in UI"
date: 2026-04-02
category: integration-issues
module: web-platform/auth
tags: [supabase, otp, auth, configuration-drift]
---

# Learning: Supabase OTP code length must be explicitly set and matched in UI

## Problem

Users received 8-digit OTP codes from Supabase but could only enter 6 digits in the login/signup UI. The input's `maxLength` was hardcoded to 6, and the submit button only enabled when exactly 6 digits were entered. The remaining 2 digits were silently truncated, making it impossible to authenticate.

A secondary issue: `mailer_otp_exp` was set to 3600 seconds (1 hour) but the email template told users "valid for 10 minutes," creating a confusing mismatch.

## Root Cause

When the auth flow was switched from magic links to OTP codes (PR #1362), the UI was written assuming 6-digit codes. The Supabase project's `mailer_otp_length` was never set explicitly, so it defaulted to 8. The value 6 was hardcoded in 6 places across 2 files (`app/login/page.tsx` and `app/signup/page.tsx`) with no shared constant, making the assumption invisible during review.

## Solution

Two-pronged fix:

1. **Server-side:** Set `mailer_otp_length: 6` and `mailer_otp_exp: 600` in Supabase production config via Management API, and in `configure-auth.sh` for reproducibility.
2. **Client-side:** Extracted `EMAIL_OTP_LENGTH = 6` constant to `lib/auth/constants.ts` and replaced all 6 hardcoded references in login/signup pages.

E2E tests added in `otp-login.e2e.ts` (7 tests) covering maxLength enforcement, submit button disabled state, instructional text accuracy, and over-length code truncation.

## Key Insight

When switching auth flows (magic link to OTP), configuration at the service level (Supabase dashboard defaults) and the UI level can diverge silently. Neither side validates against the other. A shared constant is necessary but not sufficient -- the Supabase project config must also be set explicitly rather than relying on defaults, and E2E tests should verify UI constraints match the expected code length.

## Prevention

- Always set Supabase auth configuration values explicitly in `configure-auth.sh` rather than relying on defaults. Defaults can change between Supabase versions.
- Extract magic numbers into named constants at a shared location (`lib/auth/constants.ts`) so reviewers can verify the value matches the server config.
- When switching auth mechanisms, audit both the service provider configuration and every UI touchpoint for assumptions from the previous flow.
- E2E tests should verify that the OTP input accepts exactly the expected number of digits and that the submit button state tracks the constant, not a hardcoded value.

## References

- Related learning: knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md
- Supabase Discussion #40187
- PR #1397
