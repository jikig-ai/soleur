---
title: Field Core Web Vitals land in Sentry via browserTracingIntegration pageload transactions, not a standalone vitals path or a first-party beacon
status: adopting
date: 2026-09-28
amends: none
supersedes: none
issue: 9178
related: [8985, 8978, 9034]
related_adrs: [ADR-031, ADR-067, ADR-253]
brand_survival_threshold: single-user incident
---

# ADR-258: Field Core Web Vitals land in Sentry via `browserTracingIntegration` pageload transactions, not a standalone vitals path or a first-party beacon

## Status

**Adopting — 2026-09-28 (#9178).** The decision is true of the client config
(`apps/web-platform/sentry.client.config.ts`) at merge; it is true of the
*telemetry* only after the next deploy. The status flips to `accepted` when the
follow-through probe `scripts/followthroughs/cwv-field-rum-9178.sh` reads
vital-bearing pageload transactions for `GET /dashboard` sessions in Sentry
within its post-deploy window.

## Context

Until this change the webapp had no field RUM at all: `sentry.client.config.ts`
set `tracesSampleRate: 0` and registered no vitals integration, so LCP, INP,
CLS, FCP and TTFB from real sessions were entirely dark. Every perf claim rested
on the synthetic `perf-probe.ts` — one headless shell on one machine — which
measured warm FCP 572 ms against a ≲500 ms acceptance criterion (#8978
post-deploy comment) without telling us anything about the user population. The
mount-fan-out work in the same issue (#8985 census) fixes the request count;
this decision fixes the measurement.

The mechanism is constrained by what the installed SDK actually does, verified
against `@sentry/browser` 10.59.0 source
(`build/npm/esm/dev/integrations/webVitals.js` `setup()`, plus
`types/integrations/webVitals.d.ts`), not against docs:

- Vitals attach to a **pageload transaction** as measurements through the SDK's
  `afterStartPageLoadSpan` / `spanEnd` hooks. No pageload span, no measurements —
  and only `browserTracingIntegration` creates pageload spans.
- The standalone `webVitalsIntegration` emits standalone spans **only** under
  `traceLifecycle: 'stream'` or `_experiments.enableStandaloneClsSpans` /
  `enableStandaloneLcpSpans`, and its vital-name union is `'cls' | 'inp' |
  'lcp'` — **FCP and TTFB have no standalone path at all**. The metric this
  issue exists to measure (FCP) is unreachable without tracing.

## Decision

1. **`Sentry.browserTracingIntegration()` in `sentry.client.config.ts`.** It
   auto-registers `webVitalsIntegration`; pageload/navigation transactions carry
   LCP/CLS/INP/FCP/TTFB as measurements into the existing Sentry edge (the EU/DE
   ingest endpoint, ADR-031 — no new vendor, no new store, no new Terraform).
2. **`tracesSampler` replaces `tracesSampleRate`, armed by a client-side probe
   marker.** The sampler returns `1.0` when `localStorage.getItem("soleur.perf-probe")
   === "1"` — `perf-probe.ts` arms it via `page.addInitScript` before navigation,
   because a browser-side sampler receives no request headers — and `0.1`
   otherwise. The 10% real-session rate is enough volume for p50/p75 vitals
   dashboards while bounding transaction ingest; probe runs sample fully so the
   lab measurement is unconditionally captured.
3. **The scrub boundary extends to the new event classes.** Transaction and span
   payloads bypass `beforeSend`, so the existing helpers
   (`scrubJwtFromEvent` / `stripUserContextFromEvent` / `stripPiiFromRecord`)
   are wired into `beforeSendTransaction` and `beforeSendSpan` (both present on
   the installed SDK). `sendDefaultPii` stays unset. A test asserts a captured
   transaction/vital payload carries no user id, email or IP after the chain —
   the same no-raw-id boundary the #8719 learning prescribes, applied to the new
   sinks.
4. **The recipe is encoded, not just shipped.** The Sentry-first recipe — with
   the standalone-`webVitalsIntegration` caveat and a PII-constrained beacon
   fallback spec for non-Sentry stacks — lives at
   `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` and is
   pointed at from `plan` Phase 2.9 and `spec-templates`, so the next
   Soleur-built webapp gets field CWV wiring in its plan rather than as a
   retrofit.

## Consequences

- **Field vitals become observable** (Sentry Performance → Web Vitals) for the
  first time; the FCP AC for #8978/#9178 is now measurable against the real
  session population, not only the lab probe.
- **Ingest volume rises** by ~10% of real pageload/navigation sessions plus
  full-sampling probe runs. Quota headroom against the project's transaction
  allocation is the open variable, checked during implementation; the descope
  lever is the sampler's fallthrough rate or per-route sampling.
- **The privacy posture is unchanged in kind.** The payload goes to the same
  EU-resident Sentry edge (Art. 30 PA8 §(e)) under the same scrub helpers; the
  new obligations are the two extra `beforeSend*` sinks, pinned by the payload
  test. No user identifier is ever sent — vitals are aggregate-grade telemetry,
  not per-user records.
- **Sampling means absence is not evidence.** A vital that never lands for a
  cohort may be unsampled rather than absent; dashboards and any follow-through
  reads must remember the 0.1 posture.

## Alternatives considered

| Option | Verdict | Why |
| --- | --- | --- |
| **A. `browserTracingIntegration` + probe-armed `tracesSampler`** | **Chosen** | Only mechanism that carries FCP/TTFB; reuses the ADR-031 vendor edge, the scrub helpers and the existing Sentry-as-IaC alerting surface. |
| **B.** Standalone `webVitalsIntegration()` without transaction tracing | Rejected | SDK-source verified: standalone CLS/LCP/INP spans require `traceLifecycle: 'stream'` or `_experiments` flags, and FCP/TTFB have no standalone path (`WebVitalName = 'cls'|'inp'|'lcp'`) — the metric this issue is about would stay dark. |
| **C.** First-party beacon (`useReportWebVitals`/`web-vitals` → `/api/vitals` → internal store) | Rejected | A new API route plus a new persistent store (GDPR/encryption-posture/RLS surface) to duplicate what the installed SDK already ships; Sentry is the established telemetry vendor (ADR-031). The beacon contract is still specified in the recipe as the non-Sentry-stack fallback. |
| **D.** `traceLifecycle: 'stream'` + standalone vital spans | Rejected for now | Experimental surface (`_experiments` flags + stream lifecycle) covering only the CLS/LCP/INP subset; revisit if sampled pageload transactions prove quota-expensive. |
| **E.** Lab-probe only (no field RUM) | Rejected | This is the pre-change state and the failure being fixed: one headless machine cannot represent the user population's vitals distribution. |

## Relationship to other ADRs

- **ADR-031** (Sentry as IaC, EU residency): this decision rides the existing
  `webapp -> sentry` edge — same DSN ingest host, same org, no new vendor or
  Terraform surface. The edge prose in `model.c4` gains the web-vitals payload
  class.
- **ADR-067** (SWR client cache): the sibling workstream in #9178 — its 2026-09-28
  amendment records the mount-fetch contract. Independent mechanism, shared
  issue: the dedup work shrinks the fan-out this RUM will now measure.
- **ADR-253** (bounded middleware legs): unrelated mechanism, shared goal —
  #8978's residual cold-tier bounds are what made the remaining FCP gap a
  client-mount problem worth measuring in the field.

## Diagram

No new element or relationship. The existing `webapp -> sentry` edge in
`knowledge-base/engineering/architecture/diagrams/model.c4` gains the payload
class: sampled pageload/navigation transactions carrying
LCP/CLS/INP/FCP/TTFB measurements via the `@sentry/nextjs` SDK
(`tracesSampler` 0.1 real sessions / 1.0 under the `soleur.perf-probe` marker).
