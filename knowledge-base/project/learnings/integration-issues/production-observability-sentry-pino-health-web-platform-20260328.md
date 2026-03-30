---
module: Web Platform
date: 2026-03-28
problem_type: integration_issue
component: tooling
symptoms:
  - "Client-side JS exceptions invisible — CSP nonce bug (#1213) went undetected"
  - "No structured logging — console.* with ad-hoc tags, Docker log rotation at 30MB"
  - "No uptime monitoring — server outages are silent"
  - "No deploy verification — docker restart doesn't apply new images"
resolution_type: tooling_addition
root_cause: incomplete_setup
severity: high
tags: [sentry, pino, observability, health-endpoint, better-stack, csp-report-uri, deploy-verification]
---

# Production Observability: Sentry, Pino, Health Endpoint, Better Stack

## Problem

Zero production monitoring on the Soleur web platform. Client-side JS exceptions were invisible, server errors disappeared with Docker log rotation, and no external service monitored uptime. The CSP nonce bug (#1213) went live and was only caught by manual debugging via SSH.

## Environment

- Module: Web Platform (apps/web-platform)
- Framework: Next.js 15 with custom HTTP server + esbuild
- Date: 2026-03-28

## Symptoms

- Client-side JS exceptions invisible to the team
- `console.*` logging with ad-hoc `[tag]` prefixes, no structured output
- Docker json-file driver rotates logs at 30MB — evidence disappears within hours
- No external health check on `/health` endpoint
- No way to confirm which version is running after deploy

## What Didn't Work

**Direct solution:** The implementation was a planned 4-phase incremental build, not a debugging session. Each phase was independently committable and testable.

## Session Errors

**Playwright MCP browser launch failure (3 attempts)**

- **Recovery:** User killed their running Chrome instance, clearing the singleton lock. Playwright then launched successfully.
- **Prevention:** When Playwright fails with "Opening in existing browser session," check for and remove `~/.cache/ms-playwright/mcp-chrome-*/SingletonLock` or ask the user to close Chrome. Consider documenting this in a Playwright troubleshooting learning.

**GitHub OAuth state expired after browser restart**

- **Recovery:** Retried "Sign in with GitHub" from scratch on the Sentry login page. Fresh OAuth state token succeeded.
- **Prevention:** When a browser restart is needed during an OAuth flow, always restart the OAuth flow from the beginning. Stale state tokens will fail with "Invalid request."

**Better Stack onboarding wizard blocked direct navigation**

- **Recovery:** Completed the onboarding wizard steps sequentially to reach the dashboard.
- **Prevention:** New SaaS accounts often require onboarding completion before direct URL navigation works. Start from the dashboard/home page rather than deep-linking on first use.

**npm install -g failed without sudo**

- **Recovery:** Used `npm install --prefix ~/.local` to install sentry-cli to a user-writable location.
- **Prevention:** Per AGENTS.md, the Bash tool has no sudo access. Always install CLI tools to `~/.local/bin` via `curl`/`tar` or `npm install --prefix ~/.local`.

**Wrong worktree identified for existing work**

- **Recovery:** Ran `git worktree list`, found work was in `production-observability` (not `feat-production-observability`), and switched.
- **Prevention:** When resuming work from a previous session, always run `git worktree list` and check recent commits in each candidate worktree rather than assuming a name.

**npm run build:server failed — wrong CWD**

- **Recovery:** Changed directory to `apps/web-platform` before running the script.
- **Prevention:** After context switches (reading plans, checking worktrees), verify `pwd` before running project-specific scripts.

## Solution

4-phase incremental implementation:

### Phase 1: Pino Structured Logging

Replaced all 54 `console.*` calls with Pino structured JSON logging. Created `server/logger.ts` singleton with child logger factory. Added `pino` to esbuild `--external`.

```typescript
// server/logger.ts — singleton with child logger factory
import pino from "pino";
const logger = pino({
  level: process.env.LOG_LEVEL || (isDev ? "debug" : "info"),
  ...(isDev ? { transport: { target: "pino-pretty" } } : {}),
  redact: ["req.headers['x-nonce']", "req.headers.cookie"],
});
export function createChildLogger(context: string) {
  return logger.child({ context });
}
```

### Phase 2: Sentry Integration

`@sentry/nextjs` v10.46.0 with custom server init pattern:

- `sentry.server.config.ts` — server-side init with `beforeSend` filtering (strips x-nonce, cookies)
- `sentry.client.config.ts` — client-side init
- `instrumentation.ts` — `onRequestError` export only (register() is no-op for custom servers)
- Direct import `import "../sentry.server.config"` as FIRST line in `server/index.ts`
- `withSentryConfig()` wrapping `next.config.ts` for source map upload
- CSP `connect-src` updated with `https://*.ingest.sentry.io`
- CSP `report-uri` directive for violation reporting even when JS fails to load
- `Sentry.captureException()` at catch sites in ws-handler and agent-runner
- `--external:@sentry/nextjs` in both esbuild scripts (server bundle + next.config.mjs)

### Phase 3: Enhanced Health Endpoint

```typescript
// Supabase connectivity check (2s timeout, REST API only)
async function checkSupabase(): Promise<boolean> { ... }

// Enriched /health response with version-aware deploy verification
if (parsedUrl.pathname === "/health") {
  const supabaseOk = await checkSupabase();
  res.writeHead(supabaseOk ? 200 : 503, { "Content-Type": "application/json" });
  res.end(JSON.stringify({
    status: supabaseOk ? "ok" : "degraded",
    version: process.env.BUILD_VERSION || "dev",
    supabase: supabaseOk ? "connected" : "error",
    uptime: Math.floor(process.uptime()),
    memory: Math.floor(process.memoryUsage().rss / 1024 / 1024),
  }));
}
```

CI deploy verification now checks version match (12 attempts x 10s = 120s).

### Phase 4: External Services

- Sentry project created via Playwright MCP (org: jikigai, project: soleur-web-platform)
- 6 secrets stored in Doppler, 4 in GitHub
- Better Stack uptime monitor on `app.soleur.ai/health` (3-min interval, email alerts)
- Expenses recorded (both EUR 0/month free tier)
- CLO flagged for privacy policy sub-processor disclosure (#1048)

## Why This Works

1. **Pino** provides structured JSON output greppable from `docker logs`, with context tags and sensitive header redaction
2. **Sentry** captures both server and client errors, including CSP violations via `report-uri` — the exact mechanism that would have caught #1213
3. **Custom server init** via direct import avoids the `instrumentation.ts` `register()` gap (Next.js doesn't call it for custom servers)
4. **Health endpoint** with version matching prevents the "docker restart doesn't apply new images" failure mode
5. **Better Stack** provides external uptime monitoring independent of the server itself

## Prevention

- When using `@sentry/nextjs` with a custom HTTP server, always init via direct import (not `instrumentation.ts` `register()`)
- Add `--external:@sentry/nextjs` to ALL esbuild commands (server bundle AND next.config.mjs compilation)
- CSP `report-uri` is the last-resort error signal — it fires even when the JS SDK is blocked by CSP
- `BUILD_VERSION` must be an ARG in the runner stage (not just builder) to be available at runtime
- For Sentry `beforeSend`, strip `x-nonce` and `cookie` headers to prevent sensitive data leaks

## Related Issues

- See also: [nonce-based-csp-nextjs-middleware](../2026-03-20-nonce-based-csp-nextjs-middleware.md) — CSP nonce pattern this builds on
- See also: [docker-healthcheck-fast-liveness-pattern](../2026-03-20-docker-healthcheck-fast-liveness-pattern.md) — Docker HEALTHCHECK pattern for the enriched endpoint
- See also: [csp-strict-dynamic-requires-dynamic-rendering](../2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md) — CSP strict-dynamic context
- GitHub: #1218 (production observability), #1213 (motivating CSP nonce incident), #1048 (privacy policy updates)
