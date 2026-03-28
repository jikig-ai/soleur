---
title: "fix: command center WebSocket server error causing reconnect loop"
type: fix
date: 2026-03-28
deepened: 2026-03-28
---

## Enhancement Summary

**Deepened on:** 2026-03-28
**Sections enhanced:** 5 (Root Cause, Proposed Fix, Acceptance Criteria, Test Scenarios, Implementation Notes)
**Research sources used:** MDN `connect-src` docs (Context7), Next.js CSP guide (Context7), codebase learnings (5), security review, simplicity review

### Key Improvements

1. Confirmed root cause via MDN documentation: `connect-src 'self'` explicitly documented as NOT resolving to WebSocket schemes in all browsers
2. Replaced deliberative fix discussion with a single decisive implementation approach: pass `appHost` from middleware to CSP builder for host-specific `wss://` entry
3. Added concrete TypeScript implementation for `buildCspHeader` signature change and middleware integration
4. Identified that the Next.js official CSP examples also omit WebSocket coverage -- this is a common gap, not a project-specific oversight

### New Considerations Discovered

- MDN browser compatibility notes explicitly state: "`connect-src 'self'` does not resolve to websocket schemes in all browsers"
- The `buildCspHeader` function already takes per-request params (`nonce`, `supabaseUrl`) so adding `appHost` follows the established pattern -- no architectural change needed
- The existing `withCspHeaders()` wrapper and structural coverage test (every middleware return path carries CSP) means the fix cannot silently break other exit paths
- `request.nextUrl.host` includes the port when non-standard (e.g., `localhost:3000` in dev) which naturally handles the `ws://localhost:3000` case

# fix: Command center WebSocket server error causing reconnect loop

The command center chat interface throws a server error and gets stuck in "Reconnecting" state with a yellow dot indicator. The WebSocket connection appears to establish but then drops, triggering the exponential backoff reconnect loop.

## Root Cause Analysis

### Diagnostic Findings

1. **Server is healthy:** The `/health` endpoint returns 200 (verified via `curl`).
2. **WebSocket upgrade works:** Forcing HTTP/1.1, the server responds with `101 Switching Protocols` (verified via `curl --http1.1` with upgrade headers).
3. **CSP does NOT include explicit `wss:` for the app origin:** The `connect-src` directive is `'self' https://<supabase>.supabase.co wss://<supabase>.supabase.co`. While modern browsers (Chrome 125+, Firefox) treat `wss:` as matching `'self'` on `https:` pages, this is not guaranteed across all browsers and versions.
4. **Close code 4005 ("Internal error") routes correctly** after PR #1221: the client disconnects with reason "Server error" and does NOT reconnect. If the user sees "Reconnecting" (yellow dot), the close code is likely NOT 4005 -- it is 1006 (abnormal closure) or another transient code.
5. **The only server-side path that sends 4005** is the T&C version query failure in `ws-handler.ts` (line 425-428).

### Research Insights

**MDN documentation confirms the root cause** ([MDN: connect-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/connect-src)):

> "There is an important browser compatibility note regarding `connect-src 'self'`: it does not resolve to websocket schemes in all browsers."

This is an explicit, documented browser compatibility gap. The CSP specification defines `'self'` as the page origin `(scheme, host, port)`. For `https://app.soleur.ai`, `'self'` matches `https://app.soleur.ai` but the `wss://` scheme is a different scheme entirely. Some browsers extend `'self'` to cover `wss://` as a courtesy, but this is non-standard.

**Next.js official CSP examples also omit WebSocket coverage.** The Next.js docs show `connect-src 'self' https://...` without any `wss://` entry. This is a common gap in CSP configurations -- most tutorials and framework examples do not account for WebSocket connections.

### Hypothesis Matrix

| # | Hypothesis | Symptoms Match | Diagnostic |
|---|-----------|---------------|------------|
| 1 | **CSP blocks `wss://` connection** -- `connect-src 'self'` does not match `wss://` in the user's browser | Yellow dot (reconnecting), no close code from server (browser blocks before connection) | Check browser console for CSP violation. Fix: add explicit `wss:` to `connect-src`. |
| 2 | **Server crashes during auth/T&C check** -- unhandled exception causes abnormal close (1006) | Yellow dot (reconnecting), no clean close code | Check Docker logs for unhandled exceptions. Fix: add catch-all error handling in the `wss.on("connection")` handler. |
| 3 | **Supabase `users` table query fails** -- `tc_accepted_version` query returns error, server sends 4005 | Should show "Server error" and disconnect (not reconnect) per PR #1221 fix. Does NOT match "Reconnecting" state. | Check Supabase dashboard for query errors. |
| 4 | **Agent SDK import crash** -- `@anthropic-ai/claude-agent-sdk` throws at import time or during `query()` | Server starts fine (health OK) but crashes when session starts -- user sees connection established then error | Check if error happens after `auth_ok` is sent (during `startAgentSession`). |

