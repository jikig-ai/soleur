---
title: Tasks — fix OTP verification code validation error
plan: knowledge-base/project/plans/2026-05-29-fix-otp-verification-code-validation-error-plan.md
branch: feat-one-shot-fix-otp-verification-code-validation-error
lane: cross-domain
status: planned
---

# Tasks — fix OTP verification "Something went wrong"

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `AuthError.code` / `.status` shape against installed SDK:
      `grep -n 'code' apps/web-platform/node_modules/@supabase/auth-js/dist/module/lib/errors.d.ts`
      (verified at plan time: `code: ErrorCode | (string & {}) | undefined`, `status?`).
- [ ] 0.2 Run open code-review overlap check on the four edited paths:
      `gh issue list --label code-review --state open --json number,title,body --limit 200`.
- [ ] 0.3 Confirm runner: `./node_modules/.bin/vitest --version` (NOT bun — bunfig blocks discovery).

## Phase 1 — Core: code-aware error mapping (RED → GREEN)

- [ ] 1.1 Write failing cases in `lib/auth/error-messages.test.ts` for each new
      branch: `over_request_rate_limit`, `{status:429}`, `otp_expired`,
      `{status:500}`, network throw; plus back-compat regression for the 4 legacy
      freetext mappings.
- [ ] 1.2 Add new copy constants + `mapSupabaseAuthError(error)` to
      `lib/auth/error-messages.ts`; map `code`/`status` first, freetext regexes as
      fallback. Keep `mapSupabaseError(message)` as a delegating shim.
- [ ] 1.3 Run `./node_modules/.bin/vitest run lib/auth/error-messages.test.ts` → green.

## Phase 2 — Wire both verifyOtp surfaces

- [ ] 2.1 `components/auth/login-form.tsx handleVerifyOtp`: wrap `verifyOtp` in
      try/catch; route resolved-error AND thrown-error through
      `mapSupabaseAuthError`; add `status` to `reportSilentFallback` extra (do NOT
      add `error.message`).
- [ ] 2.2 (optional parity) `handleSendOtp`: same `mapSupabaseAuthError` upgrade.
- [ ] 2.3 `app/(auth)/signup/page.tsx` verifyOtp block (lines 74-92): identical
      try/catch + `mapSupabaseAuthError` + `status` change.
- [ ] 2.4 `components/auth/oauth-buttons.tsx:94`: upgrade to
      `mapSupabaseAuthError(error)` only if the OAuth error carries code/status;
      else leave on the shim.

## Phase 3 — Component test + verification

- [ ] 3.1 Create `test/components/login-form-verify-error.test.tsx` mirroring
      `login-form-revoked-banner.test.tsx` mocks; `verifyOtp` rejects with
      `{code:"over_request_rate_limit",status:429}`; assert recoverable copy in
      `role="alert"`, assert `Something went wrong` absent.
- [ ] 3.2 `./node_modules/.bin/vitest run lib/auth/error-messages.test.ts test/components/login-form-verify-error.test.tsx` → green.
- [ ] 3.3 `npx tsc --noEmit` clean.
- [ ] 3.4 Diff-grep PII guard: no `message:` key added to any Sentry `extra`.
- [ ] 3.5 Grep both verifyOtp files import `mapSupabaseAuthError`.

## Phase 4 — Post-merge (operator, automatable)

- [ ] 4.1 Supabase MCP probe: confirm `public.runtime_mint_intent` table + grants
      present and `runtime_jwt_mint_hook` is the registered Custom Access Token
      Hook (rules in/out Hypothesis 2(a) deploy drift). If absent, file a separate
      migration-reapply issue — NOT this PR's scope.
