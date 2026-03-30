---
title: "feat: production observability (Sentry, Better Stack, Pino, Telegram alerting)"
type: feat
date: 2026-03-28
---

# feat: Production Observability

## Overview

Add operational observability to the Soleur web platform (`app.soleur.ai`). Currently zero production monitoring exists — the CSP nonce bug (#1213) went live and undetected. The founder SSHes into the server to debug with rotating Docker logs that disappear within hours.

This plan implements: Pino structured logging, Sentry error tracking (server + client), CSP violation reporting via `report-uri`, an enhanced health endpoint with version/dependency checks, Better Stack uptime monitoring, Telegram alerting, and post-deploy version verification.

## Problem Statement

| Gap | Impact | Incident |
|-----|--------|----------|
| No error tracking | Client-side JS exceptions are invisible | CSP blocking all JS (#1213), undetected |
| No uptime monitoring | Server down = silent | No external check on `/health` |
| No structured logging | `console.*` with ad-hoc tags, rotates at 30MB | SSH debugging, evidence gone within hours |
| No deploy verification | No way to confirm correct version is running | `docker restart` doesn't apply new images (learning) |
| No alerting | No notifications reach the founder | Email gets buried, no mobile alerts |

## Proposed Solution

Layered incremental implementation in 4 phases, each independently committable and testable:

1. **Structured logging** — Pino replaces all `console.*` (foundation for everything else)
2. **Sentry integration** — `@sentry/nextjs` for full-stack error tracking + CSP `report-uri`
3. **Health endpoint + deploy verification** — enriched `/health` with version, deps, uptime
4. **External services** — Better Stack uptime, Telegram alerting, Sentry project setup

## Technical Approach

### Architecture

```
                                    +-----------------+
                                    |  Better Stack   |
                                    |  (uptime ping)  |
                                    +--------+--------+
                                             |
                                    HTTPS every 3min
                                             |
                                             v
+----------+    Cloudflare    +--------------+----------------+
|  Client  | ----Tunnel-----> |   HTTP Server (index.ts)      |
| Browser  |                  |                               |
|          | <-- Sentry SDK   |  Pino logger (JSON)           |
|          |     reports -->  |  Sentry @sentry/nextjs        |
|          | <-- CSP          |  Health: /health (enriched)   |
|          |   report-uri --> |                               |
+----------+   sentry.io     +------+--------+---------------+
                                     |        |
                                     v        v
                              +------+--+ +---+------+
                              | Supabase| | Sentry   |
                              | (health | | (errors  |
                              |  check) | |  + CSP)  |
                              +---------+ +----+-----+
                                               |
                                               v
                                         +-----+------+
                                         |  Telegram  |
                                         |  (alerts)  |
                                         +------------+
```

### Implementation Phases

#### Phase 1: Structured Logging (Pino)

Foundation layer. Replaces `console.*` calls across server and app files with structured JSON logging.

**Scope note:** `middleware.ts` runs in the Next.js Edge Runtime where Pino is not available (requires Node.js `stream`, `os` APIs). Its single `console.error` call is excluded from migration. `test/bash-sandbox.test.ts` is also excluded — test files keep `console.*`.

**Files to create:**

- `apps/web-platform/server/logger.ts` — Singleton Pino logger

```typescript
// server/logger.ts
import pino from "pino";

const isDev = process.env.NODE_ENV !== "production";

const logger = pino({
  level: process.env.LOG_LEVEL || (isDev ? "debug" : "info"),
  ...(isDev
    ? {
        transport: {
          target: "pino-pretty",
          options: { colorize: true, translateTime: "SYS:HH:MM:ss.l", ignore: "pid,hostname" },
        },
      }
    : {}),
  // Redact sensitive headers
  redact: ["req.headers['x-nonce']", "req.headers.cookie"],
});

export default logger;

// Child logger factory for tagged contexts
export function createChildLogger(context: string) {
  return logger.child({ context });
}
```

**Files to modify:**

| File | Changes | `console.*` count |
|------|---------|-------------------|
| `server/index.ts` | Import logger, replace calls | 4 |
| `server/ws-handler.ts` | Import child logger `ws`, replace calls | 21 |
| `server/agent-runner.ts` | Import child logger `agent`, replace calls | 17 |
| `server/workspace.ts` | Import child logger `workspace`, replace calls | 2 |
| `server/domain-router.ts` | Import child logger `domain`, replace call | 1 |
| `lib/auth/resolve-origin.ts` | Import logger, replace call | 1 |
| `lib/auth/validate-origin.ts` | Import logger, replace call | 1 |
| `app/(auth)/callback/route.ts` | Import logger, replace calls | 4 |
| `app/api/accept-terms/route.ts` | Import logger, replace calls | 2 |
| `app/api/keys/route.ts` | Import logger, replace call | 1 |
| `app/api/workspace/route.ts` | Import logger, replace call | 1 |
| `app/api/webhooks/stripe/route.ts` | Import logger, replace call | 1 |
| `package.json` | Add `pino`, `pino-pretty` (dev) | - |
| `build:server` script | Add `--external:pino` to esbuild | - |

**Excluded from migration:**

| File | Reason |
|------|--------|
| `middleware.ts` | Edge Runtime — Pino requires Node.js APIs |
| `test/bash-sandbox.test.ts` | Test file — keep `console.*` |

**Migration pattern:**

```typescript
// Before
console.log(`[ws] User ${userId} connected`);
console.error(`[ws] Auth failed:`, err);

// After
const log = createChildLogger("ws");
log.info({ userId }, "User connected");
log.error({ err }, "Auth failed");
```

**Log persistence note:** Structured logging improves log quality but does not solve log persistence — Docker's json-file driver still rotates at 30MB. Pino JSON output is still better for `docker logs` debugging (greppable, structured). A log drain (Better Stack log ingestion) can be added later without code changes — just pipe `docker logs` to the drain.

**Approach:** Migrate `ws-handler.ts` (21 calls) first and verify esbuild external works. Then migrate remaining files. This avoids breaking logging in all files simultaneously if esbuild has issues.

**Success criteria:**

- All `console.*` calls in server/ and app/ replaced with Pino (except Edge Runtime exclusions)
- JSON log output in production, pretty-print in dev
- `x-nonce` header redacted from all log output
- Existing tests pass

#### Phase 2: Sentry Integration (@sentry/nextjs)

Full-stack error tracking using the unified `@sentry/nextjs` package. CSP violation reporting via `report-uri` directive.

**Critical: custom server init pattern.** Next.js does NOT call `instrumentation.ts` `register()` when using a custom server (confirmed in Sentry v7-to-v8 migration docs). Server-side Sentry init must happen via direct import as the first line of `server/index.ts`. The `instrumentation.ts` file is kept only for the `onRequestError` export.

**Dependencies:**

```bash
npm install @sentry/nextjs
```

**Files to create:**

- `apps/web-platform/sentry.server.config.ts` — Server-side Sentry init

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  // Error capture only — no performance tracing at current scale.
  // Enable tracesSampleRate when investigating specific performance issues.
  tracesSampleRate: 0,
  beforeSend(event) {
    // Strip sensitive headers
    if (event.request?.headers) {
      delete event.request.headers["x-nonce"];
      delete event.request.headers.cookie;
    }
    return event;
  },
});
```

- `apps/web-platform/sentry.client.config.ts` — Client-side Sentry init

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0,
});
```

