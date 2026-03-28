# Production Observability Brainstorm

**Date:** 2026-03-28
**Issue:** #1218
**Branch:** production-observability
**Participants:** Founder, CTO, COO, CPO

## What We're Building

Operational observability for the Soleur web platform (`app.soleur.ai`). The platform currently has zero production observability — no error tracking, no uptime monitoring, no structured logging. The CSP nonce bug (#1213) went undetected until manual discovery. The founder SSHes into the server to debug, which is unsustainable.

**In scope (Phase 2):**

- Sentry error tracking (server + client) — free tier, 5K errors/month
- Better Stack uptime monitoring — free tier, 5 monitors
- Structured logging with Pino — replace all `console.*` calls
- Telegram bot alerting — route Sentry + Better Stack alerts to Telegram
- Enhanced health endpoint — dependency checks, version reporting
- Post-deploy smoke test gate — verify correct version deployed

**Out of scope (deferred to Phase 3 with #1063):**

- KPI metrics dashboards (sign-in success rate, time-to-dashboard, conversion)
- Product analytics (Plausible integration on app.soleur.ai)
- Synthetic monitoring (Checkly/Playwright browser checks)
- OpenTelemetry distributed tracing (Phase 4, when container-per-workspace lands)
- PostHog (consolidation option to revisit at Phase 3.11)

## Why This Approach

### Scope Narrowing Rationale

All three domain leaders (CTO, COO, CPO) independently recommended splitting #1218:

1. **Zero beta users = empty KPI dashboards.** Tracking sign-in success rate when nobody is signing in produces no actionable data. KPI metrics become meaningful in Phase 4 when real founders arrive.
2. **Operational vs. product observability are distinct concerns.** "Is the platform broken?" (Phase 2) vs. "Are users succeeding?" (Phase 3). The Phase 2 exit criteria are about security posture, not user success metrics.
3. **KPI scope overlaps with #1063** (Phase 3: product analytics instrumentation). Doing it now creates scope confusion between the two issues.
4. **The CSP bug was an operational failure**, not a product metrics failure. Sentry + uptime monitoring would have caught it. KPI dashboards would not.

### Tool Selection Rationale

**Sentry over Datadog:**

- Free tier (5K errors/month) vs. $31+/month minimum
- First-class Next.js support (`@sentry/nextjs`) vs. generic Node.js APM
- Purpose-built for error tracking vs. full APM platform (overkill for single-server pre-revenue)
- Datadog's strengths (APM, distributed tracing) overlap with Phase 4 OTel work

**Sentry full-stack (server + client) over server-only:**

- The motivating bug (#1213) was a client-side CSP failure — server-side Sentry alone wouldn't have caught it
- Client-side adds CSP changes (a few lines in `lib/csp.ts`) and source map config
- 80/20 rule inverted: client-side is where the critical gap is

**Better Stack over UptimeRobot:**

- Already a known subprocessor (Buttondown DPA)
- Adds log aggregation capability for future use
- Free tier covers 5 monitors with 3-minute checks

**Pino over Winston:**

- Faster (JSON serialization optimized for Node.js)
- Lower overhead in production
- Better ecosystem for structured logging (pino-http for Express)
- Simpler API

**Telegram over Discord/Email for alerting:**

- Founder already has telegram-bridge infrastructure
- Reaches mobile directly — Discord may be muted, email gets buried
- Sentry and Better Stack both support Telegram webhooks

### Implementation Approach: Layered Incremental

Each layer is independently testable and deployable:

1. **Structured logging (Pino)** — foundation layer, touches ~10 files
2. **Sentry server-side** — Express error handler, unhandled rejections
3. **Sentry client-side** — CSP additions, Next.js error boundaries, source maps
4. **Better Stack uptime** — external configuration, no code changes
5. **Telegram alerting** — webhook integration for Sentry + Better Stack
6. **Enhanced health endpoint** — dependency checks, version reporting
7. **Post-deploy smoke test** — CI workflow update to verify version

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Narrow #1218 to operational observability only | Zero users = empty KPI dashboards. Defer to Phase 3 with #1063. |
| 2 | Sentry (free tier) for error tracking | Free, first-class Next.js support, catches the exact class of bug that motivated this. |
| 3 | Full-stack Sentry (server + client) | The motivating bug was client-side. Server-only misses the primary failure mode. |
| 4 | Better Stack (free tier) for uptime | Known subprocessor, log aggregation for future, 5 monitors free. |
| 5 | Pino for structured logging | Faster than Winston, better JSON serialization, pino-http for Express. |
| 6 | Telegram bot for alerting | Existing infrastructure, reaches mobile, avoids email burial. |
| 7 | Layered incremental implementation | Each step independently testable. Safer for production infra changes. |
| 8 | Plausible subscription confirmed | Founder subscribed (EUR 9/month Growth plan). Recorded in expenses. |

## Open Questions

1. **Sentry DSN management:** Store in Doppler (`SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN`). Need to create Sentry project and get DSN before implementation.
2. **Source map upload strategy:** Sentry webpack plugin at build time vs. CLI upload in CI. The webpack plugin is simpler for Next.js.
3. **Health endpoint enrichment scope:** Which dependency checks? Supabase connectivity is the obvious one. Disk space? Memory? The telegram-bridge health endpoint is a good model.
4. **CSP report-uri:** Sentry supports a CSP report endpoint. Should we add `report-uri` directive to send CSP violations directly to Sentry? This is separate from the client-side SDK and catches violations even when JS fails to load.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Minimal viable observability is uptime + server Sentry + structured logging (1-2 days). CSP changes are required for any client-side SDK. WebSocket observability needs custom instrumentation. OpenTelemetry is premature for single-server architecture. The health endpoint should be enriched with dependency checks and version reporting (telegram-bridge is the model).

### Operations (COO)

**Summary:** Current burn is EUR 32.08/month — every new SaaS is proportionally large. Sentry free tier + Better Stack free tier adds EUR 0/month. Self-hosted tools are not viable on CX33 (8GB RAM). Plausible decision was overdue (now resolved — subscribed). Each new vendor needs DPA review and expense tracking.

### Product (CPO)

**Summary:** KPI metrics should be split from #1218. Zero users = empty dashboards. Operational observability ("is it broken?") belongs in Phase 2. Product analytics ("are users succeeding?") belongs in Phase 3 with #1063. The roadmap places product analytics at 3.11 — shipping KPI dashboards now contradicts sequencing.

## Technical Constraints

- **CSP is strict** — any client-side SDK needs explicit domain additions in `lib/csp.ts` and test updates in `test/csp.test.ts`
- **No Next.js error boundaries exist** — need to add `error.tsx`, `global-error.tsx` for Sentry to capture rendering errors
- **Docker logs rotate at 30MB** — evidence disappears within hours under load
- **Health endpoint skips CSP** — middleware already exempts `/health` from nonce generation
- **Agent subprocess environment is isolated** — `agent-env.ts` allowlist must not include Sentry DSN
- **Cloudflare Tunnel** — synthetic monitoring must target `app.soleur.ai` through the tunnel, not the server IP
- **`x-nonce` header** — must never be logged by observability tooling (request-only, security-sensitive)

## Cross-Domain Flags

- **CLO:** New sub-processor disclosures required for Sentry and Better Stack in privacy docs (in scope via #1048)
- **CFO:** Sentry and Better Stack free tiers add EUR 0/month. Plausible now EUR 9/month (recorded).
- **COO:** Follow credential monitoring pattern for new service tokens (Doppler, expiry monitoring)
