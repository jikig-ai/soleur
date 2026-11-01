# Tasks — fix-next-16-4-1-e2e-dev-server-crash

Plan: `knowledge-base/project/plans/2026-11-01-fix-next-16-4-1-e2e-dev-server-crash-plan.md`
Issue: #11772 (closes). Deferral tracker: #11783 (upstream-fix adoption watch).

## Phase 1: Reproduce and attribute

- [ ] 1.1 In the worktree, temporarily install `next@16.4.3` in `apps/web-platform` (scratch install — the committed bump lands in Phase 3).
- [ ] 1.2 Start the dev server: `PORT=3100 NEXT_DIST_DIR=.next/repro npm run dev` from `apps/web-platform`; wait for `/login` readiness.
- [ ] 1.3 Run the socket-level abort repro (upstream #49587 shape): POST with a `Content-Length` body to a proxy-handled path (prefer a middleware-redirected route and a `NextResponse.next()` route to map the trigger surface), `socket.destroy()` ~500 ms mid-response.
- [ ] 1.4 Confirm the signature: `⨯ uncaughtException: Error: aborted` (`code: ECONNRESET`) + `e2e-webserver: exited rc=` + process death. Record which route class fires it (AC6 evidence).
- [ ] 1.5 If the observed signature differs from `aborted`+`ECONNRESET`, widen the classifier predicate ONLY to the observed superset (never a blanket ECONNRESET exemption) and record the deviation in `decision-challenges.md`.

## Phase 2: Crash-handler classifier (RED → GREEN)

- [ ] 2.1 RED: add arms to `apps/web-platform/test/crash-handlers.test.ts` — benign signature via `uncaughtException` → `process.exit` NOT called, `Sentry.close` NOT called, warn mirror emitted; same via `unhandledRejection`; `Error("aborted")` without `code` → exits; `ECONNRESET` with message `"socket hang up"` → exits; non-Error reason → exits. Mock `@/server/observability` alongside the existing `@sentry/nextjs` + `@/server/logger` mocks, or assert the Sentry-warn shape directly.
- [ ] 2.2 GREEN: in `apps/web-platform/server/crash-handlers.ts` add `isBenignClientAbort(err)` (`Error` + `message === "aborted"` + `code === "ECONNRESET"`) and classify-and-return in both `process.on` handlers: on match call `warnSilentFallback(err, { feature: "crash-handlers", op: "client-abort" })` and return; else `reportFatalAndExit` unchanged.
- [ ] 2.3 Re-run the Phase-1 repro against the patched bundle — server mirrors the abort at warn level and stays up.

## Phase 3: Re-apply the bump

- [ ] 3.1 `apps/web-platform/package.json`: `"next": "~16.3.8"` → `"~16.4.1"`.
- [ ] 3.2 `cd apps/web-platform && npx --yes npm@11 install --package-lock-only` (npm@11 — the version CI pins).
- [ ] 3.3 `cd apps/web-platform && npm ci --ignore-scripts` then `node -p "require('./node_modules/next/package.json').version"` → assert ≥16.4.1; `npm ls next` for stragglers. Root `package-lock.json` needs no change (no `next` entry — verified at plan time).

## Phase 4: Guard rows + test arms

- [ ] 4.1 `scripts/assert-dependabot-drain.py`: add `"next"` to `WATCHED_PACKAGES`; add `("web-platform", "next", 16, "16.4.1")` to REQUIRED beside the 2026-10-31 batch comment (update that comment's "lands in its own PR" line); add `("next", 16): "16.4.1"` to `FLOOR_ANCHORS` citing GHSA-2464-fhr4-w9xw + GHSA-673q-mjm6-r5xr (CRITICAL) + GHSA-p3m5-59mp-jv5r (HIGH); `MIN_ROWS` 35→36; `MIN_RESOLVED` 35→36.
- [ ] 4.2 `scripts/assert-dependabot-drain.test.sh`: add `"next:16:16.4.1"` to the FLOOR_ANCHORS spec-grep loop; `MIN_ASSERTIONS` 33→34.
- [ ] 4.3 Run `bash scripts/assert-dependabot-drain.test.sh` (34 assertions) and `python3 scripts/assert-dependabot-drain.py` live (36 resolved rows on the bumped lockfile).

## Phase 5: Egress pin + ADR + close-out

- [ ] 5.1 `apps/web-platform/test/egress-audit-ingest.test.ts`: pin `/^16\.3\./` → `/^16\.4\./`; run `npx vitest run test/egress-audit-ingest.test.ts`.
- [ ] 5.2 Amend `knowledge-base/engineering/architecture/decisions/ADR-062-container-memory-cap-and-restart-attribution.md`: `## Decision` Deliverable C records the benign-inbound-abort carve-out (warn mirror, no exit); `## Alternatives Considered` records the rejected upstream-patch, middleware-restructure, and respawn options with one-line reasons.
- [ ] 5.3 Record deferral tracker issue number (#11783) in the PR-body reminder; `Closes #11772` per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] 5.4 Non-goal (documented in-place, plan "Out of scope" row): the `team_names` mock-supabase route for the pre-existing `/api/team-names` 500 noise stays deferred to a separate PR — CTO-ruled 2026-11-01; do NOT treat the 500s as a crash precursor or a regression signal on this branch.

## Phase 6: Verification

- [ ] 6.1 `cd apps/web-platform && npx vitest run test/crash-handlers.test.ts test/egress-audit-ingest.test.ts` — all green.
- [ ] 6.2 `bash scripts/assert-dependabot-drain.test.sh` + `python3 scripts/assert-dependabot-drain.py` — green.
- [ ] 6.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] 6.4 If session bounds allow: bounded `npx playwright test` (authenticated project) to observe no `e2e-webserver: exited` and no `⨯ uncaughtException` death; otherwise CI e2e is the oracle (diff is `applicable=true` per the #8450 classifier).
- [ ] 6.5 AC walk: every plan AC1–AC9 checked against the final tree; AC9 confirmed by `gh pr checks` e2e green.