### Most Likely: Hypothesis 1 (CSP blocking `wss://`)

The CSP `connect-src` directive does not explicitly allow `wss://` connections to the app's own origin. The MDN documentation explicitly warns that `'self'` does not resolve to WebSocket schemes in all browsers.

**Browser behavior varies:**

- Chrome 125+ (June 2024): treats `wss:` as matching `'self'` on `https:` pages (non-standard extension)
- Firefox: similar non-standard behavior
- Safari: historically stricter -- may block `wss:` under `'self'`-only `connect-src`
- Older Chromium builds: may not include the `wss:` matching extension

When CSP blocks the WebSocket connection, the browser fires `onerror` then `onclose` with code 1006 (abnormal closure). Since 1006 is not in `NON_TRANSIENT_CLOSE_CODES`, the client enters the reconnect loop -- matching the "Reconnecting" state with yellow dot.

### Contributing Factor: No server-side logging for diagnosis

The ws-handler logs auth failures and message handling errors, but there is no request-level logging that would show whether the connection attempt reaches the server at all. If CSP blocks the connection client-side, the server sees nothing.

## Proposed Fix

### 1. Add explicit `wss://` to CSP `connect-src` via `appHost` parameter (`apps/web-platform/lib/csp.ts`)

Add the app's own WebSocket origin as an explicit `connect-src` source. The `buildCspHeader` function already accepts per-request params (`nonce`, `supabaseUrl`), so adding `appHost` follows the established pattern.

**Why not bare `wss:` scheme?** A bare scheme source (`wss:`) allows WebSocket connections to ANY host, weakening the CSP. Using `wss://<specific-host>` restricts to same-origin WebSocket connections only.

**Why not hardcode `wss://app.soleur.ai`?** The middleware runs in both development (`localhost:3000`) and production (`app.soleur.ai`). Using the request's host dynamically handles both cases without conditional logic.

#### Updated `buildCspHeader` signature

```typescript
export function buildCspHeader(options: {
  nonce: string;
  isDev: boolean;
  supabaseUrl: string;
  appHost: string;  // NEW: e.g., "app.soleur.ai" or "localhost:3000"
}): string {
  const { nonce, isDev, supabaseUrl, appHost } = options;
  // ...existing supabaseConnect logic...

  // WebSocket origin for the app itself.
  // CSP 'self' does not resolve to wss:// in all browsers (MDN compat note).
  // Use ws:// in dev (HTTP) and wss:// in prod (HTTPS).
  const appWsOrigin = isDev ? `ws://${appHost}` : `wss://${appHost}`;

  const directives = [
    "default-src 'self'",
    `script-src ${scriptSrc}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${appWsOrigin} ${supabaseConnect}`,
    // ...rest unchanged...
  ];
}
```

#### Updated middleware call site (`apps/web-platform/middleware.ts`)

```typescript
const cspValue = buildCspHeader({
  nonce,
  isDev: process.env.NODE_ENV === "development",
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
  appHost: request.nextUrl.host,  // NEW: includes port when non-standard
});
```

**Note:** `request.nextUrl.host` returns `app.soleur.ai` in production and `localhost:3000` in development. It includes the port when non-standard, which naturally handles the dev case.

### 2. Add CSP test for WebSocket same-origin coverage (`apps/web-platform/test/csp.test.ts`)

```typescript
test("connect-src includes explicit wss:// for app WebSocket origin", () => {
  const csp = buildCspHeader({
    nonce: TEST_NONCE,
    isDev: false,
    supabaseUrl: "https://abc.supabase.co",
    appHost: "app.soleur.ai",
  });
  const connectSrc = parseCspDirective(csp, "connect-src");
  expect(connectSrc).toContain("wss://app.soleur.ai");
});

test("connect-src includes ws:// for dev WebSocket origin", () => {
  const csp = buildCspHeader({
    nonce: TEST_NONCE,
    isDev: true,
    supabaseUrl: "https://abc.supabase.co",
    appHost: "localhost:3000",
  });
  const connectSrc = parseCspDirective(csp, "connect-src");
  expect(connectSrc).toContain("ws://localhost:3000");
});

