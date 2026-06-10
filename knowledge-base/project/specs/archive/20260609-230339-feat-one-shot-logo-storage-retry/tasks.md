---
feature: feat-one-shot-logo-storage-retry
plan: knowledge-base/project/plans/2026-06-09-fix-logo-storage-upload-transient-retry-plan.md
lane: cross-domain
status: pending
---

# Tasks — workspace-logo upload transient retry

> Derived from the finalized (post-review) plan. Spec lacked a valid `lane:` — defaulted
> to `cross-domain` (fail-closed). TDD ordering is normative: RED before GREEN per phase.

## Phase 1 — Retry leaf module (helper before consumer: contract-first)

- [x] 1.1 RED: create `apps/web-platform/test/server/storage-retry.test.ts`
  - [x] 1.1.1 Classification truth table (U1-U5): 5xx/429 retryable; 4xx not; `StorageUnknownError` (no status) retryable; plain `{message}` not; `null` not
  - [x] 1.1.2 Loop semantics (U5-U7): injected no-op `sleep`; persistent 503 → 3 op calls, sleep args `[500, 1000]`; transient-then-success → `onRetry(1, error)` once; success-first → sleep never called
  - [x] 1.1.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/storage-retry.test.ts` — confirm RED (module missing)
- [x] 1.2 GREEN: create `apps/web-platform/server/storage-retry.ts`
  - [x] 1.2.1 `StorageErrorLike` structural type (no storage-js import — dependency-free leaf per `server/github-retry.ts` precedent)
  - [x] 1.2.2 `isRetryableStorageError`: `name === "StorageUnknownError"` → true; numeric `status >= 500 || status === 429` → true; else false
  - [x] 1.2.3 `withStorageRetry<R extends { error: StorageErrorLike | null }>`: result-returning loop, `DEFAULT_MAX_RETRIES = 2`, `DEFAULT_BASE_DELAY_MS = 500`, plain exponential `base * 2 ** attempt`, injectable `sleep`/`onRetry`
  - [x] 1.2.4 Unit suite green

## Phase 2 — Route wiring

- [x] 2.1 RED: extend `apps/web-platform/test/workspace-logo-route.test.ts`
  - [x] 2.1.1 Add `mockWarn` override for `warnSilentFallback` in the existing observability `vi.mock` (importActual + override pattern)
  - [x] 2.1.2 Partial-mock `@/server/storage-retry`: forward to actual `withStorageRetry` with `sleep: async () => {}` (zero-delay; do NOT use fake timers)
  - [x] 2.1.3 R1: 503-once-then-success → 200, exactly 2 upload attempts, one `storage-upload-retry` warn (`extra.attempt === 1`), no `storage-upload` error report
  - [x] 2.1.4 R2: persistent 503 → 500, exactly 3 attempts, `reportSilentFallback` once with op `storage-upload`
  - [x] 2.1.5 R3: `{status: 400}` → 500, exactly 1 attempt
  - [x] 2.1.6 R4: `{name: "StorageUnknownError"}` once then success → 200, 2 attempts
  - [x] 2.1.7 Confirm RED (route not yet wired — R1/R4 fail on attempt counts)
- [x] 2.2 GREEN: edit `apps/web-platform/app/api/workspace/logo/route.ts`
  - [x] 2.2.1 Import `withStorageRetry` (`@/server/storage-retry`) + `warnSilentFallback` (`@/server/observability`)
  - [x] 2.2.2 Wrap the line-130 `.upload()` in `withStorageRetry` with a re-invoking closure (NOT a captured promise); `onRetry` emits `warnSilentFallback` op `storage-upload-retry`, extra `{userId, workspaceId, attempt}`
  - [x] 2.2.3 Terminal-failure block byte-identical (op `storage-upload`, same extra, same 500 body)
  - [x] 2.2.4 Full route suite green (all pre-existing tests unchanged)

## Phase 3 — Verification (Acceptance Criteria)

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/storage-retry.test.ts test/workspace-logo-route.test.ts` → exit 0
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0
- [x] 3.3 Scope guard: `grep -c "withStorageRetry(" apps/web-platform/app/api/workspace/logo/route.ts` → `1`
- [x] 3.4 Slug guard: `grep -c 'op: "storage-upload",' apps/web-platform/app/api/workspace/logo/route.ts` → `1` (trailing-comma anchor — bare grep substring-matches the retry slug)
- [x] 3.5 No new deps: `git diff origin/main -- apps/web-platform/package.json` → empty
- [ ] 3.6 PR body: describe fix + `Ref` the plan; PR #5084 already exists (update title/body, do not create)
