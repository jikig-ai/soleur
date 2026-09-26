---
title: "perf(dashboard): cold load misses ≲500ms first-paint AC — diagnose the cold /api/* tier and close the first-paint gap"
type: perf
date: 2026-09-26
slug: perf-dashboard-cold-load-first-paint
branch: feat-one-shot-8978-cold-load-first-paint
issue: 8978
closes: [8978, 8969]
priority: high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# perf(dashboard): cold load misses ≲500ms first-paint AC

## Overview

Post-merge verification of the auth-waterfall collapse (squash `70a75c8`, deployed `v0.302.10`, PR #8903, plan `2026-09-25-perf-dashboard-section-load-latency-plan.md`) confirms the middleware collapse works — `mw-*` Server-Timing descriptors are present with miss→hit behavior — but the ≲500 ms first-paint acceptance criterion (`knowledge-base/project/specs/feat-one-shot-dashboard-load-latency/tasks.md` §7.3) is not met. Measured on the live-verify account: FCP 2.3–4.8s, cold `/api/*` calls 8–15s, authenticated warm document TTFB floor ~0.65s.

This plan (a) instruments the cold path until the dominant tier of the 8–15s `/api/*` time is named — the issue's Definition of Done item 1 — and (b) removes the remaining known fixed tax on the warm document path so FCP ≲500 ms is reachable, then measures both with a committed authenticated probe.

Spec lacks valid lane: — no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement

Three measured facts bound the problem:

- **Cold document nav** (pre-SW activation, #8969 evidence): `mw-auth;dur=301.2, mw-revoke;dur=909.8;desc=miss, mw-tc;dur=298.5;desc=miss` — the middleware legs alone cost ~1.2–1.5s wall when the verdict caches are cold, and the render path then pays `resolveIdentity`'s own remote `auth.getUser()` a second time per document.
- **Cold `/api/*` 8–15s** is unexplained by the known RTT inventory (middleware getUser + cold verdict misses ≈ 1.5–2s). Something beyond serial-RTT arithmetic dominates — candidates: Supabase TLS/session establishment per cold connection, token refresh on a cold session, connection storms from ~6 concurrent mount fetches, IPv6/connect-timeout fallback signatures, or Supabase-side compute warm-up. No instrument currently sees inside this window: `Server-Timing` is emitted on document responses only, and `tracesSampleRate: 0` in `sentry.server.config.ts`.
- **SW-proxied navigations are invisible to the instrument** (#8969): `sw.js` forwards navigations with `sec-fetch-dest: empty`, which lands in `NON_DOCUMENT_DESTS` and skips the whole `Server-Timing`/`no-store` block — so the dominant real-session case (every post-first-visit navigation) emits no `mw-*` data, and the probe numbers in the issue may under-report.

## Research Insights

**Premise validation (Phase 0.6):** PR #8903 is MERGED (2026-09-26, squash `70a75c8` present in history) — the collapse shipped. #8926 (remaining `auth.getUser()` route migration) is OPEN — confirmed live: 74 `app/api/**/route.ts` files still contain `auth.getUser`. #8969 (SW-proxied navigations skip Server-Timing/no-store) is OPEN — mechanism verified in `middleware.ts` (`NON_DOCUMENT_DESTS` gate) and `public/sw.js` (`respondWith(fetch(event.request))` on `mode === "navigate"`). `knowledge-base/project/specs/feat-one-shot-dashboard-load-latency/tasks.md` §7.3 exists and is checked; post-merge measurement shows the AC behind it is unmet. Premises hold; nothing stale.

**Property List (Phase 0.6b):** (P1) a measured tier breakdown of the 8–15s cold `/api/*` time exists and is committed with the PR; (P2) FCP ≲500ms on the warm document path; (P3) a stated, verified bound on the cold path; (P4) measurement rides the authenticated Server-Timing + Playwright probe class named in the DoD; (P5) all auth/revocation/T&C gates keep their fail-closed semantics (inherited from ADR-253, non-negotiable constraint).

**Cut List (Phase 0.6b):**

- Whole-page SSR conversion of the dashboard home — already in ADR-253's rejected alternatives ("larger refactor; the mount-fan-out reduction captures the same win"). Not re-proposed.
- SW app-shell caching of authenticated documents — collides with GAP-G `no-store` (ADR-067 stale-document leak class: a cached authenticated document restored after sign-out). Not proposed; a generic-skeleton shell would paint fast but is not "meaningful content" under the AC's intent — recorded as a decision challenge, not adopted.
- A new verdict-store substrate (Redis/shared cache) — ADR-253 already rejected shared verdict stores at single-replica; the in-process `LRUCache` precedent covers any new cache this plan adds.

**Value measurement (Phase 0.6c):** Baselines measured this session (unauthenticated, `curl` — the transport floor): `https://app.soleur.ai/dashboard` → 307 `/login` TTFB ~155ms; `/health` ~450ms. Issue-reported: authenticated warm doc TTFB ~0.65s, FCP 2.3–4.8s, cold `/api/*` 8–15s. Static RTT inventory per cold `/api/*` call: middleware `getUser` (~300ms warm, ~1s cold per #8969's cold-doc magnitudes) + revocation RPC on miss (~900ms measured) + `users` select (~300ms) + handler-side `getUser()` on the 4 unmigrated mount routes (~300ms+) + handler queries — arithmetic explains ~2–3s, not 8–15s; the residual is precisely what Phase 0 instrumentation exists to name.

**Relevant code facts (repo research, verified by reading):**

- `apps/web-platform/middleware.ts` — emits `mw-auth`/`mw-revoke`/`mw-tc` Server-Timing **inside** the document-only `Cache-Control` block (`sec-fetch-dest ∉ NON_DOCUMENT_DESTS`), so `/api/*` responses (dest `empty`) and SW-proxied navigations get nothing. Matcher covers all `/api/*` and nested `.ext` paths.
- `apps/web-platform/server/request-auth.ts` — `verifiedUserId(req)` returns the minted header id, falls back to `getUser()` (remote) when absent.
- `apps/web-platform/lib/feature-flags/identity.ts` — `resolveIdentity` still calls remote `auth.getUser()` then parallel `users` + `workspace_members` selects. It needs only `user.id` + `user.email`; the Supabase session JWT carries both claims — a local `getSession()` decode (the same mechanism middleware already uses for `sub`/`iat`) or the minted header can supply `id`, and the JWT `email` claim supplies `email`, eliminating the render-path auth RTT.
- Mount fan-out on `/dashboard` (greps of `app/(dashboard)/dashboard/page.tsx`, `dashboard-shell.tsx`, `components/dashboard/*`): `foundation-status` (wrapped → `verifiedUserId` ✓), `today` (`verifiedUserId` ✓), `workspace/active-repo` (`verifiedUserId` ✓), `inbox/emails` (`withUserRateLimit` ✓), and four still-remote sites: `workspace/list-memberships`, `workspace/pending-invites`, `byok/effective-status` — plus `vision` (conditional POST, onboarding path only).
- `apps/web-platform/sentry.server.config.ts` — `tracesSampleRate: 0` with an inline comment inviting enablement "when investigating specific performance issues". `sentry.client.config.ts` likewise 0.
- `apps/web-platform/scripts/live-verify/run.ts` — existing authenticated live-probe harness (bun, bundled `@playwright/test` chromium, allowlisted synthetic principal `live-verify@soleur.ai`, teardown invariants). No committed perf/paint probe exists; the issue's measurements were ad-hoc.
- Supabase access is HTTP-only (`<ref>.supabase.co` PostgREST/GoTrue via supabase-js `fetch`) — "DB/pooler cold start" resolves to TLS + Supavisor/compute warm-up at the Supabase edge, not a local pg pool.

**Institutional learnings applied:**

- `2026-05-13-no-dashboard-eyeball-pull-data-yourself` — the tier breakdown must come from shipped instrumentation, not SSH.
- `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper` — migrating hot routes to `verifiedUserId` requires naming every *other* auth path on the same request leg (middleware + render + handler), which Phase 1 enumerates explicitly.
- #7418/ADR-176 skeleton checkpoint — plan file persisted before this research.

**Community/functional overlap (Phases 1.5, 1.5b):** no uncovered stack (Next.js middleware + Supabase + Playwright are all in-repo conventions); no community artifact substitutes for first-party instrumentation of our own auth path. Skipped, sequential-fallback (no Task fan-out in this runtime).

**External research (Phase 1.6):** skipped — strong local context (prior plan, ADR-253, measured evidence in #8969/#8978); the uncertainty here is empirical (which tier dominates), answerable only by this repo's own instrumentation, not by external best-practice docs.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "~70 unmigrated route-level `auth.getUser()` call sites" (#8926) | 74 `app/api/**/route.ts` files contain `auth.getUser`; 4 of them are on the dashboard mount path | Migrate the 4 mount-path sites in this PR; leave the rest to #8926 |
| "Server-Timing block skipped for SW-proxied navigations" (#8969) | Verified: `sec-fetch-dest` degrades to `empty` under SW control; `mode` stays `navigate` | Fold #8969's fix sketch into Phase 0 (it is a prerequisite for P4 measurement) |
| "cold /api/* calls 8–15s" | Not explainable by the serial-RTT inventory (~2–3s accounted) | Phase 0 ships the instruments that name the residual before fix phases commit to a mechanism |

## Proposed Solution

Three phases, ordered so measurement precedes irreversible mechanism choice.

### Phase 0 — Instrument the cold path (unblocks the DoD)

1. **Fix #8969 document detection.** In `middleware.ts`, classify document-ness on `sec-fetch-mode: navigate` **or** `request.mode === "navigate"` in addition to the dest check — SW-forwarded navigations keep `mode: navigate` even when `sec-fetch-dest` degrades to `empty`. This restores both `Server-Timing` and GAP-G `no-store` on SW-proxied navigations. `test/middleware.test.ts` gains a SW-shaped request case (dest `empty`, mode `navigate`).
2. **Emit `mw-*` Server-Timing on authenticated `/api/*` responses.** Move the `Server-Timing` header set out of the document-only gate so API responses carry the middleware-leg durations; keep the `Cache-Control: no-store` set document-only (API handlers own their own cache semantics; a blanket no-store on API is a behavior change this plan does not need). Response header mechanics: same `response.headers.set` path already proven on documents — `NextResponse.next()` response headers merge onto the handler's response.
3. **Scoped Sentry tracing.** Replace `tracesSampleRate: 0` with a `tracesSampler` that samples 1.0 for requests carrying a `x-perf-probe: 1` header (emitted by the Phase-0.5 probe) and a low floor (~0.02) otherwise — no env/Doppler change, no production config mutation. Server-side transaction events reveal handler-internal spans (auth fallback hits, supabase-js fetch spans, resolver queries). **#3829 interaction:** enabling tracing creates transaction-class envelopes — verify `server/sentry-scrub.ts` handles (or harmlessly passes) transaction events before enabling; add a test asserting the scrub path is invoked/compatible for transaction payloads.
4. **Committed perf probe.** `apps/web-platform/scripts/live-verify/perf-probe.ts` (bun, bundled chromium from `@playwright/test`, synthetic `live-verify@soleur.ai` principal — reusing `run.ts`'s allowlist + teardown invariants). Captures per navigation: `performance.getEntriesByType("paint")` FCP/LCP, `PerformanceNavigationTiming` TTFB, `Server-Timing` response headers per request (via `page.on("response")`), and `/api/*` request timing waterfall. Emits a redacted JSON summary; `x-perf-probe: 1` header set on every request so server traces correlate. Runs cold (fresh context, no SW) and warm (SW-controlled second nav) passes.
5. **Run the probe, name the dominant tier.** The deliverable of Phase 0 is a committed measurement table (document + each `/api/*` leg × cold/warm) posted to #8978 and embedded in the PR body — the DoD's "which tier dominates" item.

### Phase 1 — Remove the remaining known fixed tax (independent of diagnosis)

6. **Migrate the four mount-path routes** (`workspace/list-memberships`, `workspace/pending-invites`, `byok/effective-status`, `vision`) from `auth.getUser()` to `verifiedUserId(req)` — the mechanical #8926 slice on the dashboard-critical path. Each site keeps the 401-on-null contract; `vision` POST additionally keeps its existing body validation.
7. **Kill the render-path duplicate `getUser()`.** `resolveIdentity` gains a fast path: read `x-soleur-auth-user-id` via `headers()` (RSC sees middleware-forwarded request headers) and decode `email` from the session JWT (`getSession()` local read — same decode middleware already performs for `sub`/`iat`); fall back to remote `getUser()` when the header is absent or the JWT claims are missing — absent ⇒ re-verify, never trust (ADR-253 contract unchanged). This removes ~300ms warm / ~1s cold from every document render.
8. **Conditional: positive-only auth-verdict cache** (`mw-auth` leg). IF Phase-0 measurement shows `mw-auth` dominating cold `/api/*` (e.g., per-request `getUser` ~1s+ cold), add an in-process `LRUCache` keyed on the access-token hash → `{userId, email}`, same `MW_VERDICT_TTL_MS = 30_000`, positive-only (only `user != null` stored; `null`/error re-verifies per request). This accepts ≤30s staleness on Supabase-side session revocation — the identical bound the revocation verdict cache already accepts for membership revocation — and **requires the ADR-253 amendment** (§Architecture Decision). If measurement instead shows the cold cost lives inside Supabase TLS/compute warm-up, this cache does not help and is NOT added — the fix would then be connection-level (e.g., a lightweight warm-up hit at boot, or HTTP keep-alive tuning), decided by the measurement.

### Phase 2 — Verify

9. Run the probe cold + warm against the deployed build; record FCP, TTFB, per-`/api` timings, `mw-*` and trace breakdown.
10. Update `knowledge-base/project/specs/feat-one-shot-dashboard-load-latency/tasks.md` §7.3 commentary or file the residual if bounds are unmet — the AC demands a *stated, verified* bound even where ≲500ms proves unreachable.

## Alternative Approaches Considered

| Approach | Why rejected / deferred |
|---|---|
| Migrate all ~74 `getUser()` route sites now | #8926 already tracks the full sweep; folding it in doubles this PR's blast radius for <5% of the dashboard-path win. This PR takes the 4 mount-path sites only; #8926 remains open |
| `auth.getClaims()` local JWT verification in middleware | ADR-253 deferred it: under HS256 it only avoids the RTT if asymmetric keys are adopted (ADR-033 scoped those to the runtime-JWT substrate). Phase-1 item 8 achieves the same removal via the verdict-cache pattern already ratified |
| Whole-dashboard SSR / app-shell SW caching | Both rejected in ADR-253 / collide with GAP-G no-store respectively |
| Client-side mount-fan-out batching (e.g., `/api/dashboard/bootstrap` aggregator) | Requires `app/(dashboard)/dashboard/page.tsx` + `dashboard-shell.tsx` edits → mechanical UI-surface BLOCKING + wireframe cycle for a non-visual change; deferred to a tracking issue, revisit if Phase-0 measurement shows fetch-count (not per-call latency) dominates |
| Enable `tracesSampleRate` flat (e.g., 0.1) | Header-scoped `tracesSampler` gives 100% coverage exactly where the probe runs and near-zero spend elsewhere; a flat rate pays for noise |

## User-Brand Impact

- **If this lands broken, the user experiences:** the dashboard's primary surface — `app.soleur.ai/dashboard` — either keeps its 2.3–4.8s blank/skeleton cold paint (status quo failure: the PR that claimed the AC met ships nothing that moves it), or, on the auth-adjacent paths (verdict cache, header consumption in render), a wrongly-denied session that bounces a paying user to `/login` or a wrongly-allowed one that serves ≤30s of stale auth.
- **If this leaks, the user's data/workflow is exposed via:** `Server-Timing` on `/api/*` responses discloses internal stage durations to the already-authenticated caller (same information they can measure client-side with a timer — low sensitivity, but it is a new header surface); a mis-scoped `tracesSampler` could ship transaction envelopes containing route/URL detail to Sentry at high volume (scrub-path compatibility is a Phase-0 checklist item).
- **Brand-survival threshold:** `single-user incident` — same reasoning as the parent plan: the diff touches the authentication boundary (middleware legs, the minted identity header, a possible auth-verdict cache); one wrongly-cached or wrongly-consumed identity on the dashboard is a single-user-visible trust breach.

*CPO sign-off note:* `requires_cpo_signoff: true` carried from the parent plan's posture on the same auth boundary. This run is headless/sequential-fallback — no Task fan-out; the sign-off is recorded as a ship-time checklist item, and `soleur:engineering:review:user-impact-reviewer` is the review-phase enumerator.

## Domain Review

**Domains relevant:** Engineering | none beyond

### Engineering

**Status:** reviewed (sequential-fallback — no Task fan-out in this runtime)
**Assessment:** Load-bearing risks: (a) document-detection widening for SW-proxied navigations must not extend `no-store` to non-document dests — the fix keys on `sec-fetch-mode`/`request.mode === "navigate"`, which `fetch()` API calls never set; (b) header-consumption in `resolveIdentity` must keep the absent⇒re-verify contract — the JWT decode supplies `email`/`sub` only *after* the minted header confirms the request traversed middleware; (c) the conditional auth-verdict cache extends ADR-253's positive-only pattern one leg further and is gated on Phase-0 evidence + an ADR amendment in the same PR. Security review at PR time: `security-sentinel` + `user-impact-reviewer` (threshold: single-user incident).

### Product/UX Gate

**Tier:** none — no `app/**/page.tsx`, `app/**/layout.tsx`, `app/**/template.tsx`, `components/**`, `*.njk`, or other UI-surface glob appears in Files to Create/Edit (mechanical override does not fire; the diff is middleware/server/API/SW/config/scripts only). Visual output is unchanged — this plan moves timing, not pixels.
**Pencil available:** N/A (no UI surface)

## GDPR / Compliance (advisory)

Canonical-regex trigger fires (plan edits `app/api/**/route.ts`). Assessment: no new personal-data processing — `verifiedUserId` forwards an id already minted upstream; the probe runs against the dedicated synthetic principal (`live-verify@soleur.ai`), not real user data; `Server-Timing`/`tracesSampler` expose timing and route metadata, and the Sentry scrub contract is checked as a Phase-0 gate item rather than assumed. No Art. 9 category, no new processor, no lawful-basis change. Disposition: no compliance-posture write required.

## Observability

```yaml
liveness_signal:
  what: "Existing /health keyword monitor (supabase:connected) + mw-* Server-Timing stage durations now emitted on authenticated document AND /api/* responses + x-perf-probe-scoped Sentry transactions"
  cadence: "per-request (Server-Timing + sampled traces); Better Stack keyword monitor unchanged"
  alert_target: "Better Stack monitor app_health (existing); Sentry for gate errors"
  configured_in: "apps/web-platform/middleware.ts (timing emission); apps/web-platform/sentry.server.config.ts (tracesSampler); apps/web-platform/infra/uptime-alerts.tf (existing monitor)"
error_reporting:
  destination: "Sentry web-platform via reportEdgeSilentFallback (middleware) / reportSilentFallback (handlers)"
  fail_loud: "existing op slugs preserved; new breadcrumb middleware.auth_header.absent unchanged; transaction envelopes flow only under the sampler's header/low-rate rule"
failure_modes:
  - mode: "document-detection widening leaks no-store or Server-Timing onto non-document fetches"
    detection: "vitest: an /api/* fetch (dest empty, mode cors) carries no no-store Cache-Control; a SW-proxied nav (dest empty, mode navigate) carries both headers"
    alert_route: "CI (middleware.test.ts)"
  - mode: "auth-verdict cache serves stale identity beyond TTL or caches a deny"
    detection: "vitest: cache set only on user != null; a getUser() error and a null user are never stored; a second in-TTL request performs zero getUser calls"
    alert_route: "CI + Sentry transient_grace rate (must not collapse to zero)"
  - mode: "probe header leaks to untrusted sampling"
    detection: "tracesSampler keys on a header value only this repo's probe emits; Sentry scrub test asserts transaction-envelope handling"
    alert_route: "CI (sentry scrub test)"
logs:
  where: "web host pino stdout → Vector → Better Stack source 2457081; Sentry transactions under web-platform project"
  retention: "Better Stack Logs retention (90d table); Sentry per-project retention"
discoverability_test:
  command: "grep -o 'sec-fetch-mode' apps/web-platform/middleware.ts"
  expected_output: "sec-fetch-mode"
```

## Encryption Posture

```yaml
at_rest:
  - store: "conditional auth-verdict cache — in-process LRUCache Map (token-hash → {userId,email})"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/middleware.ts (module-scope LRUCache; process memory only, no disk/serialization path — same declaration shape as the existing revocation/T&C caches)"
    defends_against: "nothing at rest by design — entries live ≤30s in process RAM and are gone on restart; keyed by token HASH, not token bytes"
    does_not_defend: "a process-memory disclosure of the running isolate (strictly weaker data than the live request stream the process handles)"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: ephemeral in-process state has no externally-checkable artifact"
in_transit:
  - connection: "middleware (edge isolate) -> RSC render (Node runtime), same process — extended consumer set: resolveIdentity now reads the minted header"
    enforced_at: "apps/web-platform/middleware.ts (delete-before-set ordering on x-soleur-auth-user-id)"
    tls: "none — intra-process header propagation; inbound leg already TLS via Cloudflare"
    cert_verification: "off"
    does_not_defend: "a client-forged inbound header — mitigated by the unconditional delete-before-set plus the matcher-coverage guard test, unchanged"
exception:
  justification: "intra-process header propagation and ≤30s in-memory verdicts carry no at-rest or in-transit cipher surface; the token-hash key stores no credential material"
  tracking_issue: "#8978"
  reevaluate_when: "the verdict cache grows a persistence path, a cross-process consumer, or key material instead of a token hash"
  expires_on: 2026-12-26
```

## Guard Contract

### Guard 1 — Document-classification emission gate

**Property.** Every authenticated response the middleware classifies as a document emits `Server-Timing` (mw-auth/mw-revoke/mw-tc) AND `Cache-Control: no-store`; every authenticated `/api/*` response emits `Server-Timing` and does NOT get the document `no-store` overwrite; SW-proxied navigations (`sec-fetch-dest: empty`, `sec-fetch-mode: navigate`) classify as documents.

**Assembly.** The single emission block at `apps/web-platform/middleware.ts` (`fetchDest`/`NON_DOCUMENT_DESTS` gate through the `Server-Timing`/`Cache-Control` header sets) — the only site where both headers are minted; exercised by `test/middleware.test.ts` request-shape fixtures.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `sec-fetch-mode === "navigate"` arm so only dest gates the block | RED — SW-nav fixture loses Server-Timing |
| 2 | Make the test never dispatch (e.g., the assertion helper early-returns) so zero requests are classified | RED — guard must fail on 0 checked, not pass vacuously |
| 3 | Add a SECOND authenticated request shape after a compliant first (e.g., `dest: image`, `mode: no-cors`) that must NOT get no-store | RED if the check stops at or over-applies beyond the first member |
| 4 | Suite-side: invert a fixture's expected header value | RED — a harness that cannot see a wrong assertion proves nothing |
| 5 | Must-PASS: API fetch (`dest: empty`, `mode: cors`) carries Server-Timing and keeps its handler-set Cache-Control | PASS — contract explicitly permits Server-Timing on non-documents |

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-253`** (same file, `## Decision` + `## Alternatives Considered`) in this PR — required only if Phase-1 item 8 (auth-verdict cache) is adopted by measurement; the amendment records the ≤30s staleness bound on Supabase-side session revocation and why the access-token hash is the cache key. If item 8 is rejected by measurement, the ADR amendment reduces to a one-line note that the render path consumes the minted identity header (a documented extension of Decision item 3). Either way the amendment ships in THIS PR, not a follow-up.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration for this feature: (a) external human actors — `founder` (dashboard user) already modeled, no new actor (the live-verify principal is a synthetic founder-class user, not a new element); (b) external systems — Supabase (`platform.infra.supabase`, edge `webapp -> supabase "Auth and data"`), Sentry (`sentry`, existing edges incl. transaction ingest — tracing changes payload class, not topology), Cloudflare already modeled; no new vendor; (c) containers/data-stores — `platform.webapp.dashboard`, `platform.webapp.api`, `platform.webapp.auth` all already exist; the service worker is browser-internal to `webapp`, not a separate modeled element; in-process LRU caches are not modeled stores (ADR-253 precedent); (d) access relationships — unchanged, same edges at lower latency. **Conclusion: no C4 impact** — the enumeration above is the supporting evidence, not a bare "None".

### Sequencing

No staged-truth problem — the ADR amendment describes the shipped state in the same PR.

## Open Code-Review Overlap

- `#2591` (docs(security): CSP middleware + route intersection doc) — touches `middleware.ts`. **Acknowledge:** documentation-only issue describing the existing gate; this PR changes emission classification — the doc issue should be re-checked at merge but is not folded in (docs scope, separate cycle).
- `#3829` (CI gate: new Sentry monitor type → sentry-scrub.ts must change) — touches `sentry.server.config.ts`. **Acknowledge + fold-lite:** enabling `tracesSampler` introduces transaction envelopes; Phase-0 item 3 includes the explicit scrub-compatibility check + test that the gate exists to demand. The gate issue itself stays open (it is about CI enforcement, not this change).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `middleware.ts` classifies SW-proxied navigations (`sec-fetch-mode: navigate` or `request.mode === "navigate"`) as documents: they emit `Server-Timing` + `no-store`/`Pragma`; a regression vitest proves the pre-fix shape skipped them (closes #8969).
- [ ] Authenticated `/api/*` responses carry `Server-Timing` with `mw-auth`, `mw-revoke`, `mw-tc` durations; non-document responses do NOT receive the document `no-store` overwrite; `x-soleur-auth-user-id` delete-before-set ordering unchanged.
- [ ] `sentry.server.config.ts` uses `tracesSampler`: 1.0 for `x-perf-probe: 1` requests, bounded low rate otherwise; `sentry-scrub` transaction-envelope handling verified by test.
- [ ] `apps/web-platform/scripts/live-verify/perf-probe.ts` exists, runs under bun against prod with the live-verify principal, emits redacted JSON with FCP + TTFB + per-request Server-Timing capture, and honors the run.ts allowlist/teardown invariants.
- [ ] `workspace/list-memberships`, `workspace/pending-invites`, `byok/effective-status`, `vision` routes use `verifiedUserId(req)`; each still 401s unauthenticated callers via the `getUser()` fallback.
- [ ] `resolveIdentity` consumes `x-soleur-auth-user-id` + JWT `email` claim when present (zero remote `getUser()` on middleware-traversed renders) and falls back to `getUser()` when absent; identity tests cover both arms.
- [ ] If the auth-verdict cache is adopted: positive-only, `≤ MW_VERDICT_TTL_MS`, keyed on token hash; deny/error verdicts never stored; vitest proves zero `getUser` calls on warm hit and full re-verification past TTL. If rejected by measurement, the rejection + numbers are recorded in the PR body and this AC is marked N/A.
- [ ] ADR-253 amended in this PR (either arm); C4 verified no-change with the enumeration above recorded.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green; vitest green for touched suites (middleware*, request-auth, identity, sentry-scrub, perf-probe unit surface).

### Post-merge (verification — automatable; no operator step)

- [ ] The perf probe's committed measurement table (posted to #8978 + PR body) names the dominant tier of the cold `/api/*` window — DoD item 1.
- [ ] Warm-path probe: FCP ≲500ms on an authenticated `/dashboard` document load (SW-controlled navigation included) — OR, if unreachable, the measured warm FCP + the arithmetic showing the remaining floor is attached and the residual filed.
- [ ] Cold-path probe: a stated, verified bound on cold `/api/*` (p50/p95 across ≥5 cold samples) replaces the 8–15s anecdote — DoD item 2.

## Test Scenarios

- Given a SW-controlled navigation (`sec-fetch-dest: empty`, `sec-fetch-mode: navigate`), when middleware runs, then the response carries `Server-Timing` and `Cache-Control: no-store`.
- Given an `/api/*` fetch (`dest: empty`, `mode: cors`), when middleware runs, then the response carries `Server-Timing` and no `no-store` overwrite.
- Given a request lacking `x-soleur-auth-user-id`, when `resolveIdentity` runs, then it calls remote `getUser()`; given the header present, then zero `getUser` calls occur and `email` comes from the JWT decode.
- Given `tracesSampler` and a request carrying `x-perf-probe: 1`, when the transaction is created, then sample rate is 1.0; without the header, the low floor applies.
- Given the auth-verdict cache (if adopted): warm hit → zero getUser calls; expired entry → full remote re-verify; getUser error → nothing cached.
- Regression: `revoked=true` verdict, malformed JWT, and TC-unaccepted paths behave exactly as pre-change (middleware suite unchanged-green).

## Dependencies & Risks

- **Risk — AC reachability:** warm FCP ≲500ms requires warm doc TTFB ≤~350ms (155ms transport floor + middleware hits + render). Items 6–7 remove ~600ms of measured warm tax but the margin is thin; the AC's post-merge arm explicitly allows a *stated verified* bound where ≲500ms is unreachable — flagged honestly rather than silently re-scoped.
- **Risk — measurement blindness persists:** if the cold 8–15s lives inside Supabase edge/compute (visible only as "gap between mw legs and handler start"), the tier breakdown still lands (Sentry span wall-times) but the fix may be vendor-tier, not code. Recorded as the diagnosis-gated Phase-1 fallback.
- **Dependency:** #8969 fix is folded in (this plan's Phase-0 item 1 IS its fix sketch); #8926 stays open for the remaining sweep; #3564 (Core Web Vitals infra) acknowledged — this plan's probe is scoped to this AC, not a general CWV platform.
- **Deferral tracked:** client-side mount-fan-out batching deferred (see Alternative Approaches) — tracking issue #8985, milestone Phase 4.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6 — filled above.
- `NextResponse.next({ request: { headers } })` header-snapshot ordering (from the parent plan): any new header minting must precede response (re-)construction.
- `PromiseLike` (Supabase builders): `.then(onFulfilled, onRejected)` only — no `.catch()`/`.finally()` (constitution; #1214).
- The `x-soleur-auth-user-id` header is an optimization, never an authz boundary — every new consumer keeps absent⇒re-verify.
- Server-Timing on API responses exposes stage durations to the authenticated caller — accepted above; do not extend to unauthenticated paths.

## References & Research

- Issue: #8978 (this), #8969 (folded in), #8926 (partial slice), #3564 (acknowledged), #3931 (deny-RPC cache, related)
- Parent plan: `knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md`; ADR-253, ADR-067 (GAP-G), ADR-033 (key scoping)
- Code anchors: `apps/web-platform/middleware.ts` (`NON_DOCUMENT_DESTS` gate, Server-Timing block), `server/request-auth.ts` (`verifiedUserId`), `lib/feature-flags/identity.ts` (`resolveIdentity`), `public/sw.js` (navigate branch), `scripts/live-verify/run.ts` (probe invariants)
