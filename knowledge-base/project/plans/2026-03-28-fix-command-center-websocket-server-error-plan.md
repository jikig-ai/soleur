---
title: "fix: command center WebSocket server error causing reconnect loop"
type: fix
date: 2026-03-28
---

# fix: Command center WebSocket server error causing reconnect loop

The command center chat interface throws a server error and gets stuck in "Reconnecting" state with a yellow dot indicator. The WebSocket connection appears to establish but then drops, triggering the exponential backoff reconnect loop.

## Root Cause Analysis

### Diagnostic Findings

1. **Server is healthy:** The `/health` endpoint returns 200 (verified via `curl`).
2. **WebSocket upgrade works:** Forcing HTTP/1.1, the server responds with `101 Switching Protocols` (verified via `curl --http1.1` with upgrade headers).
3. **CSP does NOT include explicit `wss:` for the app origin:** The `connect-src` directive is `'self' https://<supabase>.supabase.co wss://<supabase>.supabase.co`. While modern browsers (Chrome 125+, Firefox) treat `wss:` as matching `'self'` on `https:` pages, this is not guaranteed across all browsers and versions.
4. **Close code 4005 ("Internal error") routes correctly** after PR #1221: the client disconnects with reason "Server error" and does NOT reconnect. If the user sees "Reconnecting" (yellow dot), the close code is likely NOT 4005 -- it is 1006 (abnormal closure) or another transient code.
5. **The only server-side path that sends 4005** is the T&C version query failure in `ws-handler.ts` (line 425-428).

### Hypothesis Matrix

| # | Hypothesis | Symptoms Match | Diagnostic |
|---|-----------|---------------|------------|
| 1 | **CSP blocks `wss://` connection** -- `connect-src 'self'` does not match `wss://` in the user's browser | Yellow dot (reconnecting), no close code from server (browser blocks before connection) | Check browser console for CSP violation. Fix: add explicit `wss:` to `connect-src`. |
| 2 | **Server crashes during auth/T&C check** -- unhandled exception causes abnormal close (1006) | Yellow dot (reconnecting), no clean close code | Check Docker logs for unhandled exceptions. Fix: add catch-all error handling in the `wss.on("connection")` handler. |
| 3 | **Supabase `users` table query fails** -- `tc_accepted_version` query returns error, server sends 4005 | Should show "Server error" and disconnect (not reconnect) per PR #1221 fix. Does NOT match "Reconnecting" state. | Check Supabase dashboard for query errors. |
| 4 | **Agent SDK import crash** -- `@anthropic-ai/claude-agent-sdk` throws at import time or during `query()` | Server starts fine (health OK) but crashes when session starts -- user sees connection established then error | Check if error happens after `auth_ok` is sent (during `startAgentSession`). |

### Most Likely: Hypothesis 1 (CSP blocking `wss://`)

The CSP `connect-src` directive does not explicitly allow `wss://` connections to the app's own origin. While `'self'` is intended to cover same-origin connections, the CSP Level 3 specification defines `'self'` as matching the exact origin tuple `(scheme, host, port)`. For a page served over `https://app.soleur.ai`, `'self'` matches `https://app.soleur.ai` but NOT `wss://app.soleur.ai` because the schemes differ.

**Browser behavior varies:**

- Chrome 125+ (June 2024): treats `wss:` as matching `'self'` on `https:` pages (non-standard extension)
- Firefox: similar non-standard behavior
- Safari: historically stricter -- may block `wss:` under `'self'`-only `connect-src`
- Older Chromium builds: may not include the `wss:` matching extension

When CSP blocks the WebSocket connection, the browser fires `onerror` then `onclose` with code 1006 (abnormal closure). Since 1006 is not in `NON_TRANSIENT_CLOSE_CODES`, the client enters the reconnect loop -- matching the "Reconnecting" state with yellow dot.

### Contributing Factor: No server-side logging for diagnosis

The ws-handler logs auth failures and message handling errors, but there is no request-level logging that would show whether the connection attempt reaches the server at all. If CSP blocks the connection client-side, the server sees nothing.

## Proposed Fix

### 1. Add explicit `wss:` and `ws:` to CSP `connect-src` (`apps/web-platform/lib/csp.ts`)

Add `wss://` and `ws://` (for dev) as explicit connect-src sources for the app's own origin. This eliminates reliance on browser-specific `'self'` matching behavior.

**Current:**

```typescript
`connect-src 'self' ${supabaseConnect}`,
```

**Proposed:**

```typescript
const wsConnect = isDev ? "ws://localhost:3000" : `wss://${new URL(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://placeholder.supabase.co').hostname.replace(/\.supabase\.co$/, '')}.soleur.ai`;
```

Actually, the simpler and more correct approach: the app's own WebSocket URL is always same-origin (`wss://app.soleur.ai/ws`), so adding `wss:` scheme matching alongside `'self'` is the right fix. In CSP, a bare scheme source like `wss:` allows connections to any `wss://` URL. That is too broad. Instead, use the self-referential approach:

```typescript
// In production: wss://app.soleur.ai matches the page origin.
// 'self' SHOULD cover this per CSP3 but browser support is inconsistent.
// Explicit wss: same-host entry ensures cross-browser compatibility.
const wsConnect = isDev ? "ws:" : "wss:";
```

Wait -- `wss:` as a bare scheme allows connections to ANY `wss://` host, which is too permissive for a security header. The correct approach:

```typescript
// Derive the app's WebSocket origin from the page origin.
// In development: ws://localhost:3000
// In production: wss://app.soleur.ai (same host as the page)
// 'self' should cover same-origin wss:// but browser support varies.
```

