---
title: Fix prod /dashboard error + close observability + canary gaps
type: fix
classification: ops-only-prod-write
requires_cpo_signoff: true
issue: TBD (file at work-time if not already)
branch: feat-one-shot-prod-dashboard-error-observability-gap
pr: 3014
date: 2026-04-28
---

# Fix prod /dashboard error + close observability + canary gaps

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Hypotheses, Files to Edit, Phase 1, Phase 3, Phase 4, Risks, Sharp Edges, Test Scenarios.

### Key Improvements (deepen pass)

1. **Codebase-verified pinned versions** — `next@^15.5.15`, `@sentry/nextjs@^10.46.0`, `@supabase/ssr@^0.6.0` from `apps/web-platform/package.json:3+`. All API references in the plan reflect these pins.
2. **Critical new finding: client-only validator scope.** Grep confirmed `assertProdSupabaseAnonKey` is called from `lib/supabase/client.ts` only (browser bundle). `lib/supabase/server.ts`, `service.ts`, and `middleware.ts` do NOT invoke the validator. **Implication for the canary gap:** the SSR render of `/dashboard` would succeed (server bundle bypasses the validator); the throw fires only after client hydration. A canary that fetches `/dashboard` and asserts HTTP status (200/307) would STILL miss this class of failure because SSR returns a valid HTML body. The probe MUST also assert the absence of the error-boundary sentinel string in the body, OR run a headless browser that executes the client bundle.
3. **Middleware bypass for /health** confirmed at `middleware.ts:18-20` — `if (pathname === "/health") return NextResponse.next();`. /health does not exercise Supabase auth, the client bundle, or the dashboard layout. This is exactly why the canary missed.
4. **Sentry client config has `tracesSampleRate: 0`** (`sentry.client.config.ts:6`) — affects perf only; exception capture still fires. NOT a contributor to alert silence.
5. **Sentry server `instrumentation.ts` register() is a no-op** — comment at line 4-6: "register() is NOT called by Next.js when using a custom server. Server-side Sentry.init() happens via direct import in server/index.ts." So a server-side throw during the dashboard page-component module-load would only reach Sentry if `server/index.ts`'s direct init ran first. Verify in Phase 1.
6. **Canary probe design refined.** The 307-redirect-to-/login assumption is wrong: `/dashboard` is in the `(dashboard)` route group whose `layout.tsx` is `"use client"`; the unauthenticated redirect happens inside the client render via `router.push("/login")` in `handleSignOut`, not via middleware. Middleware DOES protect non-public paths (line 49 onward), but `/dashboard` will return whatever middleware decides — likely a 307 redirect to /login. Phase 3 must verify this empirically before locking the canary contract.
7. **`reportSilentFallback` client shim signature verified.** Same shape as server version (`{feature, op?, extra?, message?}`). Phase 4.1 migration is a 1:1 swap.

### New Considerations Discovered

- **SSR/client divergence is the root cause of the canary blind spot.** Any future fix must consider this: SSR success ≠ client success.
- **Sentry source-map upload status unknown.** `sentry.client.config.ts` has only `dsn`, `environment`, `tracesSampleRate: 0`. No `release` or `source-maps` config visible — likely uploaded via `@sentry/nextjs` build plugin, but unverified in this codebase. Phase 4.4 audit is now load-bearing.
- **`SENTRY_CSP_REPORT_URI`** is referenced in `middleware.ts:38` for CSP violation reports — separate channel from the JS exception channel. Verify both DSNs and the report URI are populated in Doppler `prd`.

## Overview

