# Learning: WebSocket through Cloudflare — three-layer failure

## Problem
Chat page WebSocket kept flipping between "Connected" and "Reconnecting" after deploying behind Cloudflare proxy. Initial diagnosis (idle timeout) was wrong — the real issue was that WebSocket connections never authenticated.

## Solution
Three fixes were needed, not one:

1. **Missing auth token** (root cause): `ws-client.ts` connected to `wss://host/ws` without a `?token=` param. The server requires `?token=<supabase_access_token>` for auth. Fix: fetch session token from Supabase client and append to URL.

2. **Middleware interception**: Next.js middleware caught `/ws` and redirected to `/login` (302/307) because WebSocket connections don't carry cookies the same way. Fix: add `/ws` to `PUBLIC_PATHS` in middleware.ts — the ws-handler already does its own auth.

3. **No keepalive**: Cloudflare terminates idle WebSocket connections after 100 seconds. Fix: server-side `ws.ping()` every 30 seconds with `clearInterval` on close.

## Key Insight
When debugging WebSocket issues behind a reverse proxy, check the full chain in order: (1) Does the upgrade reach the server? (2) Does auth pass? (3) Does the connection stay alive? Fixing layer 3 first (keepalive) while layers 1 and 2 were broken wasted two deploy cycles. The server's silent auth failure (close 4001 with no log) made diagnosis harder — adding a log line for failed auth would have caught this immediately.

**Process insight**: "Deployed, should be fixed" is not verification. Actual verification means: connect via Playwright, wait 10+ seconds, confirm server logs show the authenticated user ID, and confirm the status stays "Connected" without cycling.

## Session Errors
- Assumed Cloudflare idle timeout without verifying auth worked at all
- Deployed twice without real verification (told user "should be fixed")
- curl WebSocket upgrade doesn't work through HTTP/2 (Cloudflare) — need Playwright for real WS testing
- Server had no log for failed WebSocket auth — silent 4001 close made debugging harder

## Tags
category: runtime-errors
module: web-platform