- `apps/web-platform/instrumentation.ts` — Next.js instrumentation hook

```typescript
import * as Sentry from "@sentry/nextjs";

export async function register() {
  // NOTE: register() is NOT called by Next.js when using a custom server.
  // Server-side Sentry.init() happens via direct import in server/index.ts.
  // This function is a no-op for our setup.
}

// Captures Next.js server component rendering errors
export const onRequestError = Sentry.captureRequestError;
```

- `apps/web-platform/app/global-error.tsx` — Root error boundary

```typescript
"use client";
import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

export default function GlobalError({
  error, reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => { Sentry.captureException(error); }, [error]);
  return (
    <html>
      <body className="bg-neutral-950 text-neutral-100 flex items-center justify-center min-h-screen">
        <div className="text-center">
          <h2 className="text-xl mb-4">Something went wrong</h2>
          <button onClick={reset} className="px-4 py-2 bg-neutral-800 rounded">Try again</button>
        </div>
      </body>
    </html>
  );
}
```

- `apps/web-platform/app/error.tsx` — App-level error boundary (intentionally near-identical to global-error.tsx — Next.js requires both)

```typescript
"use client";
import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

export default function Error({
  error, reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => { Sentry.captureException(error); }, [error]);
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-center">
        <h2 className="text-xl mb-4">Something went wrong</h2>
        <button onClick={reset} className="px-4 py-2 bg-neutral-800 rounded">Try again</button>
      </div>
    </div>
  );
}
```