test("connect-src does not use bare wss: scheme (overly permissive)", () => {
  const csp = buildCspHeader({
    nonce: TEST_NONCE,
    isDev: false,
    supabaseUrl: "https://abc.supabase.co",
    appHost: "app.soleur.ai",
  });
  const connectSrc = parseCspDirective(csp, "connect-src");
  // Bare 'wss:' allows connections to ANY wss:// host
  expect(connectSrc).not.toMatch(/\bwss:\s/);
});
```

#### Research Insights: Test coverage

The existing CSP test suite already verifies Supabase `wss://` in `connect-src` and structural coverage of middleware exit paths (`withCspHeaders` wrapper). The new tests add WebSocket same-origin coverage specifically, preventing regression if the `appHost` parameter is removed in a future refactor.

The existing tests that call `buildCspHeader` need updating to include the new `appHost` parameter. The `prodCsp` and `devCsp` fixtures at the top of the test file need the param added.

### 3. Verify the fix using Playwright (`apps/web-platform`)

After deploying, use Playwright to navigate to the command center, check browser console for CSP violations, and verify the WebSocket connection status transitions to "Connected" (green dot).

#### Research Insights: Verification approach

Per the learning `2026-03-17-websocket-cloudflare-auth-debugging.md`: "curl WebSocket upgrade doesn't work through HTTP/2 (Cloudflare) -- need Playwright for real WS testing." The curl verification performed during diagnosis (HTTP/1.1 forced) confirms the server works, but real browser testing via Playwright is the only way to verify CSP does not block the connection.

Per the learning `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`: "A prior learning can be the root cause of a future bug." The 2026-03-20 CSP learning documented CSP migration without noting the WebSocket gap. This plan's fix and test prevent the same class of omission.

## Acceptance Criteria

- [ ] CSP `connect-src` includes an explicit `wss://` directive that covers the app's own WebSocket endpoint
- [ ] In development mode, CSP includes `ws://localhost:3000` for local WebSocket connections
- [ ] The WebSocket connection to `/ws` is not blocked by CSP in any major browser (Chrome, Firefox, Safari)
- [ ] CSP test suite includes a test verifying WebSocket same-origin coverage
- [ ] CSP test suite includes a negative test verifying bare `wss:` scheme is NOT used
- [ ] The `StatusIndicator` shows "Connected" (green dot) after the fix is deployed
- [ ] No CSP violation errors appear in the browser console for WebSocket connections
- [ ] Existing CSP protections (script-src nonce, frame-src none, etc.) are not weakened
- [ ] Supabase `wss://` connection in `connect-src` is preserved
- [ ] All existing CSP tests pass with updated `buildCspHeader` signature

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side CSP bug fix for WebSocket connectivity.

## Test Scenarios

- Given a user on Chrome 125+, when they open the command center chat page, then the WebSocket connects successfully and the status shows "Connected"
- Given a user on Safari (latest), when they open the command center chat page, then the WebSocket connects successfully (Safari historically stricter on CSP `'self'` + `wss:`)
- Given a user on Firefox, when they open the command center chat page, then the WebSocket connects successfully
- Given the CSP `connect-src`, when a script attempts to connect to an external WebSocket host (e.g., `wss://evil.com`), then the connection is blocked by CSP
- Given the CSP `connect-src`, when Supabase client connects to `wss://<project>.supabase.co`, then the connection is allowed (existing behavior preserved)
- Given development mode (`isDev: true`), when the CSP is generated, then `ws://localhost:3000` is included for local WebSocket connections

### Research Insights: Edge Cases

- **Port handling:** `request.nextUrl.host` includes the port when non-standard (e.g., `localhost:3000`). CSP `wss://localhost:3000` matches `wss://localhost:3000/ws` but NOT `wss://localhost/ws` or `wss://localhost:4000/ws`. This is correct -- it restricts to the exact origin.
- **Cloudflare proxy:** Cloudflare terminates TLS and proxies HTTP to the origin. The `request.nextUrl.host` reflects the external hostname (`app.soleur.ai`), not the internal origin. The `wss://app.soleur.ai` CSP entry is what the browser needs.
- **Custom domain support (future):** If the app ever supports custom domains, `request.nextUrl.host` would return the custom domain, and the CSP would automatically include the correct `wss://` entry for that domain. No additional work needed.
- **CSP `upgrade-insecure-requests` interaction:** The CSP includes `upgrade-insecure-requests`, which upgrades `ws://` to `wss://` on HTTPS pages. In production this is a no-op (client already uses `wss://`). In development over HTTP, `upgrade-insecure-requests` does not apply (only enforced on HTTPS pages). No conflict.

