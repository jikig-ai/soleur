# Tasks: fix OAuth callback access_denied Sentry alert noise

## Phase 1: Split provider-error emission in callback route

- [ ] 1.1 In `apps/web-platform/app/(auth)/callback/route.ts`, replace the single `warnSilentFallback` call on the `providerErrorBucket` branch with a conditional: `logger.info` for `oauth_cancelled` bucket, `warnSilentFallback` for all other buckets.
- [ ] 1.2 Verify the `logger.info` call includes all structured context fields (`feature`, `op`, `providerErrorCode`, `bucket`, `urlPath`, `refererHost`, `origin`).
- [ ] 1.3 Verify the `warnSilentFallback` call for non-`oauth_cancelled` buckets preserves the existing signature and all extra fields.

## Phase 2: Update test file

- [ ] 2.1 Add `mockLoggerInfo` to `vi.hoisted` block and wire into the logger mock in `callback-route-branches.test.ts`.
- [ ] 2.2 Split the `test.each` block: extract `access_denied` into its own test asserting `mockWarnSilentFallback.not.toHaveBeenCalled()` and `mockLoggerInfo` called with correct context.
- [ ] 2.3 Keep `server_error`, `temporarily_unavailable`, `invalid_scope` in a `test.each` asserting `mockWarnSilentFallback` IS called.
- [ ] 2.4 Update "refererHost" test (uses `?error=access_denied`) to assert `mockLoggerInfo` context instead of `mockWarnSilentFallback`.
- [ ] 2.5 Verify "searchParamKeys" test (bare `/callback` path) remains unchanged with `mockReportSilentFallback`.
- [ ] 2.6 Verify "unrecognized `?error=`" test asserts `mockWarnSilentFallback` (unknown errors are `oauth_failed` bucket).

## Phase 3: Verify

- [ ] 3.1 Run vitest suite: `apps/web-platform/node_modules/.bin/vitest run apps/web-platform/test/app/auth/callback-route-branches.test.ts apps/web-platform/test/lib/auth/callback-error-mapping.test.ts apps/web-platform/test/lib/auth/callback-route-no-substring-match.test.ts apps/web-platform/test/lib/auth/provider-error-classifier.test.ts apps/web-platform/test/lib/auth/provider-error-classifier-no-substring-match.test.ts`.
- [ ] 3.2 Run TypeScript compile check: `npx tsc --noEmit --project apps/web-platform/tsconfig.json`.
- [ ] 3.3 Run AC1-AC5 verification grep commands.
