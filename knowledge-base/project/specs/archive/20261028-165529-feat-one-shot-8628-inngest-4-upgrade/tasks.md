# Tasks — feat-one-shot-8628-inngest-4-upgrade

Derived from `knowledge-base/project/plans/2026-10-28-chore-inngest-v4-upgrade-stream-detach-plan.md`.

## 1. Dependency floor

- [x] 1.1 `apps/web-platform/package.json`: `"inngest": "3.54.2"` → `"inngest": "^4.x"` (latest stable at work time; `npm view inngest version`)
- [x] 1.2 Regenerate `apps/web-platform/package-lock.json`: `cd apps/web-platform && npx --yes npm@11 install --package-lock-only` (no `bun install` — `lint-dual-lockfile` asserts no bun.lock exists)

## 2. Mechanical v4 API migration

- [x] 2.1 `createFunction` codemod: fold trigger arg into `triggers:` in options across `server/inngest/functions/*.ts` (71 files) + any test-harness call sites; function `id:` values unchanged
- [x] 2.2 `app/api/inngest/route.ts`: `serveHost` → `serveOrigin`; `streaming: "force"` → `streaming: true`; remove `signingKey` from `serve()`; update comment blocks for v4
- [x] 2.3 `server/inngest/client.ts`: add `signingKey` to `new Inngest()`; switch `middleware:` array to class registrations; preserve `NEXT_PHASE` build bypass + `INNGEST_DEV=1`-in-prod refusal
- [x] 2.4 `tsc --noEmit` green before continuing

## 3. Middleware rewrite (v4 `Middleware.BaseMiddleware`)

- [x] 3.1 `middleware/sentry-correlation.ts` → class; scope tags + run-start breadcrumb in `transformFunctionInput`; step breadcrumbs `onStepComplete`/`onStepError`; final-error capture `onRunError` (`isFinalAttempt`); final-ok `onRunComplete`
- [x] 3.2 `middleware/run-log.ts` → class; `transformFunctionInput` captures `startedAtMs`; terminal-row write in `onRunComplete`/`onRunError` preserving #5674 thrown-vs-returned-`ok:false` semantics + `finishRoutineRunProgress` ordering + fail-soft Sentry mirror
- [x] 3.3 `middleware/bound-logger.ts` → class; `transformFunctionInput` returns `{...arg, ctx:{...arg.ctx, logger}}`; WeakMap bound-cache, frozen-prop invariant, once-per-process fail-open report preserved
- [x] 3.4 Port the three middleware test suites to the class hook shape; same contracts green

## 4. Delete the stream-detach workaround

- [x] 4.1 Delete `server/inngest/stream-detach.ts` + `test/server/inngest/stream-detach.test.ts`
- [x] 4.2 `route.ts`: remove wrapper import + `streamRequestInfo`; `export const POST = handlers.POST`
- [x] 4.3 `test/server/inngest/signature-verify.test.ts`: drop stream-detach mock + wrapper-wiring test; keep 401-envelope assertions + serve-mount census (updated comment); check `signature-verify-dev-mode.test.ts` + `client-startup.test.ts` for v4 error-text drift
- [x] 4.4 `git grep -n "stream-detach\|detachFromConsumerCancel\|streamRequestInfo" -- apps/ scripts/ plugins/` → zero

## 5. Evidence — streaming spike re-run (S1–S8 + S9)

- [x] 5.1 Stand up spike: `inngest start` v1.45.1, branch build (`next build` + minimal server w/ `installCrashHandlers()`), Cloudflare quick tunnel, throwaway keys, `env -i` + `INNGEST_DEV=0`
- [x] 5.2 Run S1–S6, S8 rows (same shapes/pass conditions as 2026-09-23 record) — all pass; S3 full 70-min completion on re-fire
- [x] 5.3 Run S7 no-wrapper stream cut — kill-proof: PASS — zero `Controller is already closed`/`Invalid state` occurrences; app stayed up on a 3-stream cut; retries re-ran
- [x] 5.4 Run S9 checkpointing matrix — both arms recorded; shipped `checkpointing: false` arm passes, default-on arm unexpectedly COMPLETED a 3-min step on v1.45.1
- [x] 5.5 Unsigned-POST row (201 + 401 envelope) + `PUT` registration row (`modified:true`, 74 fns / 55 cron triggers planned)
- [x] 5.6 Write `knowledge-base/project/specs/feat-one-shot-8628-inngest-4-upgrade/streaming-spike-v4.md` — per-row verdicts recorded

## 6. Residuals

- [x] 6.1 Delete `scripts/followthroughs/inngest-verify-clean-10390.{sh,test.sh}`; remove `run_suite` line (`test-all.sh:5989`), `suite-durations.tsv:388`, `suite-shard-legs.tsv:391`, `fixture-relative-assert.baseline.txt` row; `git grep inngest-verify-clean-10390 -- scripts/ .github/ plugins/ apps/ infra/` → zero
- [x] 6.2 `_cron-community-publication.ts` P3(a): procfs-absent probe path — designed seam + loud-failure assertion
- [x] 6.3 P3(b): non-Linux fallback test coverage via deliberate seam (`@internal test seam` precedent)
- [x] 6.4 P3(c): `fh.close()` masks only when `writeFile` already threw; lone close error surfaces
- [x] 6.5 P3(d): error-prefix family naming decision encoded + pinned by tests

## 7. ADR + gates + close

- [x] 7.1 Amend ADR-243 (§1 v4 fix + deletion, alternatives row executed, observability table retires `inngest-stream-*` ops, S9 verdict); grep `inngest-stream-`/`serveHost`/`3.54.2` → only KB/history
- [x] 7.2 `tsc`, `eslint` green; `scripts/test-all.sh --affected` ran to the 4h ceiling — UNRESOLVED (365 pass/7 fail/317 declined); 4 diff-caused failures fixed + verified, rest environmental (shallow clone / host state / load flakes); coverage gap for CI
- [ ] 7.3 PR body: `Closes #8628` + names both attached residuals