## Context

### Relevant Files

- `apps/web-platform/lib/csp.ts` -- CSP header builder (primary fix target: add `appHost` param, add `wss://` to `connect-src`)
- `apps/web-platform/middleware.ts` -- Middleware that generates CSP headers per-request (pass `request.nextUrl.host` to CSP builder)
- `apps/web-platform/lib/ws-client.ts` -- Client-side WebSocket hook (constructs `wss://` URL from `window.location.host`)
- `apps/web-platform/server/ws-handler.ts` -- Server-side WebSocket handler (reference: close code definitions)
- `apps/web-platform/test/csp.test.ts` -- CSP test suite (add WebSocket coverage test, update existing tests with `appHost` param)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- Chat page with StatusIndicator (reference: reconnecting UI)

### Related Plans

- `2026-03-27-fix-chat-reconnecting-loop-plan.md` -- Previous fix for close code routing (PR #1221). That fix handles the case where the server sends a non-transient close code. This plan handles the case where the connection never succeeds in the first place.
- `2026-03-26-fix-csp-cloudflare-challenge-script-blocked-plan.md` -- Previous CSP issue with Cloudflare Bot Fight Mode scripts blocked by CSP on the docs site. Different surface but same CSP tightening trend.
- `2026-03-20-fix-nonce-based-csp-eliminate-unsafe-inline-plan.md` -- The original CSP implementation (PR #960) that introduced the `connect-src 'self'` without explicit `wss:`.

### Related Learnings

- `2026-03-17-websocket-cloudflare-auth-debugging.md` -- Three-layer WebSocket failure through Cloudflare (auth, middleware, keepalive). Documents that `curl` WebSocket upgrade does not work through HTTP/2 Cloudflare proxy.
- `2026-03-27-websocket-close-code-routing-reconnect-loop.md` -- Close code routing fix. Established the `NON_TRANSIENT_CLOSE_CODES` pattern.
- `2026-03-20-websocket-error-sanitization-cwe-209.md` -- Error sanitization in WebSocket messages.
- `2026-03-20-nonce-based-csp-nextjs-middleware.md` -- CSP migration to per-request nonce in middleware. Established the `buildCspHeader` + `withCspHeaders` pattern this fix extends.
- `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` -- Documented how CSP gaps between middleware and rendering can cause silent failures. This fix addresses a CSP gap between middleware `connect-src` and client WebSocket connections.

### Implementation Notes

- The CSP is generated per-request in middleware.ts with nonce-based policy. The `buildCspHeader` function already accepts `{ nonce, isDev, supabaseUrl }` -- adding `appHost` is a minimal, backwards-compatible signature extension.
- The middleware has `request.nextUrl.host` available, which returns the external hostname with port when non-standard.
- The `connect-src 'self'` keyword is kept for HTTP/HTTPS coverage -- the `wss://` entry is additive, not a replacement.
- In development, `ws://localhost:3000` is needed (not `wss://`) because local dev uses HTTP.
- A bare `wss:` scheme source (without host) allows connections to ANY `wss://` host and must be avoided.
- The `withCspHeaders()` wrapper pattern and structural coverage test ensure all middleware exit paths carry the updated CSP.

### Diagnostic Commands for Verification

After deployment, verify with Playwright:

1. Navigate to `https://app.soleur.ai/dashboard/chat/new`
2. Check browser console for CSP violation errors
3. Verify StatusIndicator shows "Connected" (green dot)
4. Send a test message and verify response streams back

If server logs are needed:

```bash
ssh <server> "docker logs --tail 200 soleur-web-platform 2>&1 | grep -iE '(error|4005|4001|close)'"
```

## References

- [MDN: connect-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/connect-src) -- Browser compatibility note on `'self'` and WebSocket schemes
- [MDN: CloseEvent](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent) -- Close code 1006 (abnormal closure) behavior
- [Next.js CSP Guide](https://nextjs.org/docs/app/building-your-application/configuring/content-security-policy) -- Official CSP examples (notably missing WebSocket coverage)
- [W3C CSP Level 3](https://www.w3.org/TR/CSP3/) -- `'self'` keyword definition as origin tuple matching
