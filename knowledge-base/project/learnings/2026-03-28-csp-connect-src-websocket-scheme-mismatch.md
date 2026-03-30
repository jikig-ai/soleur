---
title: "CSP connect-src 'self' does not cover WebSocket schemes"
date: 2026-03-28
category: runtime-errors
module: web-platform/csp
tags: [csp, websocket, connect-src, middleware, browser-compatibility]
symptoms: "Command Center stuck on 'Reconnecting' with yellow dot; WebSocket blocked by CSP"
severity: high
---

# Learning: CSP connect-src 'self' does not cover WebSocket schemes

## Problem

The Command Center chat interface was stuck in "Reconnecting" state with a yellow status dot. WebSocket connections to the server were being silently blocked. The client received close code 1006 (abnormal closure) on every attempt, which the reconnect logic treated as a transient failure, producing an infinite reconnect loop with exponential backoff.

## Root Cause

The CSP `connect-src` directive included `'self'` but no explicit WebSocket origins. Per the CSP specification, `'self'` resolves to the page's own origin scheme -- `https://app.soleur.ai` on an HTTPS page. WebSocket schemes (`wss://`, `ws://`) are distinct schemes that `'self'` does not cover.

MDN documentation explicitly confirms this browser compatibility gap: some browsers extend `'self'` to include `wss://` as a non-standard courtesy, but this behavior is unreliable across browsers and versions. When CSP blocks a WebSocket connection, the browser fires `CloseEvent` with code 1006 (abnormal closure) rather than surfacing a clear CSP violation. The client's `onclose` handler -- which routes on close codes (see `2026-03-27-websocket-close-code-routing-reconnect-loop.md`) -- correctly treated 1006 as transient, entering the reconnect loop. The reconnect logic was working as designed; the problem was upstream in CSP.

## Solution

Added an `appHost` parameter to the `buildCspHeader()` function in `lib/csp.ts`. The function now constructs host-specific WebSocket origins:

- **Production:** `wss://app.soleur.ai` from the host header
- **Development:** `ws://localhost:3000` from the host header

These are inserted into `connect-src` alongside the existing `'self'` and Supabase entries. The middleware passes `request.nextUrl.host` as `appHost`, which naturally handles both environments without conditional logic.

### Files Changed

- `apps/web-platform/lib/csp.ts` -- Added `appHost` parameter to `buildCspHeader()`, computed `appWsOrigin` variable (`wss://` or `ws://` based on dev mode), inserted into `connect-src`
- `apps/web-platform/middleware.ts` -- Pass `request.nextUrl.host` as `appHost` to `buildCspHeader()`
- `apps/web-platform/test/csp.test.ts` -- 3 new tests: production `wss://` origin present, dev `ws://` origin present, no bare `wss:` scheme without host; updated existing test fixtures

## Key Insight

CSP `'self'` is NOT a universal allowlist for same-origin connections. It matches the page origin's exact scheme -- `https://` on HTTPS pages, `http://` on HTTP pages. WebSocket schemes (`wss://`, `ws://`) are entirely different URI schemes that fall outside `'self'` in spec-compliant browsers. The fact that some browsers extend `'self'` to cover `wss://` as a convenience makes this bug intermittent and environment-dependent -- it works in Chrome DevTools but fails in Firefox, or works locally but fails in production, depending on browser version.

The debugging signal was the 1006 close code. RFC 6455 defines 1006 as "abnormal closure -- no close frame received." When a WebSocket fails at the transport layer (CSP block, network error, proxy timeout), the browser always reports 1006. If the server's close code routing is correct (sending typed 4xxx codes for application errors), then 1006 consistently appearing means the connection is being killed before the WebSocket handshake completes -- pointing to a network-layer or policy-layer blocker like CSP, CORS, or a proxy.

The pattern generalizes: any CSP-protected application using WebSockets, Server-Sent Events, or `fetch()` to non-HTTP schemes must explicitly list those schemes in `connect-src`. Relying on `'self'` to cover related schemes is a spec misunderstanding that produces intermittent, browser-dependent failures.

## Session Errors

1. **vitest binary not found via npx** -- `npx vitest run` failed because the `@rolldown/binding-linux-x64-gnu` native module was missing from the npx cache. Recovery: used `bun test` directly, which is this project's actual test runner. Prevention: Always use `bun test` for this project. The `package.json` scripts section is the source of truth for test commands, not assumptions about the test framework.

## Prevention

- When adding CSP `connect-src`, always include explicit WebSocket origins (`wss://host`, `ws://host`) -- never rely on `'self'` to cover WebSocket schemes
- When debugging WebSocket connections that fail with close code 1006, check CSP `connect-src` before investigating server-side issues -- CSP blocks produce 1006 with no server-side log entry
- When CSP works in one browser but fails in another, check for reliance on non-standard `'self'` extensions -- spec-compliant browsers are stricter
- Derive WebSocket origins from the same host header used by the HTTP request (e.g., `request.nextUrl.host`) to avoid hardcoded environment checks

## References

- Related learnings:
  - `2026-03-27-websocket-close-code-routing-reconnect-loop.md` -- close code routing that correctly handled 1006 as transient
  - `2026-03-20-nonce-based-csp-nextjs-middleware.md` -- the `buildCspHeader()` function modified in this fix
  - `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` -- prior CSP rendering issue
  - `2026-03-17-websocket-cloudflare-auth-debugging.md` -- earlier WebSocket debugging session
- [MDN: CSP connect-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/connect-src) -- documents `'self'` and WebSocket scheme behavior
- [RFC 6455 Section 7.1.5](https://datatracker.ietf.org/doc/html/rfc6455#section-7.1.5) -- close code 1006 definition
