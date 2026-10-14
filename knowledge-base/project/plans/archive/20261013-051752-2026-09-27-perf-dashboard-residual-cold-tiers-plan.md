---
title: "perf(dashboard): residual cold tiers — bound Supabase-facing legs, warm the upstream, sweep getUser() sites, and fix test-all orphan/output-loss defects"
type: perf
date: 2026-09-27
slug: perf-dashboard-residual-cold-tiers
branch: feat-one-shot-8978-residual-cold-tiers
issue: 8978
closes: [8926, 8993, 8940]
priority: high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# perf(dashboard): residual cold tiers

## Enhancement Summary

**Deepened on:** 2026-09-27
**Sections enhanced:** Hypotheses (L3→L7 layer table — Phase 4.5 fired on `timeout`), Encryption Posture (written — plan prose names cache/log-sink classes), Sharp Edges (`TimeoutError` DOMException name; vitest fake-timer caveat), References (citation paths re-verified; one wrong path fixed)
**Research agents used:** sequential-fallback — no Task fan-out in this runtime; deepen-plan halt gates (4.5 network-outage, 4.6 user-brand, 4.7 observability, 4.8 PAT, 4.9 UI-wireframe, 4.10 encryption-posture, 4.11 guard-contract) applied inline with mechanical verifiers where they exist (`lint-guard-contract.py`, PAT regex sweep, rule-id registry check, kb-path glob check, `markdownlint-cli2`)

### Key Improvements

