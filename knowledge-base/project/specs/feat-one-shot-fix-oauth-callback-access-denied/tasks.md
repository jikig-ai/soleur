# Tasks: fix OAuth callback access_denied Sentry alert noise

## Phase 1: Split provider-error emission in callback route

- [x] 1.1 In `apps/web-platform/app/(auth)/callback/route.ts` line 85, replace the single `warnSilentFallback` call with a conditional on `providerErrorBucket === "oauth_cancelled"`.
- [x] 1.2 For `oauth_cancelled` bucket: emit `logger.info` with all 7 structured context fields (`feature`, `op`, `providerErrorCode`, `bucket`, `urlPath`, `refererHost`, `origin`) and the message string `OAuth provider returned error=${providerErrorCode}`.
- [x] 1.3 For non-`oauth_cancelled` buckets: keep `warnSilentFallback(null, { feature: "auth", op: "callback_provider_error", ... })` with all existing `extra` fields.
- [x] 1.4 Add inline comment explaining why user-cancel is logger.info-only (Sentry alert rules count all captureMessage events regardless of level).

## Phase 2: Update test file

- [x] 2.1 Add `mockLoggerInfo: vi.fn()` to the `vi.hoisted` block in `callback-route-branches.test.ts` (alongside existing `mockReportSilentFallback`, `mockWarnSilentFallback`).
- [x] 2.2 Wire `mockLoggerInfo` into the logger mock: replace `info: vi.fn()` at line 27 with `info: mockLoggerInfo`.
- [x] 2.3 Extract `access_denied` from the `test.each` block into its own test: assert `mockWarnSilentFallback.not.toHaveBeenCalled()`, `mockReportSilentFallback.not.toHaveBeenCalled()`, `mockLoggerInfo` called once with `op: "callback_provider_error"` + `providerErrorCode: "access_denied"` + `bucket: "oauth_cancelled"`.
- [x] 2.4 Keep `server_error`, `temporarily_unavailable`, `invalid_scope` in a `test.each` asserting `mockWarnSilentFallback` IS called and `mockLoggerInfo.not.toHaveBeenCalled()`.
- [x] 2.5 Update "refererHost" test (uses `?error=access_denied`) to assert `mockLoggerInfo` context contains `refererHost: "accounts.google.com"` instead of `mockWarnSilentFallback`.
- [x] 2.6 Verify "searchParamKeys" test (bare `/callback` path) remains unchanged with `mockReportSilentFallback`.
- [x] 2.7 Verify "unrecognized `?error=`" test asserts `mockWarnSilentFallback` (unknown errors are `oauth_failed` bucket, not user-cancel).

## Phase 3: Verify

- [x] 3.1 Run vitest suite: `apps/web-platform/node_modules/.bin/vitest run apps/web-platform/test/app/auth/callback-route-branches.test.ts apps/web-platform/test/lib/auth/callback-error-mapping.test.ts apps/web-platform/test/lib/auth/callback-route-no-substring-match.test.ts apps/web-platform/test/lib/auth/provider-error-classifier.test.ts apps/web-platform/test/lib/auth/provider-error-classifier-no-substring-match.test.ts`.
- [x] 3.2 Run TypeScript compile check: `npx tsc --noEmit --project apps/web-platform/tsconfig.json`.
- [x] 3.3 Run AC1: `grep -n "logger.info" apps/web-platform/app/\(auth\)/callback/route.ts` shows logger.info on the oauth_cancelled branch.
- [x] 3.4 Run AC2: `grep -n "warnSilentFallback" apps/web-platform/app/\(auth\)/callback/route.ts` shows warnSilentFallback for non-cancelled provider errors.
- [x] 3.5 Run AC3-AC5: verify test assertions in callback-route-branches.test.ts.
