# Webapp Core Web Vitals Observability

Trigger: the plan's Files-to-Edit touch a browser-rendered webapp
(`apps/*/app/`, `pages/`, a client `Sentry.init`, a `next.config.*`), or
the feature description mentions `FCP`, `LCP`, `CLS`, `INP`, `TTFB`,
`Core Web Vitals`, `web vitals`, `field RUM`, `real-user monitoring`,
`first paint`, `page speed` (case-insensitive).

When triggered, the plan MUST wire **field** (real-user) Core Web Vitals
into the `## Observability` section — a synthetic lab probe is not a
substitute: it measures one machine on one network. The recipe below is
the default; a plan that deviates must say why in Alternatives.

## Why this exists

Synthetic probes cannot see the field distribution. #9178 / #8985: the
dashboard's only perf evidence was the lab `perf-probe` (one headless
shell, `x-perf-probe`-armed) while `sentry.client.config.ts` set
`tracesSampleRate: 0` — every real session's LCP/INP/CLS/FCP/TTFB was
dark, so the warm-FCP regression was measured on a machine that is not
the user population. The mechanism details below are verified against
the installed SDK source (`@sentry/browser` 10.59.0,
`build/npm/esm/dev/integrations/webVitals.js` + `types/integrations/
webVitals.d.ts`), not docs — re-verify against the installed version
before reusing them.

## Recipe 1 — Sentry installed (`@sentry/nextjs` or `@sentry/browser`)

Prefer this when the repo already vendors Sentry (our edge: ADR-031,
org `jikigai-eu` on the DE ingest cluster).

1. **Add `Sentry.browserTracingIntegration()` to `integrations`** in the
   client config. It auto-registers `webVitalsIntegration`; vitals are
   attached to the **pageload/navigation transaction** as measurements
   (LCP, CLS, INP, FCP, TTFB) via the SDK's `afterStartPageLoadSpan` /
   `spanEnd` hooks — which only fire because tracing creates a pageload
   span.
2. **Use `tracesSampler`, not `tracesSampleRate`** — the sampler lets a
   perf probe fully sample its own runs while real sessions stay cheap:

   ```ts
   tracesSampler: () => {
     // Storage getters can throw where cookies are disabled — the
     // floor (0.1) must be the failure mode, never an exception.
     try {
       return sessionStorage.getItem("soleur.perf-probe") === "1"
         ? 1.0
         : 0.1;
     } catch {
       return 0.1;
     }
   },
   ```

   The probe marker MUST be client-side state (`sessionStorage` —
   tab-scoped so it never outlives the probe session), armed via
   `page.addInitScript` **before** navigation. A header marker does
   not work: `tracesSampler` receives no request headers in the browser.
3. **Extend the scrub boundary to the new event classes.** Transaction
   and span payloads bypass `beforeSend`. Reuse the same scrub helpers
   (`scrubJwtFromEvent` / `stripUserContextFromEvent` / `stripPiiFromRecord`
   or their local equivalents) in `beforeSendTransaction` and
   `beforeSendSpan` — both hooks exist on the installed SDK
   (`options.d.ts`). `sendDefaultPii` stays unset. Add a test asserting a
   captured transaction/vital payload carries no `user` id, email, or IP
   after the scrub chain.
   Tracing also makes `request.url`/`request.query_string`/transaction
   names live — a substring scrub alone is insufficient: pageload URLs
   carry bearer-token tails (`/invite/<token>`, `/shared/<token>`) that
   are not JWT- or email-shaped. Port or share the server-side URL
   sanitizer (`lib/sentry-url-sanitize.ts` here: strip query/hash, reduce
   token-path prefixes, delete `query_string`, reduce transaction names)
   and wire `beforeBreadcrumb` — navigation `from`/`to` data attaches to
   every envelope. (This gap was the #9180 review P1.)

### The standalone-`webVitalsIntegration` caveat

`webVitalsIntegration()` on its own emits **standalone spans only for
CLS, LCP, INP** — the `WebVitalName` union is `'cls' | 'inp' | 'lcp'`,
and even those require `traceLifecycle: 'stream'` or the
`_experiments.enableStandaloneClsSpans` /
`enableStandaloneLcpSpans` flags. **FCP and TTFB have no standalone path
at all** — they exist only as measurements on a pageload transaction.
If the metric the plan exists to measure is FCP or TTFB, the pageload-
transaction arm (`browserTracingIntegration`) is not optional. Revisit
the streaming path only if sampled transactions prove quota-expensive —
it is an `_experiments` surface.

## Recipe 2 — non-Sentry stacks (beacon endpoint fallback)

When no Sentry SDK is installed, wire the `web-vitals` npm package to a
first-party beacon endpoint:

- **Client:** `onFCP/onLCP/onINP/onCLS/onTTFB` → `navigator.sendBeacon`
  to `/api/vitals` (beacon survives page unload; `fetch` does not).
- **Payload contract — PII fail-closed:** metric name, value, rating,
  navigation type, page path (template, not URL with params), device
  class, connection effectiveType. **Never** send user id, email, IP
  (the endpoint must not log client IPs), session id, or any free-text
  field. Honor `navigator.doNotTrack === "1"` and GPC by not sending.
- **Sampled:** client-side dice roll (e.g. 10%) before registering the
  observers; the probe arm overrides to 100% the same way as Recipe 1.
- **Storage:** the endpoint writes to the project's existing telemetry
  store; standing up a new persistent store for vitals is a GDPR/Art. 30
  surface and needs its own ADR — prefer emitting to the incumbent
  telemetry vendor over a new datastore.

## Sampling and quota

- Real sessions at `0.1` (10%) is the default posture — enough volume for
  p50/p75 vitals dashboards, bounded ingest spend. State the expected
  transaction volume against the project's Sentry quota in the plan's
  `## Observability` block; quota headroom is a plan-time check, not a
  post-deploy surprise.
- Probe-armed runs sample at `1.0` so the lab measurement is
  unconditionally captured — the marker costs nothing at probe volume.
- Lower the real-session rate before raising quota; the two levers are
  `tracesSampler`'s fallthrough rate and a per-route sampler (sample
  `/dashboard` pageloads at a higher rate than static pages if the plan
  is about one route).

## Verification

- **Plan-time:** a unit test asserting (a) `browserTracingIntegration`
  is in `integrations`, (b) the sampler returns `1.0` under the probe
  marker and the low rate otherwise, (c) a transaction payload survives
  the scrub chain with no PII keys.
- **Post-deploy:** the Sentry Web Vitals dashboard (Performance →
  Web Vitals) shows LCP/INP/CLS/FCP/TTFB for the route within 24 h; the
  plan enrolls a follow-through script that reads Sentry for
  vital-bearing pageload transactions rather than eyeballing the
  dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **Alerting:** vitals regressions are dashboard-grade, not page-grade —
  do not wire a paging alert on a single session's LCP; an aggregate
  p75 regression alert belongs in the project's alert IaC if the plan
  adds one.

## References

- Decision record: `knowledge-base/engineering/architecture/decisions/ADR-259-field-rum-cwv-via-sentry-webvitals.md`
- Installed-SDK source of truth: `apps/web-platform/node_modules/@sentry/browser/build/npm/esm/dev/integrations/webVitals.js` (`setup()`)
- Client config this recipe was extracted from: `apps/web-platform/sentry.client.config.ts`
- Mount-path defect class it pairs with: `apps/web-platform/test/dashboard-mount-fetch-dedup.test.tsx` (census guard; ADR-067 amendment 2026-09-28)
