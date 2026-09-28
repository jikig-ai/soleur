---
title: "Tasks — perf(dashboard): residual cold tiers"
branch: feat-one-shot-8978-residual-cold-tiers
plan: knowledge-base/project/plans/2026-09-27-perf-dashboard-residual-cold-tiers-plan.md
issue: 8978
closes: [8926, 8993, 8940]
date: 2026-09-27
---

# Tasks — perf(dashboard): residual cold tiers

Source of truth: `knowledge-base/project/plans/2026-09-27-perf-dashboard-residual-cold-tiers-plan.md`. Phase order is dependency order: measure before mechanism choice on the document tier; contract-preserving bounds before the sweep.

## Phase 0 — Name the post-middleware tier (measurement)

- [x] 0.1 Re-run the committed probe: `doppler run -c prd -- bun run scripts/live-verify/perf-probe.ts` (5 cold + 1 warm; `LIVE_VERIFY_BROWSER_PATH=/usr/bin/chromium` until the operator Chrome install lands). Record the table.
- [x] 0.2 Pull the probe-armed Sentry transactions via the `scripts/sentry-issue.sh` Discover read path (`SENTRY_ISSUE_RO_TOKEN`, `event.type:transaction`): read `http.client` spans to `*.supabase.co` per document request — connect vs server wall-time, request-receipt→dispatch gap, middleware vs render share.
- [x] 0.3 Conditional in-surface probe — only if 0.2 leaves the tier blind: per-request timing log in `apps/web-platform/server/index.ts` around `handle()` and/or `performance.now()` spans inside `resolveIdentity` emitted via pino (`op: "render-identity"`, fields `headerHit`/`selectDurMs`/`totalMs`). Skip with a recorded reason if spans already discriminate.
- [x] 0.4 Produce the committed measurement table (tier × sample) — lands in the PR body via ship and a comment on #8978.
- [x] 0.5 Smoke: confirm `AbortSignal.timeout` exists in the Next middleware runtime (add a one-line probe or exercise the bound in a vitest); if absent, use the manual `AbortController + setTimeout` form (`cf-cache-purge.ts` precedent) for every bound.

## Phase 1 — Bound Supabase-facing legs (#8978)

- [x] 1.1 `apps/web-platform/middleware.ts`: `.abortSignal(AbortSignal.timeout(MW_RPC_TIMEOUT_MS))` on the `check_my_revocation` RPC → existing `grace` arm; timeout-distinct `op` tag on `reportEdgeSilentFallback` (e.g. `revocation_rpc_timeout`).
- [x] 1.2 Revocation in-flight dedup: `Map<cacheKey, Promise<RevocationOutcome>>` beside `revocationOkCache`; join concurrent misses on the same `${sub}:${iat}`; delete on settle; positive-only cache rules unchanged.
- [x] 1.3 Same bound on the T&C `users` select → existing `tcError` arm (`/accept-terms?error=db_unavailable`).
- [x] 1.4 mw-auth arm: bind `getUser()` (~10 s) only if Phase-0 data shows recurring multi-second `mw-auth` stalls; otherwise record reviewed-and-unbounded with the number.
- [x] 1.5 `apps/web-platform/lib/feature-flags/identity.ts`: bound the `users`/`workspace_members` pair → existing degrade arm (`prd`/null fields; `userId`/`email` unaffected via the minted-header fast path).
- [x] 1.6 Conditional upstream warm-up (only if Phase 0 names cold connection/compute): `setInterval` in `server/index.ts` issuing a pinned cheap anon-key request to the Supabase edge every ~15–20 s with its own `AbortSignal.timeout`; failure-tolerant, tick logged. Otherwise record the rejection + numbers.
- [x] 1.7 Tests: never-resolving-builder fixtures per bound arm; concurrency fixture for dedup (6 misses → 1 RPC); census assertion over `supabase\.` call sites on the auth path (Guard 1 row 4); degrade-arm fixture for resolveIdentity.
- [x] 1.8 ADR-253 amendment (bounded waits + dedup + warm-up disposition) — same PR.

## Phase 2 — Verify (#8978 DoD)

- [ ] 2.1 Post-deploy probe re-run; measurement table to #8978 + PR body (ship authors the body).
- [ ] 2.2 Warm FCP vs ≲500 ms — attach measured floor arithmetic if unreachable; record the gap as a decision challenge, do not silently re-scope.
- [ ] 2.3 Cold path: stated, verified p50/p95 bound (≥5 samples).
- [ ] 2.4 Re-evaluation comment on #8985 citing the fresh fetch-count-vs-document-tier numbers (issue stays open).

## Phase 3 — #8926 sweep

- [x] 3.1 Regenerate the census: `grep -rln 'auth\.getUser' apps/web-platform/app/api --include='route.ts'` at implementation time.
- [x] 3.2 Migrate pure id-read sites to `verifiedUserId(req)` (`Promise<string | null>`; 401 on null — keep each route's existing failure contract).
- [x] 3.3 Rich-field sites (today: `repo/setup`, `checkout`, `workspace/accept-invite`, `workspace/invite-member`, `workspace/decline-invite`): use `sessionJwtEmailForVerifiedUser` where the email claim suffices; else keep `getUser()` with a one-line documented reason.
- [x] 3.4 Commit the documented-exceptions list; add the remaining-sites census assertion (Guard-adjacent ratchet — every file still calling `auth.getUser()` must be on the list).
- [x] 3.5 Update the touched routes' tests; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green.

## Phase 4 — test-all machinery (#8993, #8940)

- [x] 4.1 #8993: parent-death watchdog on the non-enumerate run path of `scripts/test-all.sh` — mirror the `_enum_wd` pattern (kill -0 + zombie `stat=` + `lstart` identity pin + `pgrep -P` in-flight child sweep before TERM); arm after flag-parse before `tc_acquire`; disarm from the existing EXIT trap list; `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` documented opt-out.
- [x] 4.2 #8940: per-suite `tee` capture to `$SOLEUR_SCRATCH_SESSION_ROOT/logs/<label>.log`; suite rc read via `${PIPESTATUS[0]}` (never `$?`); on non-ok status copy last ~200 lines to `${XDG_STATE_HOME:-$HOME/.local/state}/soleur/logs/test-all-<pid>-<label>.log` and print the path on the summary line; EXIT-trap arm covers the killed-mid-suite case.
- [x] 4.3 Fixtures (`scripts/test-all-orphan-watchdog.test.sh`, `scripts/test-all-failure-log.test.sh` or folded into `test-contention.test.sh`): orphan-fire, live-parent must-PASS, opt-out arm, durable-path-printed-and-resolves, killed-mid-suite tail preserved, all-ok writes nothing.

## Exit checklist

- [ ] All plan ACs ticked (Pre-merge + post-merge probes run post-deploy).
- [ ] markdownlint clean on plan + this file.
- [ ] `lint-guard-contract.py` passes the plan's Guard Contract.