**Files to modify:**

| File | Changes |
|------|---------|
| `server/index.ts` | Add `import "../sentry.server.config"` as FIRST import line |
| `next.config.ts` | Wrap with `withSentryConfig()` (see config below) |
| `lib/csp.ts` | Add `*.ingest.sentry.io` to `connect-src`, add `report-uri` directive |
| `test/csp.test.ts` | Update CSP assertions for Sentry domain and `report-uri` |
| `server/ws-handler.ts` | Add `Sentry.captureException()` in catch blocks (call site, not sanitizer) |
| `server/agent-runner.ts` | Add `Sentry.captureException()` in catch blocks |
| `package.json` | Add `@sentry/nextjs` |
| `Dockerfile` | Add `ARG NEXT_PUBLIC_SENTRY_DSN`, `ARG SENTRY_AUTH_TOKEN`, `ARG SENTRY_ORG`, `ARG SENTRY_PROJECT` (builder stage only) |
| `.env.example` | Add `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN` |
| `build:server` script | Add `--external:@sentry/nextjs` to esbuild |
| `.github/workflows/reusable-release.yml` | Add `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` to Docker build-args |

**Sentry init in `server/index.ts` (single init path):**

```typescript
// MUST be first import — before next, ws, or any app code.
// instrumentation.ts register() is NOT called by Next.js with custom servers.
import "../sentry.server.config";

import { createServer } from "http";
import next from "next";
// ... rest of imports unchanged
```

**`withSentryConfig()` in `next.config.ts`:**

```typescript
import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";
import { buildSecurityHeaders } from "./lib/security-headers";

const securityHeaders = buildSecurityHeaders();

const nextConfig: NextConfig = {
  output: undefined,
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  serverActions: {
    allowedOrigins:
      process.env.NODE_ENV === "development"
        ? ["app.soleur.ai", "localhost:3000"]
        : ["app.soleur.ai"],
  },
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default withSentryConfig(nextConfig, {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
  // Upload source maps for all client chunks
  widenClientFileUpload: true,
  // Delete source maps after upload — don't ship to users
  sourcemaps: { deleteSourcemapsAfterUpload: true },
  // Suppress noisy logs outside CI
  silent: !process.env.CI,
  disableLogger: true,
});
```

**Note on esbuild + source maps:** `withSentryConfig()` hooks into `next build` (Webpack) for source map upload. The custom server built by esbuild is separate — its stack traces are already readable in Node.js without source maps (no minification in the esbuild config). No additional source map upload needed for server code.

**CSP changes in `lib/csp.ts`:**

Add `report-uri` directive and Sentry ingest domain to `connect-src`. The `report-uri` sends CSP violations directly to Sentry even when JS fails to load — this is the mechanism that would have caught #1213.