1. `.abortSignal(AbortSignal.timeout(…))` on a postgrest chain is **repo-precedented**, not novel: `server/cost-writer.ts` (`LEDGER_READBACK_TIMEOUT_MS`) is the precedent-diff anchor; `server/github-retry.ts` documents the abort lands as `DOMException` named `"TimeoutError"`.
2. `cf-cache-purge.ts` notes `AbortSignal.timeout` uses a runtime-internal timer vitest does not intercept — timeout-arm fixtures either use real short timers or a manual `AbortController` (that file's own precedent).
3. Live L3/L7 artifacts added (health 200 `supabase:"connected"`; unauth dashboard nav 307 in 165 ms) — the outage shape is inside-request latency, not connectivity loss.

### New Considerations Discovered

- `AbortSignal.timeout` availability in the Next middleware runtime must be confirmed by a Phase-0 smoke (it is standard web API; the manual `AbortController + setTimeout` fallback is the in-repo precedent if unavailable).
- `verifiedUserId(req)` is typed on `Request`; Next.js route handlers hold `NextRequest` (a `Request` subclass) — compatible, but the four sites pass different request object names (`_req`, `req`) — migrate per-site, not by mechanical rewrite.

## Overview

Post-deploy verification of the auth-tax + instrumentation PR (squash `9b6b0394`, PR #8984, deployed 2026-09-27) left #8978's ≲500 ms first-paint acceptance criterion unmet and produced two newly measured cold tiers: (a) an `mw-revoke` cold-miss leg of ~29.6 s on probe run cold-3, and (b) an unexplained post-middleware document tier of 23–38 s (cold-2 TTFB 38.1 s with all middleware legs served from cache in ~0.71 s). Best cold FCP 1.71 s; warm 2.08 s against a ≲500 ms AC.

This plan covers five open issues:

- **#8978** — name and remove the two residual cold tiers so the DoD lands: warm FCP ≲500 ms where reachable plus a stated, verified cold bound.
- **#8926** — migrate the remaining route-level `auth.getUser()` call sites to `verifiedUserId()` (71 files carry `auth.getUser` on `origin/main`; 5 touch fields beyond `user.id`).
- **#8993** — an orphaned `test-all.sh --affected` run held the repo-global flock for ~1.5 h after its lefthook parent died.
- **#8940** — a failing test-all battery leaves zero retained diagnostics because suite output artifacts die with the per-run scratch root.
- **#8985** — mount fan-out batching on /dashboard: dispositioned as **deferred-with-data** below (the issue's own re-evaluation criterion is unmet).

Spec lacks valid lane: — no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement

Three measured facts bound the problem:

- **mw-revoke cold-miss = ~29.6 s.** `check_my_revocation` is an indexed one-row PostgREST RPC (migration 067) — query time is sub-ms. A ~30 s leg is therefore a *transport/upstream* stall: cold TCP+TLS to the Supabase edge, undici pool cold-start, or Supabase-side compute/PostgREST warm-up. The leg has **no timeout** — `supabase.rpc(...)` runs against the default fetch with no `AbortSignal`, so an upstream stall is unbounded.
- **Post-middleware document tier = 23–38 s.** On cold-2, all `mw-*` legs resolved in ~0.71 s yet the document took 38.1 s TTFB. Between middleware and first byte sits Next.js dispatch + `(dashboard)/layout.tsx` → `resolveIdentity`, which still issues two remote PostgREST selects (`users`, `workspace_members ⋈ workspaces`) on every document render — the same cold-upstream surface as the revocation leg. No `Server-Timing` leg names this window today; Sentry transactions are armed on `x-perf-probe` (shipped in #8984) but the span evidence has not yet been pulled and read.
- **test-all machinery** (observed during PR #8984): `tc_acquire`'s advisory flock is inherited by suite children (`exec {fd}>>`, no CLOEXEC), so an orphaned runner holds it until the run ends; the only parent-death protection today is the enumerate-mode watchdog (`_enum_wd_disarm` arming block) and a 4 h `TC_RUNTIME_CEILING_S` that is only consulted at suite *entry*. Separately, per-suite output artifacts live under the `soleur-run.<pid>` scratch root that `_soleur_scratch_cleanup` deletes on exit — a failing run keeps nothing.

## Hypotheses

Ordered per the network-outage discipline (L3 verified before L7 claims). deepen-plan Phase 4.5 fired on `timeout`; the layer table records live-verified state and the hypotheses below pick up where it stops.

**Network-Outage Deep-Dive (Phase 4.5 — `timeout` trigger):**

| Layer | State | Artifact |
|---|---|---|
| L3 firewall allowlist | Not applicable — no SSH/admin host path is the symptom; the incident is inside-request latency on an HTTPS public surface | — |
| L3 DNS/routing | Verified — `app.soleur.ai` resolves and serves continuously; unauthenticated `/dashboard` nav returns 307 in ~165 ms | `curl` this session |
| L7 TLS/proxy | Verified — Cloudflare-fronted `https://app.soleur.ai/health` → 200, TLS handshake clean | `curl -w ttfb` this session |
| L7 application | Verified — `/health` → `{"status":"ok",…"supabase":"connected"}` (uptime ~840 s) proves server→Supabase egress is live | health JSON this session |

The unverified tier is **L7 in-request transport**: per-request outbound latency to `*.supabase.co` inside individual transactions, which the layers above do not discriminate. That is what H1–H5 instrument.

- **H1 — Cold Supabase edge connection (TCP+TLS+edge routing) dominates cold-miss legs.** Discriminator: Sentry `http.client` spans on probe-armed requests show connect/TLS wall-time per outbound call; a periodic upstream warm-up (Phase C) collapses the tier iff this is the cause.
- **H2 — Supabase compute/PostgREST warm-up dominates (server-side stall, not client connect).** Discriminator: spans show long `waiting`/server-time with short connect; the warm-up ping also exercises compute, so it covers both arms — but the fix's success criterion differs (idle-cadence correlation for H2).
- **H3 — A retry/redirect loop or connect-timeout-then-fallback signature (e.g., IPv6-first connect stall).** ~30 s is consistent with a connect timeout + retry. Discriminator: span count per outbound request (one long span = stall; two stacked = retry), plus failure-mode correlation.
- **H4 — Render-path selects (`resolveIdentity`'s `users`/`workspace_members` pair) stall on the same cold upstream and explain most of the post-middleware tier.** Discriminator: the two selects' span durations inside the document transaction.
- **H5 — Event-loop starvation / dispatch contention inside the custom server (ws-handler, session-proxy, agent timers) delaying document handling.** Discriminator: transaction start-time gap (request receipt → Next handler dispatch) inside `server/index.ts`; if the gap is pre-Next, it is a server-side queue, not Supabase.

## Research Insights

**Premise validation (Phase 0.6):** All five cited issues are OPEN (`gh issue view` this session: #8978, #8985, #8926, #8993, #8940). Cited artifacts verified on `origin/main`: `apps/web-platform/middleware.ts` (mw-* emission, armed `.catch` grace arm, `check_my_revocation` call site), `server/request-auth.ts` (`verifiedUserId` + `sessionJwtEmailForVerifiedUser`), `lib/feature-flags/identity.ts` (`resolveIdentity` fast path — merged), `scripts/live-verify/perf-probe.ts` (committed probe), `sentry.server.config.ts` (`tracesSampler` armed on `x-perf-probe`), `scripts/test-all.sh` (flock via `tc_acquire`/`acquire_lock`, enumerate-only parent-death watchdog, `_soleur_scratch_cleanup`), migration `067_workspace_member_revocation_lookup.sql` (RPC is a trivially indexed one-row SELECT). ADR-253 read in full — the auth-verdict `LRUCache` rejection arm is recorded there; this plan does **not** re-propose it (see Cut List). Premises hold; nothing stale.

**Property List (Phase 0.6b):**

- P1: a cold-miss revocation leg cannot hold a request longer than a bounded wait — stalls map onto the existing `grace` arm.
- P2: the post-middleware document tier is *named* by a discriminating signal (Sentry span breakdown or an added in-surface probe), not inferred.
- P3: every still-remote Supabase read on the authenticated path is either bounded or justified; warm-path FCP ≲500 ms is attempted and the cold path lands a stated, verified bound.
- P4: a `test-all.sh` run whose parent died exits promptly and releases the repo flock — orphan-by-definition detection, not a ceiling heuristic.
- P5: a failing suite leaves durable, printed diagnostic output surviving scratch cleanup.
- P6: route handlers that need only `user.id` stop paying a remote `getUser()` RTT (#8926 sweep).
- P7: all auth/revocation/T&C gates keep their existing verdict semantics — bounds re-map onto arms that already exist (grace for revocation, fail-closed `db_unavailable` for T&C, re-verify for identity).

**Cut List (Phase 0.6b):**

- **Auth-verdict `LRUCache` on mw-auth** — ADR-253 amendment already rejected this with recorded reasoning (minority tier; cannot accelerate the *first* cold request; no coalescing). The cold-3 30 s revoke leg does not rescue it: the right fix for a stalled leg is a *bound*, not a verdict cache (a cache cannot populate on the miss that matters). Not re-proposed.
- **Stale-holder detection on the flock** — `scripts/lib/test-contention.sh` already documents why this is dead code: kernel flock releases on holder death. #8993's orphan was *alive*; the defect is liveness of the holder, not lock hygiene. The parent-death watchdog buys P4 directly.
- **Per-request verdict store / Redis / new cache substrate** — single-process deployment (ADR-253 in-process ruling); nothing here needs a store.
- **Whole-page SSR conversion** — ADR-253 rejected alternatives; unchanged.
- **Mount-fan-out aggregator route** — see #8985 disposition below: buys no property the measured data demands *now*; its re-evaluation criterion is unmet.

**Value measurement (Phase 0.6c):** Baselines are measured, not asserted — probe comment on #8978 (post-merge run): cold doc TTFB 1.57–38.1 s, mw-revoke miss 29.6 s, warm-sw TTFB 1.95 s, FCP cold 1.71–38.3 s / warm 2.08 s. The bound legs (P1) cap the worst middleware leg at `MW_RPC_TIMEOUT_MS`; the warm-up (H1/H2 arm) removes the cold-connection cost class entirely if armed; the getUser sweep removes ~300 ms–1 s × N authenticated requests across 66+ routes (measured warm RTT ~300 ms per prior plan).

**Relevant code facts (verified by reading this session):**

- `apps/web-platform/middleware.ts` — revocation leg at `supabase.rpc("check_my_revocation", ...)` inside `Promise.resolve().then(...)` with an armed `.catch` → `{kind:"grace"}`; `mw-tc` `users` select fails *closed* (redirect `/accept-terms?error=db_unavailable`, mirrored via `reportEdgeSilentFallback`); `mw-auth` `getUser()` failure → `redirectWithCookies("/login")`.
- postgrest-js (installed, `apps/web-platform/node_modules/@supabase/postgrest-js/src/`): `PostgrestTransformBuilder.abortSignal(signal)` exists (line ~200) — a bounded wait is one `.abortSignal(AbortSignal.timeout(MW_RPC_TIMEOUT_MS))` call; `PostgrestClient` also accepts a `timeout` option that wraps fetch in an `AbortController`.
- `scripts/lib/test-contention.sh` — `acquire_lock` → `_acquire_lock_impl` → `flock -w <timeout>`; deliberately no stale-holder detection (documented); suite children inherit the lock fd (open file description, no CLOEXEC) — an orphaned runner keeps it while *any* descendant lives.
- `scripts/test-all.sh` — enumerate-mode parent-death watchdog exists (`kill -0` parent + `ps -o stat=` zombie check + `lstart` pid-reuse guard + in-flight-child sweep, ~lines 649–710) but is armed **only** for `_ENUMERATE == 1`; the main run path has `_CEILING_S` (default `TC_RUNTIME_CEILING_S=14400`) checked only at suite entry — an orphan mid-suite is unbounded. `run_suite` runs `"$@" || rc=$?` — suite output streams to the runner's stdout and per-suite scratch artifacts land under `$SOLEUR_SCRATCH_SESSION_ROOT`, deleted by `_soleur_scratch_cleanup` on owner exit (`scripts/lib/scratch-root.sh`).
- Mount fan-out on /dashboard (grep this session): `foundation-status`, `dashboard/today`, `workspace/active-repo` (SWR `swrKeys.workspaceActiveRepo`), `dashboard/orphan-count` (conditional), `vision` (conditional POST), plus `workspace/list-memberships` (org-switcher-container), `workspace/pending-invites` (pending-invite-banner-recovery), `byok/effective-status` (no-api-key-banner).
- `getUser()` census (grep this session): 71 `app/api/**/route.ts` files contain `auth.getUser`; only 5 access fields beyond `user.id` (`user.email`/`user_metadata`/`app_metadata`): `repo/setup`, `checkout`, `workspace/accept-invite`, `workspace/invite-member`, `workspace/decline-invite`.
- Custom server `apps/web-platform/server/index.ts` — thin `http.createServer` dispatching to `handle()`; `setInterval` timers are an established in-process pattern (`agent-runner.ts`, `cc-dispatcher.ts` reapers).
- Sentry `@sentry/nextjs` 10.59.0 — Node auto-instrumentation emits `http.client` spans for outbound fetch/undici; transactions for `x-perf-probe: 1` requests sample at 1.0 (shipped). Read path for the spans: `scripts/sentry-issue.sh --host-events` precedent — `/api/0/organizations/jikigai-eu/events/` accepts `event.type:transaction` queries on the `SENTRY_ISSUE_RO_TOKEN` ([event:read, org:read]).

**Institutional learnings applied:**

- `2026-05-13-no-dashboard-eyeball-pull-data-yourself` — tier attribution comes from shipped instrumentation (Sentry spans, Server-Timing), never SSH eyeballing.
- Blind-surface rule (`2026-07-01-blind-surface-needs-structured-probe-before-nth-fix`) — the post-middleware tier gets an in-surface discriminating probe before a fix commits.
- `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper` — the getUser sweep enumerates *every* route file, classified id-read vs rich-field, not "the ones the plan remembered".
- `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms` — #8940's retention lives in the EXIT-trap window ordering, tested against failure arms that fire mid-window.
- `#8299`/`#7493` guard-vacuity learnings — Guard Contract mutation matrices below are derived from the design, each with a dispatch-red and a second-member row.

**Community/functional overlap (Phases 1.5, 1.5b):** no uncovered stack (Next.js + Supabase + bash runner are in-repo conventions); first-party instrumentation of our own auth path has no community substitute. Skipped, sequential-fallback (no Task fan-out in this runtime).

**External research (Phase 1.6):** skipped — the dominant uncertainty is empirical (which span dominates), answerable only by this deployment's own instrumentation; mechanisms below are already in-repo precedents.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "~70 route-level `auth.getUser()` call sites" (#8926) | 71 files contain `auth.getUser`; 5 use fields beyond `user.id` | Sweep the ~66 id-read sites; per-site disposition the 5 rich-field sites |
| "orphaned run holds the repo flock" (#8993) | Confirmed structurally: lock fd inherited by suite children; no main-path parent-death check (enumerate-only watchdog + 4 h suite-entry ceiling) | Parent-death watchdog on the run path mirroring the proven enumerate pattern |
| "failure output dies with the run dir" (#8940) | `soleur_scratch_session_begin` + `_soleur_scratch_cleanup` verified; suite output is streamed, not durably captured | Per-suite `tee` capture + on-failure tail preservation to a durable dir |
| "#8985: revisit if fetch COUNT dominates the cold window" | Post-merge data: document tier consumed the whole cold window on worst samples; the fan-out had not even fired | Deferred-with-data; re-evaluation note posted to #8985 at ship |
| "mw-revoke cold-miss ~30 s is RPC cost" | RPC body is an indexed one-row SELECT — cost is upstream transport, not the query | Bound the leg + dedup misses + upstream warmth (measurement-gated) |

## Proposed Solution

Five phases. Phases 0–2 close the #8978 diagnosis→bound→verify loop; Phase 3 is the mechanical sweep; Phase 4 is the test-all machinery pair. Phase ordering puts measurement before mechanism where the mechanism is genuinely unknown (document tier), and bounds before warmth (bounds are correct regardless of what the stall's root cause is).

### Phase 0 — Name the post-middleware tier (measurement)

1. **Re-run the committed probe** — `doppler run -c prd -- bun run scripts/live-verify/perf-probe.ts` (5 cold + 1 warm), same contract as the prior run (`LIVE_VERIFY_BROWSER_PATH` fallback per run.ts).
2. **Pull the armed Sentry transactions.** The `x-perf-probe` sampler is already live — query `/api/0/organizations/jikigai-eu/events/` (`event.type:transaction`, probe-window filter) with the `SENTRY_ISSUE_RO_TOKEN` read path (`scripts/sentry-issue.sh` Discover precedent). Read the span breakdown of each document request: `http.client` child spans to `*.supabase.co` (connect vs server time), the gap between request receipt and render, middleware vs render share.
3. **Conditional in-surface probe** (fires only if step 2 leaves the tier blind — e.g., middleware/render split across transactions or missing undici spans): add a cheap per-request timing log in `server/index.ts` around `handle()` and/or `performance.now()` spans inside `resolveIdentity` emitted via pino (`op: "render-identity"`, fields: `headerHit`, `selectDurMs`, `totalMs`) — discriminating ALL of H1–H5 in one event, per the blind-surface rule. Landed only if needed; either way the decision is recorded.
4. Deliverable of Phase 0: a committed measurement table (post to #8978 + PR body) naming each cold tier — the DoD's "which tier dominates" item, now at span granularity.

### Phase 1 — Bound every Supabase-facing leg on the authenticated path

Bounds re-map onto arms that already exist; no new verdict semantics.

5. **mw-revoke bound.** `supabase.rpc("check_my_revocation", ...).abortSignal(AbortSignal.timeout(MW_RPC_TIMEOUT_MS))` (postgrest-js `PostgrestTransformBuilder.abortSignal`, verified installed; precedent `server/cost-writer.ts`). Phase-0 smoke confirms `AbortSignal.timeout` exists in the middleware runtime (standard web API — expected; the manual `AbortController + setTimeout` form is the in-repo fallback, `cf-cache-purge.ts`). Abort lands as `DOMException` `"TimeoutError"` inside the armed `.catch` → `{kind:"grace"}` → existing grace arm (proceed + `reportEdgeSilentFallback`, `op` tags timeout distinct from error). `MW_RPC_TIMEOUT_MS` initial value ~5_000; the exact bound is set against Phase-0 numbers.
6. **Revocation miss in-flight dedup.** `Map<cacheKey, Promise<RevocationOutcome>>` beside `revocationOkCache`: a concurrent miss for the same `${sub}:${iat}` joins the in-flight promise instead of issuing a second RPC; entry removed on settle. Coalesces the N-concurrent-mount-fetch miss amplification (the shape cold-3 paid). Positive-only caching rules unchanged — dedup shares *work*, not *verdicts*.
7. **mw-tc bound.** Same `abortSignal` bound on the `users` T&C select. Timeout lands in the **existing** fail-closed `tcError` arm (`/accept-terms?error=db_unavailable` + Sentry mirror) — a ~30 s hang becomes a ~5 s compliance-preserving redirect. ADR-253 amendment records the bounded-wait posture.
8. **mw-auth bound — measurement-gated.** `getUser()` timeout → `!user` → `/login` redirect (today's exact error arm, earlier). Prescribed at a longer bound (~10 s) only if Phase 0 shows multi-second mw-auth stalls recurring; otherwise noted as reviewed-and-kept-unbounded with the number. Either arm recorded.
9. **resolveIdentity selects bounded.** Same `abortSignal` bound on the `users`/`workspace_members` pair in `resolveIdentity` — timeout lands in the *existing* degrade arm (`error || !data` → `role:"prd"`, null org/subscription), so a cold stall degrades chrome instead of hanging the document. `userId`/`email` are unaffected (fast path already local).
10. **Upstream warm-up — measurement-gated (H1/H2 arm).** If span data names cold upstream connection/compute: a `setInterval` warmer in `server/index.ts` (existing timer precedent) issues a pinned cheap request to the Supabase edge (e.g., `GET /rest/v1/` root or equivalent health endpoint, anon key, `AbortSignal.timeout`) on a ~15–20 s cadence — holds the undici pool/TLS session and PostgREST compute warm. Failure-tolerant (log-only). Note: middleware may run on a separate fetch dispatcher than the Node render path — the warmer covers the Node path; whether it also warms the middleware isolate is answered by Phase-0 span data, and the plan records whichever arm held.
11. **ADR-253 amendment** documenting the bounded-wait posture per leg and the dedup-warmup additions (see §Architecture Decision).

### Phase 2 — Verify (#8978 DoD)

12. Re-run the probe cold + warm; post the measurement table to #8978 and the PR body: warm FCP vs ≲500 ms, cold p50/p95 across ≥5 samples, per-leg `mw-*` and span breakdown.
13. Close-out arithmetic: if ≲500 ms warm FCP remains unreachable (transport floor + render), the measured bound + the arithmetic attach to #8978 — per the issue's own DoD wording the cold arm is "a stated, verified bound"; the warm-FCP gap is recorded as a decision challenge rather than silently re-scoped.

### Phase 3 — #8926 sweep: `auth.getUser()` → `verifiedUserId()`

14. Enumerate every `app/api/**/route.ts` carrying `auth.getUser` (71 on main today; re-grep at implementation — the list is generated, not hand-maintained).
15. Migrate the pure id-read sites (~66): `const { data: { user } } = await supabase.auth.getUser(); if (!user) 401` → `const userId = await verifiedUserId(req); if (!userId) 401`. Per-site diff kept mechanical; sites whose `user` object feeds only `user.id` are the sweep set.
16. Rich-field sites (5 found today — `repo/setup`, `checkout`, `workspace/accept-invite`, `workspace/invite-member`, `workspace/decline-invite`): evaluate per site — `sessionJwtEmailForVerifiedUser` where the email claim suffices (the #8984 precedent), else keep `getUser()` with a one-line documented reason.
17. A grep-guard vitest/shell assertion that the *remaining* `auth.getUser` route-site list equals the committed documented-exceptions list — the sweep cannot silently rot back (see Guard Contract).

### Phase 4 — test-all machinery (#8993, #8940)

18. **#8993 parent-death watchdog on the run path.** Mirror the enumerate watchdog's proven pattern (parent `kill -0` + `ps -o stat=` zombie check + `lstart` identity pin + in-flight child sweep via `pgrep -P` snapshot before TERM), armed for the non-enumerate run and disarmed from the existing EXIT trap list. Detection semantics: runner's PPID becomes 1 (reparented) or the captured parent pid is dead/zombie ⇒ no consumer exists ⇒ kill in-flight suite children, then TERM self so the EXIT trap runs (`_soleur_scratch_cleanup` + lock fd close). Documented kill switch `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` for deliberate detached runs (matches `SOLEUR_DISABLE_*` convention). Lock-fd inheritance wrinkle is covered by killing suite children *first* — same ordering the enumerate arm already implements.
19. **#8940 durable failure output.** Each `run_suite` dispatch captures combined output through `tee` into `$SOLEUR_SCRATCH_SESSION_ROOT/logs/<label>.log` (streaming unchanged — the operator still sees output live); on a non-`ok` status (`failed`/`killed`/tripwire), copy the last ~200 lines to `${XDG_STATE_HOME:-$HOME/.local/state}/soleur/logs/test-all-<pid>-<label>.log` and print the path in the `[FAIL]`/`[KILLED]` line. `PIPESTATUS[0]` reads the suite rc across the pipe (never `$?` post-tee); a `tee` failure cannot mask a suite failure. Cleanup-window ordering per the #8288 learning: retention runs inside the failure arm *and* the EXIT trap covers the killed-mid-suite arm, so no exit path between the last write and cleanup loses the tail.
20. Tests: `scripts/test-contention.test.sh` / a new runner fixture — orphan fixture (parent exit mid-run ⇒ runner exits, lock released), watchdog never fires while parent lives (must-PASS arm), failure-log fixture (failing suite ⇒ durable path printed + file exists + contains tail), clean-run fixture (no durable writes on all-ok).

### #8985 disposition — deferred-with-data

The issue's re-evaluation criterion is "revisit if fetch COUNT (not per-call latency) dominates the cold window." Post-merge measurement shows the opposite arm: the document tier consumed the entire cold window on the worst samples — the mount fan-out had not even dispatched. Batching mount fetches cannot accelerate first paint (they begin after the document arrives and JS executes), so it buys no property the ≲500 ms AC measures. Implementation would additionally force the mechanical UI-surface gate (`app/**/page.tsx`, `components/**` edits → BLOCKING tier + wireframe) into a perf PR — the same reason the prior plan deferred it. **Disposition: stays open; a re-evaluation comment with the fresh numbers is posted at ship.** If Phase-0 span data *does* show fetch-count queueing inside the cold window (contradicting the above), the disposition flips to "file the implementation plan" — still not folded into this diff.

## Files to Edit

- `apps/web-platform/middleware.ts` — `abortSignal` bounds on the revocation RPC + T&C `users` select (+ conditional mw-auth bound); in-flight dedup map for revocation misses.
- `apps/web-platform/lib/feature-flags/identity.ts` — `abortSignal` bounds on the `resolveIdentity` `users`/`workspace_members` selects.
- `apps/web-platform/server/index.ts` — conditional upstream warm-up interval (Phase-1.10, measurement-gated); conditional per-request timing log (Phase-0.3, fires only if Sentry spans leave the tier blind).
- `apps/web-platform/server/request-auth.ts` — only if a rich-field site's claim needs a small helper extension (expected: no change).
- `apps/web-platform/app/api/**/route.ts` — ~66 id-read sites migrated to `verifiedUserId()`; ≤5 rich-field sites evaluated per-site (each keep-`getUser()` decision carries an inline reason).
- `scripts/test-all.sh` — parent-death watchdog arm on the run path; per-suite `tee` capture; failure-tail preservation + printed path.
- `scripts/lib/scratch-root.sh` — only if the log subdir convention lands there (expected: none — retention path lives outside the scratch root by design).
- `scripts/test-contention.test.sh` / new fixture file(s) — orphan-watchdog + failure-retention fixtures.
- `apps/web-platform/test/*` — middleware/identity/request-auth suites covering bound, dedup, degrade arms.
- `knowledge-base/engineering/architecture/decisions/ADR-253-*.md` — amendment (bounded waits + dedup + warmer).
- `apps/web-platform/scripts/live-verify/perf-probe.ts` — only if Phase-0.3 adds fields the probe must emit (expected: none).

## Files to Create

- `scripts/test-all-orphan-watchdog.test.sh` (or folded fixture file) — the #8993 battery.
- `scripts/test-all-failure-log.test.sh` (or folded fixture file) — the #8940 battery.
- `knowledge-base/project/specs/feat-one-shot-8978-residual-cold-tiers/tasks.md` — task breakdown (Save Tasks step).

## User-Brand Impact

- **If this lands broken, the user experiences:** an authenticated `/dashboard` visitor bounces to `/login` or `/accept-terms?error=db_unavailable` on a slow-but-healthy upstream (bound too tight), or keeps hanging ≥30 s on first paint (bound absent/misfiring); a wrongly-degraded `resolveIdentity` shows a paying user the free-tier chrome for a page load.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the revocation grace arm absorbing a *timeout* widens the already-accepted fail-open window (a member removed mid-session whose removal RPC times out passes the middleware bounce for that request) — the RLS data layer still denies immediately; the `verifiedUserId` sweep trusts the middleware-minted header, so a matcher gap plus a deleted-header regression would hand an attacker-controlled `x-soleur-auth-user-id` to 70 routes at once.
- **Brand-survival threshold:** `single-user incident` — the T&C bounded wait and revocation grace sit on the consent/compliance boundary, and a wrong bounce strand locks one real user out of their own dashboard.

*Per-site note:* CPO sign-off is carried forward from the parent plan's identical blast radius (same middleware/auth surfaces, strictly-narrower failure windows); `soleur:engineering:review:user-impact-reviewer` runs at review time per the conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "Better Stack uptime monitor on https://app.soleur.ai/health (supabase:connected keyword pair) + mw-* Server-Timing descriptors on every authenticated document/API response (shipped in #8984); the committed perf-probe is the cold-path liveness probe"
  cadence: "monitor continuous; probe on-demand per measurement phase"
  alert_target: "operator email via Better Stack; Sentry issue stream for reportEdgeSilentFallback ops"
  configured_in: "apps/web-platform/infra (uptime + Sentry IaC); sentry.server.config.ts tracesSampler"
error_reporting:
  destination: "Sentry web-platform project via SENTRY_DSN; reportEdgeSilentFallback for middleware grace/timeout arms"
  fail_loud: "revocation timeout emits reportEdgeSilentFallback op=revocation_rpc_timeout (distinct from revokeError); tc timeout emits tc_query_failed + db_unavailable redirect; test-all orphan exit prints a named banner line"
failure_modes:
  - mode: "Supabase edge cold-stall on a Supabase-facing leg"
    detection: "mw-revoke/mw-tc Server-Timing desc + Sentry span wall-time on probe-armed transactions; the leg never exceeds MW_RPC_TIMEOUT_MS post-fix"
    alert_route: "Sentry issue via reportEdgeSilentFallback"
  - mode: "warm-up interval silently dead (timer cleared / throws)"
    detection: "warmer emits a low-volume periodic log/heartbeat tick; absence of ticks in the log stream is the detection (in-surface probe, per affected-surface rule)"
    alert_route: "log-scan during incident; Sentry on tick failure"
  - mode: "test-all run orphaned under dead parent"
    detection: "watchdog emits a named ORPHAN banner on fire + exits; waiters see lock release"
    alert_route: "stderr banner in the orphaned run's output + commit-gate unblocking"
  - mode: "failing suite output lost"
    detection: "every non-ok suite summary line carries a durable log path; a printed path that does not resolve is itself the failure"
    alert_route: "the [FAIL]/[KILLED] summary line"
logs:
  where: "web host pino stdout → Vector → Better Stack source 2457081; Sentry transactions under web-platform project; test-all durable tails under ${XDG_STATE_HOME:-~/.local/state}/soleur/logs/"
  retention: "Better Stack 90d; Sentry per-project retention; durable suite tails persist until operator prunes"
discoverability_test:
  command: "grep -o 'AbortSignal.timeout' apps/web-platform/middleware.ts"
  expected_output: "AbortSignal.timeout"
```

## Encryption Posture

Phase 4.10 trigger assessment: no `Files to Edit`/`Files to Create` entry matches `.tf$`, `supabase/migrations/*.sql`, `cloud-init`, or `docker-compose`; the prose does name a store class (the dedup `Map`, the durable log sink) and reuses a cross-component connection at higher cadence, so the block is written rather than waived.

```yaml
at_rest:
  - mechanism: "in-process memory only (Map<cacheKey, Promise>) — a volatile pending-promise map, not a persistent store; same class as ADR-253's existing verdict caches"
    evidence: "readers must wait Promise settlement; entry deleted on settle; carries no credential material, keyed on ${sub}:${iat}"
    defends_against: "dedup of concurrent in-flight misses on the same subject — nothing at rest to encrypt"
    does_not_defend: "anything persistent — the map is not durable state"
    disclosed_as: "ADR-253 amendment records the mechanism"
    live_verification: "concurrency fixture: N misses join one RPC; map is empty after settle"
  - mechanism: "plaintext-exception — durable suite tails under ${XDG_STATE_HOME:-$HOME/.local/state}/soleur/ on the operator host"
    evidence: "host-local files written by the local run; same fs ACLs as the scratch dir they replace; repo precedent `${XDG_STATE_HOME}/soleur/` in `scripts/tmpfs-guard.sh`, `scripts/soleur-tmp-purge.sh`, `plugins/soleur/scripts/lib/tmp-classify.sh` (`TC_RETAIN_DIR`)"
    defends_against: "nothing additional — test-output text on the same disk that already transiently held it under /var/tmp"
    does_not_defend: "credential redaction inside suite output — suites must not print secrets today; the durable copy adds retention, not new exposure"
    disclosed_as: "plan body + implementation comment; no compliance-posture.md row (test output is not a processing activity)"
    live_verification: "fixture asserts path printed on summary line resolves and holds the failure tail"
    exception:
      tracking_issue: "n/a — intentionally plaintext test output on the authoring host; opt-out via env var at implementation"
      expires_on: "n/a"
in_transit:
  - tls: "unchanged — warm-up reuses the existing webapp→Supabase TLS edge; no new destination, credential, or payload class"
    cert_verification: "unchanged — Node fetch/undici default verification"
    does_not_defend: "Supabase-side compromise — existing boundary, not widened"
    disclosed_as: "ADR-253 amendment"
```

## Guard Contract

### Guard 1 — bounded Supabase-facing legs

**Property.** No `supabase.rpc`/`from(...).select` call on the authenticated middleware or `resolveIdentity` render path can hold a request beyond its declared `AbortSignal.timeout` bound; every bound maps to a pre-existing verdict arm (grace / `db_unavailable` redirect / `!user` redirect / identity degrade), never to a new one.

**Assembly.** The three middleware call sites (`rpc("check_my_revocation")`, the T&C `users` select, and `auth.getUser()` if armed) plus the two `resolveIdentity` selects — the complete set of remote Supabase calls on the `/dashboard` request path, enumerated by grep of `supabase\.` in `middleware.ts` + `identity.ts`; each site's timeout→arm mapping is asserted by vitest fixtures injecting a never-resolving builder.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `.abortSignal(...)` from the revocation RPC | RED — never-resolving fixture hangs past the bound assertion |
| 2 | Bound the RPC but swallow the abort into `ok` instead of `grace` | RED — timeout must NOT write a positive verdict to `revocationOkCache` |
| 3 | Dispatch-red: stub the abort fixture so it never asserts | RED — the suite fails on 0 assertions, not vacuous green |
| 4 | Add a SECOND Supabase call on the path without a bound | RED — a census assertion lists the bounded call-site set; an unlisted remote call fails it |
| 5 | Must-PASS: a fast healthy RPC resolves normally and caches the positive verdict | PASS — bound never alters the happy path |

### Guard 2 — orphan watchdog liveness

**Property.** A `test-all.sh` run whose parent process dies exits within ~2× the watchdog poll interval, after killing its in-flight suite children, and releases the repo flock — while a run whose parent lives is never killed.

**Assembly.** The single watchdog arm/disarm pair: the arming site on the run path (after flag-parse, before `tc_acquire`) and the EXIT-trap disarm (`_run_wd_disarm` spliced beside `_enum_wd_disarm`). Every entry into a suite dispatch is irrelevant to the property — detection is parent liveness, not suite state.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the reparent/PPID check so the watchdog only polls `kill -0` on a dead pid | RED — zombie-parent fixture must still fire |
| 2 | Dispatch-red: watchdog armed but never polls (loop body skipped) | RED — orphan fixture times out, suite cannot green |
| 3 | Add a second arm site that double-arms the watchdog | RED/PASS-pinned — a duplicate-arm fixture asserts exactly one watchdog subshell |
| 4 | Fire-ordering: TERM self before killing in-flight suite children | RED — a child-holds-lock fixture asserts flock release |
| 5 | Must-PASS: run with live parent completes normally, watchdog disarmed on exit, no banner | PASS — contract permits normal runs |

### Guard 3 — failure-output retention

**Property.** Every suite reporting non-`ok` status leaves a durable log file outside the scratch root whose path is printed on that suite's summary line; a clean all-ok run writes nothing durable.

**Assembly.** `run_suite`'s three non-ok arms (`failed`, `killed`, `TRIPWIRE`) plus the EXIT-trap arm covering mid-suite kill — the four exits past which a suite's output could be lost; the `tee` capture site is the single chokepoint all four read.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Trap copies nothing on failure | RED — failure fixture asserts durable file exists |
| 2 | Print the path but copy a different/empty file | RED — fixture greps the durable file for the suite's own tail marker |
| 3 | Dispatch-red: summary line omits the path | RED — fixture asserts the printed path resolves |
| 4 | Reorder: cleanup deletes the scratch log before the failure arm copies it | RED — killed-mid-suite fixture (EXIT-trap arm) |
| 5 | Must-PASS: all-ok run leaves no durable files | PASS — retention is failure-scoped, not unconditional |

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-253`** in this PR: (a) bounded waits on every Supabase-facing leg — revocation timeout→grace, T&C timeout→`db_unavailable` fail-closed redirect, identity-select timeout→existing degrade arm, and whichever mw-auth arm Phase-0 data selects; (b) revocation-miss in-flight dedup (shared work, not shared verdicts — positive-only caching semantics unchanged); (c) the upstream warm-up interval if armed — a periodic cheap read on the existing webapp→Supabase edge. The amendment is a deliverable of this plan, not a follow-up.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`) at implementation. Enumeration for this feature: (a) external human actors — none new (founder + synthetic live-verify principal already covered); (b) external systems — Supabase edge already modeled (`webapp -> supabase "Auth and data"`); the warmer adds *cadence* to an existing edge, not a new element; Sentry already models transaction ingest; (c) containers/data-stores — none new (`platform.webapp.*` already modeled; durable log dir is operator-local scratch, not a modeled store); (d) access relationships — unchanged. **Expected conclusion: no C4 impact** — the implementer re-verifies this enumeration against the three files before writing it (the mandate forbids an unchecked "None").

### Sequencing

No staged-truth problem — the amendment describes the shipped state in the same PR.

## Open Code-Review Overlap

- `#2591` (docs CSP middleware + route intersection) — touches `middleware.ts`. **Acknowledge:** docs-only issue describing existing gates; re-check at merge, not folded.
- `#3829` (CI gate: new Sentry monitor type → sentry-scrub.ts must change) — `sentry.server.config.ts` not edited this time (sampler already shipped). **Acknowledge:** no new monitor type is introduced; the warm-up emits logs, not a new monitor class.
- `#8659` (33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox) — adjacent EXIT-trap territory in `test-all.sh` machinery. **Acknowledge:** this plan splices into the *existing* trap list rather than replacing it (the same discipline #8659 demands); the durable-retention arm ordering is Guard 3 row 4.
- `#7942` (two `*.mutation.sh` batteries ungated) — **Acknowledge:** unrelated surface (naming/gate coverage), no overlap with the watchdog/retention diff.
- `#3739` (extract reportSilentFallbackWithUser across ~11 api routes) — overlaps the #8926 sweep's file set. **Acknowledge:** orthogonal concern (Sentry reporting helper vs auth call); if a migrated route also touches the silent-fallback block, keep the two edits textually separate; scope-out stays open.
- `#4525` (resolveCurrentOrganizationId migration, getUser-related) — **Acknowledge:** historical migration issue; the sweep does not re-litigate it.
- `#3351`, `#2246` (kb-upload streaming; kb low-severity polish) — touch `app/api/` files inside the sweep set. **Acknowledge:** mechanical conflict risk only; the sweep keeps diffs minimal per file.
- `#2590` (extract useFirstRunAttachments from DashboardPage) — touches `dashboard/page.tsx`, which this plan does **not** edit (#8985 deferred). **Acknowledge.**

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — sequential-fallback, no Task fan-out in this runtime)
**Assessment:** Perf-boundary work on the middleware auth path + test-runner machinery. Architecture load: bounded waits change the freshness posture of three gates → covered by the ADR-253 amendment deliverable and Guard 1. The getUser sweep is mechanical with a documented-exceptions ratchet (Guard 3 assembly / Phase-3.17 assertion). CTO-lens concerns are the auth-boundary semantics (header remains advisory, absent⇒re-verify) and the orphan-watchdog's kill discipline (children before self, identity-pinned target) — both encoded in the phases and guard matrices.

### Product/UX Gate

**Tier:** none — the mechanical UI-surface override ran against the Files lists above: no `app/**/page.tsx` / `layout.tsx` / `template.tsx`, no `components/**`, no `pages/**`, no `*.njk/html/vue/svelte/astro` entry. `app/api/**/route.ts` is backend. The one UI-adjacent issue (#8985) is deferred per its own criterion, keeping this diff server-side. `Pencil available: N/A (no UI surface)`.

### GDPR / Compliance Gate (Phase 2.7 — advisory, inline)

The canonical regex surfaces ARE touched (auth flows in `middleware.ts`, `app/api/**/route.ts`). Assessment: no new processing activity, no new data categories, no new processors, no schema/migration change. `verifiedUserId` supplies the same `user.id` the handler already resolved — the read moves earlier in the pipeline, the datum does not change class. JWT-claim consumption (`email`/`sub`) is the #8984-shipped mechanism with its documented staleness bound. The durable suite logs live operator-local under `$XDG_STATE_HOME` and contain test output only (fixtures are synthesized per `cq-test-fixtures-synthesized-only`). No `compliance-posture.md` write triggered; nothing Art. 9, no missing lawful basis, no Art. 30 trigger. The work phase re-runs `soleur:gdpr-gate` against the cumulative diff before exit per its own convention.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `check_my_revocation` RPC carries `AbortSignal.timeout(MW_RPC_TIMEOUT_MS)`; a vitest with a never-resolving builder proves the leg lands in `grace` (never caches, proceeds, reports with a timeout-distinct op tag).
- [ ] Revocation misses dedup in-flight by `${sub}:${iat}` key: N concurrent misses issue exactly 1 RPC; map entry removed on settle; positive-only verdict storage unchanged.
- [ ] T&C `users` select is bounded; timeout produces the existing `/accept-terms?error=db_unavailable` arm (fail-closed unchanged).
- [ ] `resolveIdentity`'s `users`/`workspace_members` selects are bounded; timeout produces the existing degrade arm (prd/null fields, `userId`/`email` from the fast path unaffected).
- [ ] mw-auth arm recorded per Phase-1.8 (bounded at documented value or kept unbounded with the measured justification).
- [ ] If the warm-up arm is adopted: `server/index.ts` warmer runs on a fixed cadence, uses `AbortSignal.timeout`, logs failures, and a test proves a tick failure cannot crash the server. If rejected by Phase-0 data, the rejection + numbers are in the PR body and this AC is N/A.
- [ ] #8926: every `app/api/**/route.ts` `auth.getUser(` **call site** (awaited call, not comments/prohibition prose — grep e.g. `await auth.getUser` or `auth.getUser(` outside comment lines) is either migrated to `verifiedUserId()` (id-read) or carries a one-line documented reason; the call-site census equals the committed exceptions list (regression assertion in CI).
- [ ] #8993: a fixture killing the runner's parent mid-suite proves the watchdog exits the run, kills in-flight children, and releases the repo flock; a live-parent fixture proves no fire; `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` documented opt-out works.
- [ ] #8940: a failing suite leaves a durable log under `${XDG_STATE_HOME:-$HOME/.local/state}/soleur/logs/` whose printed path resolves and contains the suite's tail; all-ok runs write nothing durable; killed-mid-suite arm preserves the partial tail.
- [ ] ADR-253 amendment committed in this PR (bounded waits + dedup + warm-up disposition).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green; vitest/shell suites green for touched surfaces; `test-all.sh --affected` green.

### Post-merge (verification — automatable; no operator step)

- [ ] Probe re-run against the deployed build: measurement table posted to #8978 + PR body naming each cold tier (mw legs, render path, upstream spans) — DoD "which tier dominates" at span granularity.
- [ ] Warm-path probe: FCP ≲500 ms, OR the measured warm FCP + floor arithmetic attached to #8978 as the honest bound (DoD's stated-verified-bound arm) with the gap recorded.
- [ ] Cold-path probe: stated, verified bound (p50/p95, ≥5 cold samples) replaces the 23–38 s anecdote — DoD item 2.
- [ ] #8985 receives the re-evaluation comment citing the fresh fetch-count-vs-document-tier numbers.

## Test Scenarios

- Given a stalled revocation RPC, when `MW_RPC_TIMEOUT_MS` elapses, then the request proceeds via `grace` with no verdict-cache write and a timeout-distinct `reportEdgeSilentFallback` op.
- Given 6 concurrent requests sharing `${sub}:${iat}`, when the verdict cache is cold, then exactly 1 RPC is issued and all six join it.
- Given a T&C select stall, when the bound elapses, then the response is the `db_unavailable` redirect (never a grace pass).
- Given a stalled `resolveIdentity` select, when the bound elapses, then the document renders degraded chrome (prd/null) with correct `userId`/`email`.
- Given a killed lefthook parent mid-suite, when the watchdog polls, then the run exits ≤2 polls, children die first, the flock frees, and the ORPHAN banner prints.
- Given a live parent, when the run completes, then the watchdog never fired and disarmed cleanly.
- Given `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1`, when the parent dies, then the run continues (documented opt-out).
- Given a failing suite, when the summary prints, then the `[FAIL]` line names a durable path that resolves and contains the tail; given all-ok, then no durable files exist.
- Regression: `revoked=true`, malformed JWT, TC-unaccepted, unpaid paths behave byte-identically to pre-change (existing middleware suite stays green).

## Dependencies & Risks

- **Risk — bound too tight.** A bound under a legitimately-slow upstream converts stalls into redirect/degrade arms. Mitigation: bound values set against Phase-0 percentiles, not guessed; every arm is a *pre-existing* consequence, reclassified earlier.
- **Risk — verdict-cache temptation resurfaces.** The cold-3 30 s revoke leg makes the auth-verdict cache look attractive again; the fix here is bounds + warmth, not staleness — a cache cannot populate on the miss that hurts. Recorded in Cut List + ADR amendment.
- **Risk — middleware isolate vs Node pool.** The warm-up may only warm the render-path dispatcher; if span data shows the stall is isolate-local to middleware, the warm-up arm's reach is reassessed (and the bounds still cap the damage).
- **Risk — tee masking.** `run_suite`'s pipe changes `rc` semantics (`PIPESTATUS[0]`, not `$?`); a `tee` failure must never mask the suite rc — pinned by Guard 3's fixture and the sharp edge below.
- **Risk — sweep blast radius.** ~66 file edits is wide but mechanical; the documented-exceptions ratchet keeps the residual honest. If review finds the diff unreviewable, the phase splits at ship time (sweep commit separable).
- **Dependency — live-verify principal + Doppler `prd` env** for the probe (unchanged contract); `SENTRY_ISSUE_RO_TOKEN` (Doppler `soleur/prd`) for the span pull.
- **Deferral tracked:** #8985 deferred-with-data (criterion unmet); re-evaluation comment is an AC. Operator-side Chrome install (`yay -S google-chrome`) remains outside pipeline scope — probe runs under `LIVE_VERIFY_BROWSER_PATH=/usr/bin/chromium`.

## Sharp Edges

- `PromiseLike` builders (postgrest): `.then(onFulfilled, onRejected)` only — no `.catch()`/`.finally()`; and `Promise.resolve()`-unwrap before arming (existing middleware shape).
- `AbortSignal.timeout` aborts surface as a `DOMException` named `"TimeoutError"` (`server/github-retry.ts` docstring) — they must route to the *existing* arms, never mint a new verdict kind, and must never write the positive caches. Precedent-diff (Phase 4.4): `.abortSignal(AbortSignal.timeout(…))` on a postgrest chain already ships at `server/cost-writer.ts` (`LEDGER_READBACK_TIMEOUT_MS`); `AbortSignal.timeout` is used at `health.ts`, `token-validators.ts`, `github-api.ts`, `c4-writer.ts`. Middleware-runtime availability is unconfirmed — Phase-0 smoke; the manual `AbortController + setTimeout` fallback is itself in-repo precedent (`cf-cache-purge.ts`, chosen there because vitest fake timers do not drive `AbortSignal.timeout`'s runtime-internal timer — timeout-arm fixtures must use real short timeouts or an injected controller).
- `x-soleur-auth-user-id` stays advisory: absent/mismatched ⇒ re-verify; the sweep must not convert any route to trusting the header unconditionally.
- The `run_suite` pipe: `"$@" 2>&1 | tee <log>` then `rc=${PIPESTATUS[0]}` — reading `$?` reads `tee`'s rc and can false-green a suite.
- The watchdog's kill target is identity-pinned (`lstart` comparison) — a recycled pid must never take the signal (enumerate-arm precedent).
- Suite children inherit the lock fd — exit-ordering matters: children first, then the runner, or the flock survives the kill (#8993's exact failure shape).
- Sentry quota: `x-perf-probe` stays non-secret; the span pull uses the RO token via the existing Discover path — do not mint a second Sentry reader (sentry-issue.sh's own warning).
- User-Brand section must stay populated — deepen-plan Phase 4.6 halts on empty/TBD.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Auth-verdict `LRUCache` on mw-auth | Rejected — ADR-253 amendment; re-rejected above (cannot populate on the miss that matters; bounds are the correct mechanism for a stalled leg) |
| Retry-then-fail on stalled legs | Rejected — retries double a stalled leg's cost; the bound + existing arm is strictly cheaper |
| Supabase connection pre-warm per request | Folded — that IS the mount-time cost; the interval warmer amortizes it off the request path |
| Exclude `/api/*` from the middleware matcher | Rejected — ADR-253 alternatives (strips revocation/T&C enforcement) |
| `PR_SET_PDEATHSIG` via C wrapper | Rejected — Linux-only, needs a compiled helper; the `ps`-portable watchdog works on macOS+Linux and reuses proven code |
| Flock holder-liveness handshake (waiters detect dead holders) | Rejected — holder was alive; liveness-of-holder is a heartbeat protocol across N consumers vs one parent-death check at the source |
| Unconditional per-suite durable logs | Rejected — writes ~330 suite logs on every clean run; failure-scoped retention buys the same diagnostic property |
| Mount-fan-out aggregator now | Deferred-with-data — see #8985 disposition |

## References & Research

- Issues: #8978 (residual tiers), #8926, #8985 (deferred), #8993, #8940; prior: #8969 (shipped), PR #8984 / squash `9b6b0394`
- Prior plan: `knowledge-base/project/plans/2026-09-26-perf-dashboard-cold-load-first-paint-plan.md`; parent plan `2026-09-25-perf-dashboard-section-load-latency-plan.md`
- ADRs: ADR-253 (amend target), ADR-067 (GAP-G no-store), ADR-033
- Code anchors: `apps/web-platform/middleware.ts` (revocation leg + armed catch, tc fail-closed arm), `apps/web-platform/server/request-auth.ts` (`verifiedUserId`, `sessionJwtEmailForVerifiedUser`), `apps/web-platform/lib/feature-flags/identity.ts` (`resolveIdentity`), `scripts/lib/test-contention.sh` (`acquire_lock`, no-stale-holder note), `scripts/lib/scratch-root.sh` (`_soleur_scratch_cleanup`), `scripts/test-all.sh` (enumerate watchdog ~lines 649–710, `run_suite` fail arms), `apps/web-platform/node_modules/@supabase/postgrest-js/src/PostgrestTransformBuilder.ts` (`abortSignal`), `scripts/sentry-issue.sh` (Discover read precedent), `apps/web-platform/scripts/live-verify/perf-probe.ts`, `apps/web-platform/server/cost-writer.ts` (`.abortSignal(AbortSignal.timeout())` precedent on a postgrest chain), `apps/web-platform/server/github-retry.ts` (`TimeoutError` DOMException name)
- Measurement record: #8978 comments (Phase-0 run + post-merge run tables)