`app.soleur.ai/dashboard` renders the Next.js error.tsx fallback ("Something
went wrong / An unexpected error occurred / Try again") for every visitor.
A recent change shipped to production broke the route. **Three compounding
failures** are in scope and treated as one incident:

1. **Production fix** — identify the change that broke `/dashboard` and ship
   the fix to prod.
2. **Observability gap** — Sentry / pino / Cloudflare alerts did not fire
   despite every visitor hitting the boundary.
3. **Canary gap** — the canary upgrade promoted the broken bundle to prod;
   the canary health check passed.

Fixing only the immediate breakage without closing (2) and (3) means the next
regression silently ships the same way. Per AGENTS.md
`hr-weigh-every-decision-against-target-user-impact`, this is a single-user
incident threshold (every dashboard visitor sees the error) and requires CPO
sign-off at plan time.

## Working hypothesis (to verify in Phase 1)

PR #3007 (commit `7d556531`) added `assertProdSupabaseAnonKey` called at
**module load** from `apps/web-platform/lib/supabase/client.ts`. Both
`app/(dashboard)/layout.tsx` and `app/(dashboard)/dashboard/page.tsx` import
`createClient` from that module. If any JWT-claim check fails in production,
the module throws at first import, every dashboard render aborts, and the
error.tsx boundary renders the generic copy.

The most likely failure modes (to confirm with prod logs):

- **A. Custom-domain ref mismatch.** `NEXT_PUBLIC_SUPABASE_URL` in prod is
  `https://api.soleur.ai` (custom domain). The runtime cross-check
  `expectedRefFromUrl` returns `null` for `api.soleur.ai` and skips the
  `ref === expected` assertion (per validator comments) — so this path is
  safe by design. **But** if Doppler `prd` was updated to a `<ref>.supabase.co`
  URL while the JWT was sourced from a different project, the cross-check
  WOULD fail at runtime. Verify the URL in prod's container env.
- **B. Stale anon-key in Doppler `prd`.** GitHub Secret
  `NEXT_PUBLIC_SUPABASE_ANON_KEY` and Doppler `prd` may have drifted (only
  Doppler is read at runtime by the container; build-arg values are static).
  CI Validate uses the GitHub secret; container reads Doppler at start.
- **C. `NODE_ENV=production` triggers the validator at runtime even though
  CI passed.** CI's Validate step runs against the GitHub repo secret. If
  the prod container's `NEXT_PUBLIC_SUPABASE_ANON_KEY` (from Doppler) differs
  from the GitHub secret used at build time, the runtime guard fires.
- **D. Some unrelated runtime crash** in the dashboard render path. Less
  likely (timing aligns with #3007 ship), but Phase 1 verifies via Sentry
  digest and prod container logs.

Phase 1 is a diagnostic phase: we DO NOT begin remediation until prod logs
identify the actual throw site. The full remediation plan (Phases 2–5) is
written for hypothesis A/B/C and is the most likely path; if Phase 1 surfaces
hypothesis D the plan is regenerated with the correct root cause.

## User-Brand Impact

**If this lands broken, the user experiences:** `/dashboard` continues to
render the error boundary; users cannot reach Command Center, Knowledge Base,
Settings, or the chat page (the entire authenticated surface). Sign-in
appears to work but every post-auth landing breaks.

**If this leaks, the user's workflow is exposed via:** an extended outage of
the only authenticated UI surface — users perceive Soleur as unusable; loss
of trust at the most expensive moment (post-conversion). No data exposure,
but the outage IS the brand-survival event.

**Brand-survival threshold:** single-user incident — every authenticated
visitor hits the broken route on landing.

CPO sign-off required at plan time before `/work` begins (carried forward
from brainstorm or invoked here). `user-impact-reviewer` will run at review
time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Research Reconciliation — Spec vs. Codebase

| Spec / hint claim | Codebase reality | Plan response |
|---|---|---|
| "/dashboard error.tsx is the rendering surface" | `apps/web-platform/app/error.tsx` is the only error.tsx; there is no `app/(dashboard)/error.tsx` or `app/(dashboard)/dashboard/error.tsx`. The root error.tsx catches the throw. | Confirmed. Phase 4 adds a route-segment error.tsx at `app/(dashboard)/error.tsx` for narrower segment isolation + better diagnostics. |
| "Canary health check probes `/dashboard`" | `infra/ci-deploy.sh:271` probes `curl -sf http://localhost:3001/health` only. `/dashboard` is auth-required and never probed. | Confirmed gap. Phase 3 widens canary to probe `/dashboard` (expecting 200 with the unauthenticated-redirect or the dashboard render — design decision in Phase 3). |
| "error.tsx logs to Sentry via reportSilentFallback" | error.tsx calls `Sentry.captureException(error)` directly in a `useEffect`. Does NOT use `reportSilentFallback` from `@/server/observability` (server-only) or `@/lib/client-observability` (the client shim). | Phase 2 migrates error.tsx to `@/lib/client-observability.reportSilentFallback` so the call is uniform and gets the `feature` tag. |
| "Sentry source maps are uploaded" | TBD — verify in Phase 1 via Sentry release artifacts. | Phase 2 audit. |
| "Sentry DSN is configured for prod" | `sentry.client.config.ts` reads `NEXT_PUBLIC_SENTRY_DSN`; `sentry.server.config.ts` reads `SENTRY_DSN`. Neither verified in prod Doppler. | Phase 1 confirms both are set in Doppler `prd`. |

## Hypotheses

(Network-outage checklist not applicable — the symptom is a Next.js render
error, not an SSH/L3 connectivity event.)

### Research Insights — failure-mode taxonomy

After grep-verified review of the validator call sites:

- `assertProdSupabaseAnonKey` runs ONLY from `apps/web-platform/lib/supabase/client.ts:20-23` (browser bundle, module load).
- `assertProdSupabaseUrl` runs from the same site (line 19) AND is the same client-only scope.
- `lib/supabase/server.ts` and `lib/supabase/service.ts` do NOT invoke either validator. SSR rendering uses these server modules; the dashboard SSR pass would succeed even with a malformed anon key.
- `middleware.ts` (Edge runtime) ALSO uses `process.env.NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` directly via `createServerClient` and does NOT call the validators. Middleware wouldn't crash.

This means: **the throw is client-side only.** The HTML for `/dashboard`
arrives at the browser successfully; client hydration triggers the throw
when `(dashboard)/layout.tsx` (`"use client"`, line 1) imports
`@/lib/supabase/client`. React renders the closest error boundary.

### Hypotheses (refined)

H1 (most likely): **`assertProdSupabaseAnonKey` throws at client-bundle
module load** because the value inlined into the static bundle by the
Next.js DefinePlugin fails one of: 3-segment shape, `iss="supabase"`,
`role="anon"`, canonical 20-char ref, placeholder-prefix denylist, or
URL/ref cross-check (skipped on `api.soleur.ai`). The value is BAKED IN
at build time — the runtime container's Doppler value is irrelevant for
client-bundle behavior. The CI Validate step in `reusable-release.yml:313+`
should have caught this; verify whether it ran on the suspect deploy.

H1a (subcase of H1): **CI Validate step passed but build-arg was a
different value.** `reusable-release.yml:405-406` shows
`NEXT_PUBLIC_SUPABASE_URL=${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}` is the
build-arg source. If the CI Validate step decoded the same secret BEFORE
docker build, the values are identical. So H1a requires a Validate-step
bug (e.g., the CR/LF-strip sanitization mentioned in PR #3007's fix
landed AFTER the suspect deploy). Verify deploy timestamp vs. PR #3007
merge time.

H1b (subcase of H1): **Custom-domain CI binding regression.** PR #3007
notes the CI step does `dig +short CNAME` for `api.soleur.ai` to bind
the JWT ref. If the CNAME resolution timed out (no `+time=` flag) or
returned a different ref than expected, CI may have validated against
one value and built with another.

H2: **`assertProdSupabaseUrl` throws at client-bundle module load**
(same root cause class as H1, separate validator).

H3: **Sentry DSN missing or misconfigured in prod**. `sentry.client.config.ts`
reads `NEXT_PUBLIC_SENTRY_DSN` (build-time inlined). If it's empty,
`Sentry.init({ dsn: undefined })` is a no-op — every captureException
silently succeeds with no network call. Verify the DSN is in Doppler `prd`
AND was inlined into the build (grep the deployed bundle for the DSN
prefix).

H4: **Sentry DSN set but no alerting rule** for either
`feature: "dashboard-error-boundary"` or unhandled exceptions on the
`/dashboard` route. Events arrive but no email/Slack/Discord alert fires.
Verify in Sentry's project settings.

H5: **Cloudflare logpush configured but no 5xx alert rule** at the edge.
Confirmed: not a contributor — the page returns 200 (the error.tsx
boundary IS the rendered output, not a server 5xx). CF can't see this
class without a body-content rule. Phase 4.6 synthetic check is the right
mitigation, not a CF rule.

H6: **A non-supabase regression.** Lower likelihood given timing
correlation with PR #3007 ship. Possible candidates:
- The PR #2994 SW cache bump (v1→v2) could leave clients on a stale
  bundle if the SW serve-stale-while-revalidate logic is broken.
- A typed-OAuth-error-classifier regression that throws synchronously in
  a way that triggers the dashboard layout's `getSession()` early.

Phase 1 disambiguates H1 vs. H6 by reading the actual stack frame from
Sentry (if H3 is also true, fall back to prod browser console via
Playwright MCP).

## Files to Edit

- `apps/web-platform/app/error.tsx` — migrate Sentry call to
  `reportSilentFallback` shim from `@/lib/client-observability`; add
  `feature: "dashboard-error-boundary"` tag and `digest` to extras for
  cross-referencing prod logs.
- `apps/web-platform/lib/supabase/client.ts` — change runtime validator
  posture: keep the existing assertions, but instead of throwing at module
  load (which collapses the entire auth-required surface and makes
  diagnosis hostile), wrap the call site so it (a) `reportSilentFallback`s
  with full context AND (b) re-throws with a SAFE error message that does
  NOT leak the JWT preview into the user-visible boundary. The validator
  itself remains throw-on-failure — the change is the *consumer* posture.
  **Open question for review:** should we degrade-not-fail? Decision in
  Phase 4 — see "Sharp Edges". Default: re-throw, but emit Sentry first.
- `apps/web-platform/infra/ci-deploy.sh` — widen canary probe set beyond
  `/health` (Phase 3). New probes: `/login` (public auth route) AND
  `/dashboard` (auth-required, expecting 200 with the layout's
  unauthenticated-redirect chain or 307 to /login). Both must succeed
  before swap.
- `apps/web-platform/scripts/verify-required-secrets.sh` — extend
  Doppler-side gate to assert URL/JWT-ref binding for canonical hostnames
  (already done in #3007, verify; extend to detect dev/prd Supabase
  identity if drifted).
- `plugins/soleur/skills/preflight/SKILL.md` — add Check 7 "Canary probe
  set covers authenticated surface", referencing the new ci-deploy probes.

## Files to Create

- `apps/web-platform/app/(dashboard)/error.tsx` — segment-scoped error
  boundary so a `/dashboard` failure doesn't bubble to the root and the
  digest tag carries `segment: dashboard`.
- `apps/web-platform/test/lib/supabase/client-runtime-validator.test.ts` —
  test that module-load throws AND emits a Sentry event before re-throw
  (deterministic — see Sharp Edges on LLM-mediated test paths; this one
  is direct-invocation).
- `apps/web-platform/test/infra/ci-deploy-canary-probe-set.test.sh` —
  extends `ci-deploy.test.sh` with cases asserting BOTH `/health` AND
  `/dashboard` are probed and BOTH must pass for canary swap.
- `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` —
  postmortem doc capturing the timeline, the canary gap, the Sentry gap,
  and the four-layer remediation.
- `knowledge-base/project/learnings/runtime-errors/2026-04-28-module-load-throw-collapses-auth-surface.md` —
  learning file for the throw-at-module-load anti-pattern in client bundles
  imported by every authenticated route.

## Implementation Phases

### Phase 1 — Diagnose (READ-ONLY, blocking gate)

Goal: identify the actual throw site in prod. Do NOT begin remediation
before this phase completes with a confirmed root cause.

The validator is client-side only (see Hypotheses → Research Insights).
That changes the diagnostic order: **the deployed bundle is the source of
truth, not the runtime container env.** Doppler reads matter for the
non-client server paths and for the next deploy, not for the in-flight
broken client bundle.

1. **Sentry digest review.** Filter Sentry prod project to events since
   PR #3007 merge time (`git log -1 --format=%cI 7d556531` →
   `2026-04-28T22:12:22+02:00`). Look for: stack frames referencing
   `validate-anon-key`, `validate-url`, `assertProdSupabase`, OR
   `(dashboard)/layout` / `(dashboard)/dashboard/page`. Capture digest
   IDs, redacted error.message, stack trace, count, first-seen timestamp.
   If zero events, H3 (Sentry DSN missing / not inlined) is confirmed —
   skip to step 4.
2. **Direct browser-console capture via Playwright MCP** (always run, even
   if step 1 returned events — the actual unminified stack is in the
   browser):
   ```
   mcp__playwright__browser_navigate https://app.soleur.ai/dashboard
   mcp__playwright__browser_console_messages
   ```
   Look for: `Error: NEXT_PUBLIC_SUPABASE_ANON_KEY ...` or
   `Error: NEXT_PUBLIC_SUPABASE_URL ...`. The error message format from
   the validator includes the FAILED claim and a preview — this
   pinpoints the exact assertion that fired.
3. **Inspect the deployed bundle directly** for the inlined values
   (preflight Check 5 Step 5.4 from PR #3007 is the canonical recipe):
   ```bash
   # Fetch a chunk that imports lib/supabase/client (likely _app or layout)
   curl -s 'https://app.soleur.ai/_next/static/chunks/app/(dashboard)/layout-*.js' \
     | grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' \
     | head -1
   # Decode the payload segment
   ```
   The decoded JWT shows the value the bundle is asserting against. The
   bundle ALSO has the URL inlined nearby — grep for
   `NEXT_PUBLIC_SUPABASE_URL` substring or the canonical hostname.
4. **Sentry DSN presence + bundle inlining.** Two checks:
   - `doppler secrets get NEXT_PUBLIC_SENTRY_DSN -p soleur -c prd --plain` (per-command ack required)
   - `curl -s https://app.soleur.ai/_next/static/chunks/main-*.js | grep -oE 'https://[a-z0-9]+@[a-z0-9.-]+sentry\.io/[0-9]+' | head -1`
   If the Doppler value exists but the bundle does NOT contain it, the
   build-arg pipeline drops it (verify `reusable-release.yml` build-args
   include `NEXT_PUBLIC_SENTRY_DSN`).
5. **Doppler vs GitHub-secret + custom-domain CNAME state** (per-command
   ack required):
   - `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain`
   - `doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain`
   - Decode JWT payload, assert `iss === "supabase"`, `role === "anon"`,
     `ref` shape (`^[a-z0-9]{20}$`), URL/ref binding (or custom-domain
     skip per `validate-anon-key.ts:99-101`).
   - `dig +short +time=2 +tries=1 CNAME api.soleur.ai` — confirm the
     custom domain still resolves to the canonical Supabase ref CI
     expects.
   - `gh secret list -R jikig-ai/soleur --json name,updatedAt` — confirm
     the last-update timestamp on `NEXT_PUBLIC_SUPABASE_ANON_KEY` and
     `NEXT_PUBLIC_SUPABASE_URL`.
6. **Prod container env diff** (READ-ONLY SSH diagnosis allowed):
   ```bash
   ssh prod-web docker inspect soleur-web-platform \
     --format '{{range .Config.Env}}{{println .}}{{end}}' \
     | grep -E '^NEXT_PUBLIC_SUPABASE_|^NEXT_PUBLIC_SENTRY_'
   ```
   Note: container env affects server-side reads; the client bundle is
   already inlined. Keep this for completeness and for the post-fix
   restart in Phase 2.
7. **Cloudflare logpush.** Verify there's no edge-level 5xx alert
   masking — confirmed pre-deepen: error.tsx returns 200, CF cannot see
   this class. Document as out-of-scope for this PR.
8. **Decision gate.** Write a one-page diagnostic into
   `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`
   with the confirmed root cause. The diagnostic MUST cite specific
   artifact paths (Sentry event ID, browser-console transcript file,
   bundle chunk URL with grep output) — not "I think it's H1." If the
   cause is NOT H1/H1a/H1b/H2 (i.e. an H6 surprise), regenerate this
   plan with the correct root cause before proceeding to Phase 2.

### Phase 2 — Remediate the immediate breakage

Branch: this branch (`feat-one-shot-prod-dashboard-error-observability-gap`).

**Important (deepen-pass):** the validator is client-side / build-time
inlined. A `docker restart` alone will NOT fix the deployed bundle. The
fix requires a new build via `web-platform-release.yml`. Phase 2 below
reflects this.

1. **Determine the fix shape from Phase 1's diagnostic:**
   - If Doppler `prd` is correct AND the bundle has a wrong value
     inlined: a CI build-arg pipeline bug. Trigger
     `gh workflow run web-platform-release.yml` (per-command ack) — the
     re-build picks up the now-correct CI Validate step, builds against
     the GitHub repo secret, and ships a clean canary.
   - If Doppler `prd` is wrong: `doppler secrets set
     NEXT_PUBLIC_SUPABASE_ANON_KEY=<canonical> -p soleur -c prd`
     (per-command ack), THEN trigger a new release build. Doppler is
     read at BUILD time via the docker build-args plumbing.
   - If the GitHub repo secret is wrong: `gh secret set
     NEXT_PUBLIC_SUPABASE_ANON_KEY -R jikig-ai/soleur < /dev/stdin`
     (per-command ack, value piped via stdin to avoid shell history),
     THEN trigger a new release build.
2. **Trigger a new release build.** `gh workflow run
   web-platform-release.yml --ref main` (per-command ack). Poll
   `gh run list --workflow=web-platform-release.yml --limit 1
   --json status,conclusion` until complete. The new bundle's CI
   Validate step will re-assert the JWT claims; if it fails again, the
   secret is still wrong and step 1 was misdiagnosed.
3. **Verify the new canary swap succeeded.** Watch `journalctl -u docker
   -n 100 | grep DEPLOY` for the `final_write_state 0 "ok"` line. If
   instead `canary_failed` appears, the new probe set caught the issue
   (success — the gap is closed).
4. **Verify recovery via Playwright MCP** against
   `app.soleur.ai/dashboard` from a signed-in fixture. The page must
   render Command Center, NOT the error boundary. Capture a screenshot
   for the postmortem. Also fetch the deployed bundle and re-run the
   Phase 1 step 3 inlined-JWT check — it must now pass.

### Phase 3 — Close the canary gap

The canary probes `/health` only at `infra/ci-deploy.sh:271`
(`curl -sf http://localhost:3001/health`). Per the deepen finding,
`middleware.ts:18-20` short-circuits `/health` BEFORE Supabase auth
runs AND the route never imports `@/lib/supabase/client`. So even if
the validator throws every time, `/health` returns 200.

**The harder part:** simply adding `/dashboard` to the probe set is
NOT sufficient. The validator throws at *client-bundle module load*,
which means SSR succeeds and HTTP-status probing returns 200. The
probe must verify the client bundle hydrates without error.

#### Probe-design decision matrix

| Probe approach | Catches client-only throws? | Complexity | Decision |
|---|---|---|---|
| HTTP status only (`-w '%{http_code}'`) | No — SSR returns 200 | Low | Reject |
| HTTP status + body sentinel grep | Partial — only catches errors that render error.tsx during SSR (e.g., a server-component throw); misses pure client-hydration throws | Low | Adopt as Layer 1 (cheap, high value for SSR throws) |
| Headless browser hydration check | Yes — runs the JS bundle | High (needs Chromium in canary container) | Adopt as Layer 2 (expensive, but the only way to catch this exact failure) |
| Inline JWT-claim assertion against the bundle | Yes — validates the inlined value matches Doppler | Medium | Adopt as Layer 3 (preflight Check 5 Step 5.4 already does this — wire into canary) |

#### Concrete implementation

1. **Layer 1 — HTTP+body probe** (always runs, after `/health`):
   ```bash
   # Probe /login (public route) — must 200 with non-empty body
   LOGIN_RESPONSE=$(curl -sf --max-time 5 -o /tmp/canary-login.html -w '%{http_code}' \
     http://localhost:3001/login)
   if [[ "$LOGIN_RESPONSE" != "200" ]] || [[ ! -s /tmp/canary-login.html ]]; then
     # rollback path
   fi
   # Probe /dashboard — accept 200|302|307 (middleware redirect to /login is healthy)
   DASH_RESPONSE=$(curl -s --max-time 5 -o /tmp/canary-dash.html -w '%{http_code}' \
     -L --max-redirs 0 \
     http://localhost:3001/dashboard)
   if [[ ! "$DASH_RESPONSE" =~ ^(200|302|307)$ ]]; then
     # rollback
   fi
   # Body-content rejection: never accept the error-boundary sentinel
   if grep -qF 'An unexpected error occurred' /tmp/canary-{login,dash}.html; then
     # rollback — error.tsx rendered during SSR
   fi
   ```
2. **Layer 3 — Inlined-JWT claim check** (cheap, runs after Layer 1):
   ```bash
   # Pull a chunk that imports lib/supabase/client and assert the inlined
   # anon key passes the same JWT-claims test that runs at module load.
   # This is preflight Check 5 Step 5.4 — wire it into ci-deploy.sh.
   bash plugins/soleur/skills/preflight/scripts/check-5-anon-key-shape.sh \
     http://localhost:3001 \
     || rollback
   ```
3. **Layer 2 — Headless browser** (deferred to a follow-up PR, tracked in
   Deferral Tracking). Requires either: (a) chromium in the canary
   container (image-size hit), or (b) a CI-runner-side Playwright probe
   that hits `localhost:3001` via a tunnel. Trade-off documented in
   the canary-probe-set runbook.

4. **Test fixtures** in `infra/ci-deploy.test.sh` (extend, do not fork):
   - Case A: `/health` 200 + `/login` 5xx → rollback.
   - Case B: `/health` 200 + `/login` 200 + `/dashboard` 5xx → rollback.
   - Case C: `/health` 200 + `/login` 200 + `/dashboard` 200 with
     error-boundary sentinel in body → rollback.
   - Case D: `/health` 200 + all probes 200 + Layer-3 inlined-JWT
     check fails → rollback.
   - Case E: All layers pass → swap.

5. **Document the canary contract** in
   `knowledge-base/engineering/ops/runbooks/canary-probe-set.md`. The
   runbook MUST explicitly call out the SSR/client divergence so future
   readers understand WHY Layer-3 (and eventually Layer-2) exists when
   HTTP probing seems sufficient.

### Phase 4 — Close the observability gap

#### Research Insights

`@/lib/client-observability` (verified at `lib/client-observability.ts:22-39`)
exports `reportSilentFallback(err: unknown, options: { feature: string;
op?: string; extra?: Record<string, unknown>; message?: string })` — same
shape as the server version. The shim avoids pulling pino into the
browser bundle.

`sentry.client.config.ts` is minimal (`dsn`, `environment`,
`tracesSampleRate: 0`). No `release`, no `dist`, no source-map config.
For `@sentry/nextjs@^10.46.0`, source-map upload is typically wired via
the `withSentryConfig` Next.js config wrapper. **Verify in Phase 4.4**
whether `next.config.ts` has `withSentryConfig` AND whether the
`SENTRY_AUTH_TOKEN` build secret is populated in CI — without both,
released stack traces will be unmappable.

1. **Migrate `app/error.tsx`** to import `reportSilentFallback` from
   `@/lib/client-observability` (instead of calling `@sentry/nextjs`
   directly). Tags: `feature: "dashboard-error-boundary"`,
   `op: "render"`. Extras: `digest`, `route` (window.location.pathname),
   `userAgent`. This standardizes the call shape and makes the event
   discoverable by the same Sentry filter as every other silent fallback.

   ```typescript
   // apps/web-platform/app/error.tsx
   "use client";
   import { useEffect } from "react";
   import { reportSilentFallback } from "@/lib/client-observability";

   export default function Error({
     error,
     reset,
   }: {
     error: Error & { digest?: string };
     reset: () => void;
   }) {
     useEffect(() => {
       reportSilentFallback(error, {
         feature: "dashboard-error-boundary",
         op: "render",
         extra: {
           digest: error.digest ?? null,
           route: typeof window !== "undefined" ? window.location.pathname : null,
           // Do NOT include error.message — may contain JWT preview from
           // validate-anon-key.ts. The Error object itself is captured;
           // Sentry's beforeSend in sentry.client.config.ts strips x-nonce
           // and cookie headers but does not redact message bodies.
         },
       });
     }, [error]);
     // …existing JSX preserved…
   }
   ```
2. **Add a route-segment `app/(dashboard)/error.tsx`** so dashboard-segment
   throws don't bubble to the root and the digest carries `segment:
   dashboard`.
3. **Decide on validator posture for `lib/supabase/client.ts`.** The
   throw-at-module-load is correct from a security standpoint (fail-closed
   on a malformed anon key — see PR #2975/#3007 rationale: a service-role
   paste would silently bypass RLS). Do NOT weaken the throw. Instead:
   wrap the assertion in a try/catch at the call site, emit
   `reportSilentFallback` to Sentry with full context (current claim
   shape, URL canonical first label) BEFORE re-throwing, and ensure the
   re-thrown error message does NOT leak the JWT preview into the
   client-visible boundary.
4. **Audit Sentry source-map upload** in CI. If absent, wire it into
   `reusable-release.yml` so stack traces from minified bundles are
   readable.
5. **Audit Sentry alerting rules.** Confirm an alert rule exists for
   `event.count > 10 in 1m` on `feature: "dashboard-error-boundary"`
   AND a generic alert on `feature: "supabase-validator-throw"`. If
   absent, create them via Sentry API or document the exact dashboard
   click-path (Sentry settings is not Terraform-controlled).
6. **Add a synthetic check** (Better Stack or equivalent) that hits
   `app.soleur.ai/dashboard` from an authenticated fixture every 5 min
   and pages on render-error-boundary detection. This is the last-line
   defense if Sentry and canary both miss again.

### Phase 5 — Preflight + retroactive gate application

Per AGENTS.md `wg-when-fixing-a-workflow-gates-detection`:

1. **Add Preflight Check 7** — "Canary probe set covers authenticated
   surface": runs `grep -c '/dashboard' apps/web-platform/infra/ci-deploy.sh`
   and asserts ≥ 1.
2. **Retroactively apply** the new canary probe to the case that exposed
   the gap (this incident). Verify by re-running the new ci-deploy.test.sh
   against a synthetic build that simulates the #3007-class throw — it
   must reject the canary swap.
3. **File a tracking issue** for any deferred remediation (synthetic
   check, Sentry alert rule, etc.) per AGENTS.md
   `wg-when-deferring-a-capability-create-a`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 1 diagnostic written to `dashboard-error-postmortem.md` with
      the confirmed root cause and the decision rationale.
- [ ] `app/error.tsx` uses `reportSilentFallback` (not direct Sentry call).
- [ ] `app/(dashboard)/error.tsx` exists with segment-scoped tagging.
- [ ] `infra/ci-deploy.sh` probes `/dashboard` AND `/login` after `/health`.
- [ ] `ci-deploy.test.sh` covers the three new failure modes (5xx
      /dashboard, error-boundary HTML, 5xx /login).
- [ ] `lib/supabase/client.ts` re-throws AND emits a Sentry event before
      throw; test asserts both happen (deterministic invocation, no LLM
      in the assertion path).
- [ ] Preflight Check 7 added; runs as part of `/soleur:preflight`.
- [ ] Learning file
      `2026-04-28-module-load-throw-collapses-auth-surface.md` written.
- [ ] PR body uses `Ref #3014` (this is an `ops-only-prod-write` plan;
      issue closure is a post-merge step per AGENTS.md
      `cq-ops-remediation-uses-ref-not-closes` precedent).

### Post-merge (operator)

- [ ] Doppler `prd` corrected (Phase 2.1) and prod container restarted
      (Phase 2.2).
- [ ] Playwright MCP run confirms `/dashboard` renders Command Center
      from a signed-in fixture; screenshot saved to postmortem runbook.
- [ ] Sentry alerting rules created (Phase 4.5).
- [ ] Synthetic check live (Phase 4.6).
- [ ] Postmortem runbook published; `gh issue close <N>` for tracking
      issue once all post-merge steps are green.
- [ ] Run `gh workflow run web-platform-release.yml` to verify the new
      canary probe set rejects a synthetic broken bundle (Phase 5.2).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Security (CISO).

### Engineering (CTO)

**Status:** reviewed (carry-forward from incident framing)
**Assessment:** Module-load throw in a client-bundle module imported by
every authenticated route is a single point of failure. The validator's
fail-closed posture is correct; the consumer's import surface is the
problem. Segment-scoped error boundaries + canary widening + observability
upgrade is the right four-layer remediation.

### Product (CPO)

**Status:** reviewed
**Assessment:** Single-user incident threshold — every authenticated
visitor sees the broken page. CPO sign-off required pre-`/work`. The
public site (login, marketing pages) was unaffected, which is the only
thing limiting the blast radius from "outage" to "post-auth outage". Time-
to-remediation matters more than scope of fix; Phase 2 is the user-impact
load-bearing step.

### Security (CISO)

**Status:** reviewed
**Assessment:** Do NOT weaken the validator throw — it's the security
load-bearing check that prevents a service-role paste from silently
bypassing RLS in the browser bundle. The remediation strengthens
observability around the throw, not the throw itself.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no new user-facing UI. The root error.tsx is unchanged
visually; the segment error.tsx renders the same boundary copy with a
narrower scope.
**Agents invoked:** none
**Skipped specialists:** none

## Test Scenarios

(Per AGENTS.md `cq-write-failing-tests-before` — TDD applies; tests RED
before implementation.)

1. `client-runtime-validator.test.ts` — module load with malformed JWT
   throws AND emits a Sentry event tagged `feature:
   "supabase-validator-throw"`. Assertion path is direct invocation, not
   LLM-mediated, per AGENTS.md
   `cq-when-a-plan-prescribes-testing-a-security-invariant`.
2. `ci-deploy.test.sh` — three cases: (a) /dashboard 5xx → rollback,
   (b) /dashboard 200 with error-boundary sentinel → rollback,
   (c) /login 5xx → rollback. Each must NOT swap canary to prod.
3. `dashboard-segment-error-boundary.test.tsx` — render-throw inside
   `app/(dashboard)/dashboard/page.tsx` is caught by
   `app/(dashboard)/error.tsx` (not the root error.tsx), and the Sentry
   event carries `segment: dashboard`.
4. Preflight Check 7 — `bash plugins/soleur/skills/preflight/scripts/check-7.sh`
   returns 0 on the current ci-deploy.sh and non-zero on a synthetic
   ci-deploy.sh with the /dashboard probe removed.

## Open Code-Review Overlap

Deepen-pass query attempted: `gh issue list --label code-review --state open --json number,title,body --limit 200`. The session shell does not have authenticated `gh` for this lookup at deepen-time. Marking `None known` and deferring the live query to the work-skill setup phase, where the canonical query MUST run before any file edits. If matches are returned at work-time, fold them in or document the disposition before proceeding.

## Risks

- **R0 (deepen-pass new): Phase 2 may not actually fix the symptom.**
  The validator is client-side only — values are inlined into the static
  bundle at BUILD time, not read from the runtime container. If the
  diagnosed root cause is "the bundle has a bad value baked in," then a
  Doppler correction + container restart does NOTHING for the in-flight
  poisoned bundle. The fix requires a NEW build with the corrected
  build-arg, then a deploy. Phase 2 must distinguish: (a) "Doppler is
  correct, the build picked up a wrong value via CI race" → re-run
  `web-platform-release.yml` from the current main; (b) "Doppler itself
  is wrong" → fix Doppler, then re-run release. Either path requires a
  new image tag. Do NOT just `docker restart`.
- **R1: Hot-fix concurrency.** Phase 2 (Doppler edit + new build trigger
  + canary swap) is a destructive prod write. Per AGENTS.md
  `hr-menu-option-ack-not-prod-write-auth`, each command requires explicit
  per-command ack before execution. Do NOT batch.
- **R2: Canary probe brittleness.** Adding `/dashboard` to the canary
  probe means an unauthenticated 307 must be the success signal. If
  Next.js ever changes the redirect status code (e.g. to 302), the
  probe breaks. Mitigation: probe asserts `status -in {200, 307, 302}`
  AND body does not contain the error-boundary sentinel.
- **R3: Sentry alert rule drift.** Sentry settings are not Terraform-
  controlled. The new alert rule could be deleted out-of-band.
  Mitigation: document the rule in the postmortem runbook and add a
  monthly drift check via `scheduled-cf-token-expiry-check`-style cron.
- **R4: Custom-domain ref skip.** The validator deliberately skips the
  URL/JWT-ref cross-check on `api.soleur.ai`. If Doppler `prd` is ever
  changed to a different custom domain, the skip set in
  `validate-anon-key.ts:37` (`CUSTOM_DOMAIN_HOSTS`) and the CI dig step
  in `reusable-release.yml` must be updated together. Add an AGENTS.md
  reference but no rule (this is discoverable via clear error).
- **R5: Race between canary and migrations.** Migrations run BEFORE
  deploy in `web-platform-release.yml`; a migration that breaks the
  app at runtime would still pass canary if `/health` doesn't exercise
  it. Out of scope for this PR; track as deferred via a follow-up issue.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This section is filled in.
- Per `cq-when-a-plan-prescribes-testing-a-security-invariant`, the
  Sentry-event-fires test (Test Scenario 1) MUST use direct module
  invocation, not a `query({ prompt })` LLM-mediated harness. The model
  can introspect or refuse and produce a green suite that proves
  nothing.
- Per `cq-ref-removal-sweep-cleanup-closures`, if Phase 4.1 removes any
  `useEffect` cleanup return from the migrated error.tsx, grep the
  ref name to ensure no orphaned cleanup-closure reference survives.
- Per the `wg-after-merging-a-pr-that-adds-or-modifies` workflow
  guidance, Phase 5.2's `gh workflow run web-platform-release.yml`
  must poll until completion and investigate any failures before ending
  the session.
- Per `hr-menu-option-ack-not-prod-write-auth`, every Phase 1 (read-only
  diagnosis) command that touches prod (Doppler reads, SSH reads) and
  every Phase 2 destructive write (Doppler set, docker restart) requires
  explicit per-command ack. The ack is per-command, not per-phase.
- Per the canary-network/probe addition, `curl` must include
  `--max-time 5` and `dig` (if used in the new probe set) must include
  `+time=2 +tries=1` per the new
  `cq-when-a-plan-prescribes-dig-nslookup-curl` learning.
- Sentry source-map verification (Phase 4.4) must include reading the
  released bundle's stack-trace-sourcemap binding, not just confirming
  the upload command exists in CI. A successful upload to a wrong
  release version still produces unreadable traces.

## Alternative Approaches Considered

| Approach | Why rejected | Tracking |
|---|---|---|
| Roll back PR #3007 entirely | The validator is security-load-bearing (catches service-role paste). Rollback would re-open a strictly worse hole. | N/A |
| Move validator to lazy-call (only when `createClient()` runs) | Defeats fail-fast; the throw would surface only on the first user interaction, which is later than module-load. Same blast radius, worse diagnostics. | N/A |
| Probe `/dashboard` with a real authenticated fixture | Requires injecting a test JWT into the canary container, which crosses the auth boundary and is a separate security review. Probing for 307 (the unauthenticated-redirect) is sufficient — it proves the layout module-loaded successfully. | Track as a deferred enhancement (synthetic auth fixture in canary). |
| Add a Cloudflare worker that detects error-boundary HTML in responses | Belt-and-suspenders, but adds CF complexity. Synthetic check (Phase 4.6) achieves the same with less infra. | Track as Post-MVP enhancement. |

## Deferral Tracking

Deferrals identified during deepen pass — file as GitHub issues at work-time
per AGENTS.md `wg-when-deferring-a-capability-create-a`:

- **D1 (Layer 2 canary headless-browser probe).** Phase 3's Layer 2
  (chromium-in-canary) is deferred to a follow-up PR. Re-evaluation
  criteria: another failure that Layer 1 + Layer 3 miss (e.g., a
  React Suspense boundary bug that only manifests post-hydration).
  Milestone: Post-MVP / Later.
- **D2 (Synthetic auth fixture).** Layer 2's full /dashboard render
  verification needs a test JWT injected into the canary container — a
  separate security review. Defer; track for the same Layer-2 follow-up.
- **D3 (CF worker for error-boundary HTML detection).** Belt-and-suspenders
  to the Phase 4.6 synthetic check. Deferred unless the synthetic check
  proves insufficient.
- **D4 (Sentry settings drift detection).** Sentry alert rules and
  source-map config are not Terraform-controlled. A monthly drift check
  cron (mirroring `scheduled-cf-token-expiry-check.yml`) would catch
  out-of-band rule deletion. Defer to a separate PR — out of scope here.

## References

- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact`
- AGENTS.md `hr-menu-option-ack-not-prod-write-auth`
- AGENTS.md `cq-ops-remediation-uses-ref-not-closes` (paraphrased from
  Sharp-edges)
- AGENTS.md `wg-when-fixing-a-workflow-gates-detection`
- PR #2975 — `validate-url.ts` precedent for the validator pattern
- PR #2994 — typed OAuth error classifier + Sentry mirror precedent
- PR #3007 — `validate-anon-key.ts` (the change under suspicion)
- `apps/web-platform/lib/supabase/client.ts:19-23` — module-load throw site
- `apps/web-platform/infra/ci-deploy.sh:271` — current canary probe
- `apps/web-platform/app/error.tsx` — current error boundary
- `apps/web-platform/server/observability.ts` — `reportSilentFallback`
- `apps/web-platform/lib/client-observability.ts` — client shim