```typescript
export function buildCspHeader(options: {
  nonce: string;
  isDev: boolean;
  supabaseUrl: string;
  appHost: string;
  sentryReportUri?: string;
}): string {
  // ... existing code ...

  const directives = [
    "default-src 'self'",
    `script-src ${scriptSrc}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${appWsOrigin} ${supabaseConnect} https://*.ingest.sentry.io`,
    "object-src 'none'",
    "frame-src 'none'",
    "worker-src 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
    ...(sentryReportUri ? [`report-uri ${sentryReportUri}`] : []),
  ];

  return directives.join("; ");
}
```

The `sentryReportUri` is constructed from the DSN at runtime in `middleware.ts` and passed to `buildCspHeader()`. Format: `https://<ORG_INGEST>.ingest.sentry.io/api/<PROJECT_ID>/security/?sentry_key=<PUBLIC_KEY>`. The `sentry_key` is the public key from the DSN — safe to include in headers.

**Sentry capture at call sites (NOT in error-sanitizer.ts):**

The `sanitizeErrorForClient()` function is a pure function (input -> output). Adding `Sentry.captureException()` inside it would create side effects and report non-error states (like "No active session") as errors. Instead, capture at the call sites in `ws-handler.ts` and `agent-runner.ts`:

```typescript
// In ws-handler.ts catch blocks:
import * as Sentry from "@sentry/nextjs";

try {
  // ... handler logic
} catch (err) {
  Sentry.captureException(err);
  const safeMessage = sanitizeErrorForClient(err);
  // ... send safeMessage to client
}
```

**Security constraints:**

- `x-nonce` header filtered in `beforeSend` callback (server config)
- Client-side config has no `beforeSend` — browser does not have access to `x-nonce` (server-injected request header)
- `agent-env.ts` allowlist must NOT include `SENTRY_DSN`
- Cookie headers stripped from Sentry events
- `SENTRY_AUTH_TOKEN` is a Docker build ARG in the builder stage only — not present in the runner image

**Success criteria:**

- Server-side errors captured in Sentry (unhandled rejections, WS handler exceptions)
- Client-side errors captured (JS exceptions, unhandled promise rejections)
- CSP violations reported to Sentry via `report-uri` directive
- Source maps uploaded for readable client-side stack traces
- No sensitive data leaks (x-nonce, cookies, BYOK key)

#### Phase 3: Enhanced Health Endpoint + Deploy Verification

Enrich `/health` from `{ status: "ok" }` to include version, dependencies, uptime, and memory. Replace the existing CI health verification step with a version-aware check.

**Files to modify:**

| File | Changes |
|------|---------|
| `server/index.ts` | Replace trivial health check with enriched version |
| `Dockerfile` | Add `ARG BUILD_VERSION` and `ENV BUILD_VERSION` |
| `.github/workflows/web-platform-release.yml` | Pass version to Docker build, replace health verification with version check |
| `.github/workflows/reusable-release.yml` | Pass `BUILD_VERSION` build-arg |

**Enhanced health endpoint (`server/index.ts`):**

```typescript
if (parsedUrl.pathname === "/health") {
  const supabaseOk = await checkSupabase();
  const healthy = supabaseOk;
  res.writeHead(healthy ? 200 : 503, { "Content-Type": "application/json" });
  res.end(JSON.stringify({
    status: healthy ? "ok" : "degraded",
    version: process.env.BUILD_VERSION || "dev",
    supabase: supabaseOk ? "connected" : "error",
    uptime: Math.floor(process.uptime()),
    memory: Math.floor(process.memoryUsage().rss / 1024 / 1024),
  }));
  return;
}
```

**Supabase connectivity check (not business table query):**

```typescript
async function checkSupabase(): Promise<boolean> {
  try {
    // Lightweight connectivity check — uses Supabase REST API health,
    // not a business table query (avoids RLS coupling and schema dependency).
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      {
        headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! },
        signal: AbortSignal.timeout(2000),
      }
    );
    return response.ok;
  } catch {
    return false;
  }
}
```

**CI version verification (replaces existing health check step):**