The simplest correct fix: since `ws-client.ts` constructs the WebSocket URL from `window.location.host` (same origin), the CSP should use `'self'` for HTTP/HTTPS and add an explicit entry for the WebSocket scheme of the same host. But since we do not know the host at CSP generation time in the middleware (it varies by request), the most robust approach is to read the `Host` header from the request in the middleware and construct the `wss://` entry dynamically. However, this adds complexity.

**Simplest safe fix:** Use `wss:` scheme-only source in production. While this allows WebSocket connections to any `wss://` host, `connect-src` already has `'self'` which covers `https:` connections to the same origin. The only additional surface `wss:` adds is WebSocket connections -- and since the client only creates WebSocket connections to `window.location.host`, the practical security impact is minimal. Fetch/XHR to external hosts is still blocked by `'self'`.

**Even simpler and fully safe:** The middleware already has access to `request.nextUrl`, so we can derive the WebSocket origin:

```typescript
// In buildCspHeader, accept the app host:
const appWsOrigin = isDev
  ? "ws://localhost:3000"
  : `wss://${appHost}`;
```

Then in middleware.ts, pass `request.nextUrl.host` to the CSP builder.

### 2. Add CSP test for WebSocket same-origin coverage (`apps/web-platform/test/csp.test.ts`)

Add a test that verifies `connect-src` explicitly includes `wss:` for the app's own origin, preventing regression.

### 3. Verify the fix using Playwright (`apps/web-platform`)

After deploying, use Playwright to navigate to the command center, check browser console for CSP violations, and verify the WebSocket connection status transitions to "Connected" (green dot).

## Acceptance Criteria

- [ ] CSP `connect-src` includes an explicit `wss://` directive that covers the app's own WebSocket endpoint
- [ ] In development mode, CSP includes `ws://localhost:*` for local WebSocket connections
- [ ] The WebSocket connection to `/ws` is not blocked by CSP in any major browser (Chrome, Firefox, Safari)
- [ ] CSP test suite includes a test verifying WebSocket same-origin coverage
- [ ] The `StatusIndicator` shows "Connected" (green dot) after the fix is deployed
- [ ] No CSP violation errors appear in the browser console for WebSocket connections
- [ ] Existing CSP protections (script-src nonce, frame-src none, etc.) are not weakened
- [ ] Supabase `wss://` connection in `connect-src` is preserved

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side CSP bug fix for WebSocket connectivity.

## Test Scenarios

- Given a user on Chrome 125+, when they open the command center chat page, then the WebSocket connects successfully and the status shows "Connected"
- Given a user on Safari (latest), when they open the command center chat page, then the WebSocket connects successfully (Safari historically stricter on CSP `'self'` + `wss:`)
- Given a user on Firefox, when they open the command center chat page, then the WebSocket connects successfully
- Given the CSP `connect-src`, when a script attempts to connect to an external WebSocket host (e.g., `wss://evil.com`), then the connection is blocked by CSP
- Given the CSP `connect-src`, when Supabase client connects to `wss://<project>.supabase.co`, then the connection is allowed (existing behavior preserved)
- Given development mode (`isDev: true`), when the CSP is generated, then `ws://` scheme is included for local development (not `wss://`)

## Context

### Relevant Files

- `apps/web-platform/lib/csp.ts` -- CSP header builder (primary fix target)
- `apps/web-platform/middleware.ts` -- Middleware that generates CSP headers per-request (needs to pass host to CSP builder)
- `apps/web-platform/lib/ws-client.ts` -- Client-side WebSocket hook (constructs `wss://` URL from `window.location.host`)
- `apps/web-platform/server/ws-handler.ts` -- Server-side WebSocket handler (reference: close code definitions)
- `apps/web-platform/test/csp.test.ts` -- CSP test suite (needs new test for WebSocket coverage)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- Chat page with StatusIndicator (reference: reconnecting UI)

### Related Plans

- `2026-03-27-fix-chat-reconnecting-loop-plan.md` -- Previous fix for close code routing (PR #1221). That fix handles the case where the server sends a non-transient close code. This plan handles the case where the connection never succeeds in the first place.
- `2026-03-26-fix-csp-cloudflare-challenge-script-blocked-plan.md` -- Previous CSP issue with Cloudflare Bot Fight Mode scripts blocked by CSP on the docs site. Different surface but same CSP tightening trend.
- `2026-03-20-fix-nonce-based-csp-eliminate-unsafe-inline-plan.md` -- The original CSP implementation (PR #960) that introduced the `connect-src 'self'` without explicit `wss:`.

### Related Learnings

- `2026-03-17-websocket-cloudflare-auth-debugging.md` -- Three-layer WebSocket failure through Cloudflare (auth, middleware, keepalive). Documents that `curl` WebSocket upgrade does not work through HTTP/2 Cloudflare proxy.
- `2026-03-27-websocket-close-code-routing-reconnect-loop.md` -- Close code routing fix. Established the `NON_TRANSIENT_CLOSE_CODES` pattern.
- `2026-03-20-websocket-error-sanitization-cwe-209.md` -- Error sanitization in WebSocket messages.

### Implementation Notes

- The CSP is generated per-request in middleware.ts with nonce-based policy. The `buildCspHeader` function accepts `{ nonce, isDev, supabaseUrl }` and needs a new `appHost` parameter to construct the explicit `wss://` entry.
- The middleware has `request.nextUrl.host` available for deriving the WebSocket origin.
- The `connect-src 'self'` keyword is kept for HTTP/HTTPS coverage -- the `wss://` entry is additive, not a replacement.
- In development, `ws://localhost:3000` is needed (not `wss://`) because local dev uses HTTP.
- A bare `wss:` scheme source (without host) allows connections to ANY `wss://` host and should be avoided. Use `wss://<specific-host>` instead.

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
