---
title: Tasks — Fix RuntimeAuthError error-level Sentry noise on scope-grants RSC prefetch
plan: knowledge-base/project/plans/2026-06-08-fix-scope-grants-runtimeautherror-rsc-prefetch-noise-plan.md
branch: feat-one-shot-runtime-auth-error-scope-grants
lane: cross-domain
date: 2026-06-08
---

# Tasks

Runner: vitest (`./node_modules/.bin/vitest run`). NEVER `bun test` (bunfig blocks discovery).
Typecheck: `npm run -w apps/web-platform typecheck` (= `tsc --noEmit`).

## Phase 1 — RED (write failing tests first)

- [ ] 1.1 Edit `apps/web-platform/test/resolve-bash-autonomous.test.ts`: extend the `@/server/observability` `vi.mock` block to also mock `warnSilentFallback: vi.fn()`.
- [ ] 1.2 Enrich the `@/lib/supabase/tenant` mock's `RuntimeAuthError` to accept + store a `cause` constructor arg (mirror `lib/supabase/tenant.ts:86-98`), and add a `mapRuntimeAuthCauseToErrorCode` export to the mock (faithful to the real switch at `:120-135`).
- [ ] 1.3 Update the existing `"FAIL-CLOSED: RuntimeAuthError → false AND mirrors"` test (currently throws `RuntimeAuthError("jwt_mint", …)`) to assert `warnSilentFallback` is called and `reportSilentFallback` is NOT.
- [ ] 1.4 Add test: `RuntimeAuthError("denied_jti", …)` → returns `false`, asserts `reportSilentFallback` called (error), `warnSilentFallback` NOT called.
- [ ] 1.5 Add test: `RuntimeAuthError("rotation", …)` → returns `false`, asserts `reportSilentFallback` called (error).
- [ ] 1.6 Add assertion across the new tests that the mirrored `extra` object includes `code` equal to `mapRuntimeAuthCauseToErrorCode(cause)`.
- [ ] 1.7 Run `./node_modules/.bin/vitest run test/resolve-bash-autonomous.test.ts` — confirm RED.

## Phase 2 — GREEN (implement the per-cause severity split)

- [ ] 2.1 Edit `apps/web-platform/server/resolve-bash-autonomous.ts`: import `warnSilentFallback` alongside `reportSilentFallback`, and `mapRuntimeAuthCauseToErrorCode` from `@/lib/supabase/tenant`.
- [ ] 2.2 In the `catch (err)` block (after the `instanceof RuntimeAuthError` guard at ~line 51): compute `const code = mapRuntimeAuthCauseToErrorCode(err.cause)` and `const emit = err.cause === "jwt_mint" ? warnSilentFallback : reportSilentFallback`; call `emit(err, { feature: "resolve-bash-autonomous", op: "tenant-read", extra: { userId, workspaceId: workspaceId ?? null, code }, message: "founder JWT mint transiently unavailable; fail-closed false (approval gate ON)" })`.
- [ ] 2.3 Keep the fail-closed `return false` for all causes unchanged. Keep the `if (!(err instanceof RuntimeAuthError)) throw err;` re-throw unchanged.
- [ ] 2.4 Run `./node_modules/.bin/vitest run test/resolve-bash-autonomous.test.ts` — confirm GREEN.

## Phase 3 — Verify

- [ ] 3.1 `npm run -w apps/web-platform typecheck` — clean (`tsc --noEmit`).
- [ ] 3.2 `grep -n "reportSilentFallback\|warnSilentFallback" apps/web-platform/server/resolve-bash-autonomous.ts` — confirm both present, split landed.
- [ ] 3.3 Confirm all 6 ACs (AC1-AC6 pre-merge) are satisfied.

## Post-merge (operator / automated)

- [ ] 4.1 AC7: after deploy, on the next natural `jwt_mint` occurrence, confirm via Sentry API/UI that the event lands at `level: warning` (no longer error-budget) while `denied_jti`/`rotation` remain `error`. Automation: Sentry API read-only; post-deploy (no synthetic prod trigger).