```yaml
- name: Verify deploy health and version
  env:
    VERSION: ${{ needs.release.outputs.version }}
  run: |
    for i in $(seq 1 12); do
      HEALTH=$(curl -sf "https://app.soleur.ai/health" 2>/dev/null || echo "")
      if echo "$HEALTH" | grep -q "ok"; then
        DEPLOYED_VERSION=$(echo "$HEALTH" | jq -r '.version // empty')
        if [[ "$DEPLOYED_VERSION" == "$VERSION" ]]; then
          echo "Deploy verified: version $VERSION running"
          exit 0
        fi
        echo "Version mismatch: expected $VERSION, got $DEPLOYED_VERSION (attempt $i/12)"
      fi
      sleep 10
    done
    echo "::error::Deploy verification failed after 120s"
    exit 1
```

**Success criteria:**

- `/health` returns version, supabase status, uptime, memory
- Returns 503 when Supabase unreachable
- CI verifies deployed version matches expected tag (replaces existing step)
- Docker healthcheck still works (checks for HTTP 200)

#### Phase 4: External Services Setup

No code changes. Account setup and configuration for Better Stack, Sentry project, and Telegram alerting.

**4.1: Sentry Project Setup**

- Create Sentry account/project via Playwright MCP
- Get DSN values for server and client
- Get Organization Auth Token for source map uploads (scopes: `project:releases`, `org:read`)
- Store in Doppler: `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`
- Add `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` as GitHub secrets for CI
- Construct `report-uri` URL from DSN and store as `SENTRY_CSP_REPORT_URI` in Doppler

**4.2: Better Stack Uptime Monitor**

- Create Better Stack account via Playwright MCP
- Create HTTP monitor: `https://app.soleur.ai/health`, 3-minute interval
- Configure alert policy: notify on 2 consecutive failures

**4.3: Telegram Alerting**

- Configure Sentry webhook integration to send alerts to Telegram
- Configure Better Stack notification channel to Telegram
- Test both alert paths with a synthetic error/downtime

**4.4: Expense and Legal Updates**

- Record Sentry and Better Stack in `knowledge-base/operations/expenses.md` (both EUR 0/month on free tiers)
- Flag for CLO: new sub-processors Sentry and Better Stack need privacy policy disclosure (#1048)

**Automation note:** All browser tasks in 4.1-4.3 use Playwright MCP. The only potential manual step is if Sentry or Better Stack require CAPTCHA during signup — in that case, Playwright drives to the CAPTCHA gate and hands off for that single interaction.

## Acceptance Criteria

- [ ] All `console.*` calls in server/ and app/ replaced with Pino (except Edge Runtime exclusions)
- [ ] Pino outputs JSON in production, pretty-print in dev
- [ ] `x-nonce` header never appears in logs or Sentry events
- [ ] Sentry captures server-side errors (unhandled rejections, WS exceptions)
- [ ] Sentry captures client-side errors (JS exceptions, unhandled promise rejections)
- [ ] CSP violations reported to Sentry via `report-uri` directive
- [ ] Source maps uploaded to Sentry for readable client-side stack traces
- [ ] `error.tsx` and `global-error.tsx` catch rendering errors and report to Sentry
- [ ] `/health` returns version, supabase status, uptime, memory
- [ ] `/health` returns 503 when Supabase is unreachable
- [ ] CI verifies deployed version matches expected tag
- [ ] Better Stack monitors `https://app.soleur.ai/health` every 3 minutes
- [ ] Sentry and Better Stack alerts route to Telegram
- [ ] All existing tests pass (CSP tests updated for Sentry domain and `report-uri`)

## Test Scenarios

- Given the server starts, when Pino is initialized, then logs output as JSON to stdout in production
- Given a client-side JS exception, when the error boundary catches it, then Sentry receives the event with a readable stack trace
- Given a CSP violation on the client, when the browser sends a `report-uri` POST, then Sentry captures the violation report
- Given the `x-nonce` header is present on a request, when a server error is sent to Sentry, then the header is stripped from the event
- Given Supabase is unreachable, when `/health` is called, then it returns HTTP 503 with `{ status: "degraded", supabase: "error" }`
- Given a successful deploy, when CI checks `/health`, then the version matches the release tag
- Given Better Stack detects 2 consecutive health failures, then a Telegram alert is sent
- Given a server-side unhandled rejection, when it occurs, then Sentry captures it with structured log context
- Given `middleware.ts` runs in Edge Runtime, then it uses `console.error` (not Pino) and errors are not captured by Sentry edge config

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Sentry client SDK blocked by CSP | Add `*.ingest.sentry.io` to `connect-src`. SDK is bundled via npm (no CDN `script-src` needed). `report-uri` captures violations even when JS SDK fails. |
| Source map upload fails in CI | Auth token as GitHub secret. `SENTRY_AUTH_TOKEN` in builder stage only (not in runner image). Fallback: server-side stack traces are readable without source maps (esbuild doesn't minify). |
| Pino migration breaks existing behavior | Migrate `ws-handler.ts` first (21 calls), verify esbuild external, then migrate remaining files. |
| Health check adds latency | Supabase REST API health check with 2s timeout. Does not query business tables. |
| Sentry free tier limit (5K errors/month) | Pre-revenue with zero users. Monitor usage in Sentry dashboard. |
| esbuild externals for Pino/Sentry | Both must be in `--external` flags. Verify with `ws-handler.ts` first. |
| `withSentryConfig()` + esbuild `.mjs` compilation | `withSentryConfig()` hooks into `next build` (Webpack), not esbuild. The esbuild step for `next.config.mjs` must add `--external:@sentry/nextjs` to avoid bundling the Sentry config wrapper. |
| `instrumentation.ts` `register()` not called with custom server | Server-side init via direct import in `server/index.ts`. `instrumentation.ts` kept only for `onRequestError` export. |

## Domain Review

**Domains relevant:** Engineering, Operations, Product

Carried forward from brainstorm `## Domain Assessments` (2026-03-28).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CSP changes required for client-side SDK. WebSocket observability needs custom instrumentation. Health endpoint should model telegram-bridge. OpenTelemetry deferred to Phase 4.

### Operations (COO)

**Status:** reviewed
**Assessment:** Sentry + Better Stack free tiers add EUR 0/month to burn. Each new vendor needs DPA review and expense tracking. Self-hosted not viable on CX33.

### Product (CPO)

**Status:** reviewed
**Assessment:** KPI metrics split from #1218 and deferred to Phase 3 with #1063. Operational observability belongs in Phase 2. Product analytics at 3.11.

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-28-production-observability-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-production-observability/spec.md`
- CSP implementation: `apps/web-platform/lib/csp.ts`
- Error sanitizer: `apps/web-platform/server/error-sanitizer.ts`
- Health endpoint: `apps/web-platform/server/index.ts:17-22`
- Telegram-bridge health model: `apps/telegram-bridge/src/health.ts`
- CSP nonce learning: `knowledge-base/project/learnings/2026-03-27-sign-in-bug-prevention-strategies.md`
- Docker restart learning: `knowledge-base/project/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md`

### External References

- Sentry Next.js Manual Setup: `docs.sentry.io/platforms/javascript/guides/nextjs/manual-setup/`
- Sentry v7-to-v8 Migration (custom server): `docs.sentry.io/platforms/javascript/guides/nextjs/migration/v7-to-v8/`
- Sentry Security Policy Reporting (CSP report-uri): `docs.sentry.io/security-legal-pii/security/security-policy-reporting/`
- Sentry Auth Tokens (scopes: project:releases, org:read): `docs.sentry.io/account/auth-tokens/`
- Pino (GitHub): `github.com/pinojs/pino`

### Related Issues

- #1218 — Production observability (this issue)
- #1213 — CSP nonce fix (motivating incident)
- #1063 — Product analytics instrumentation (Phase 3, deferred KPI scope)
- #1048 — Privacy policy updates (sub-processor disclosures for Sentry, Better Stack)
