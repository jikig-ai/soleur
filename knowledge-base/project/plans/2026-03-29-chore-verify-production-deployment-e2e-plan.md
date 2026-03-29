---
title: "chore: verify production deployment end-to-end loop"
type: chore
date: 2026-03-29
deepened: 2026-03-29
---

# chore: verify production deployment end-to-end loop

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 5 (Known Issues, Test Scenarios, Implementation Phases, Dependencies, Session Persistence)
**Research sources:** codebase analysis (middleware.ts, csp.ts, ws-client.ts, api-messages.ts, callback/route.ts, dns.tf, tunnel.tf), 6 institutional learnings, Supabase/Cloudflare documentation

### Key Improvements

1. **Root cause identified for CSP localhost bug** -- `request.nextUrl.host` in Next.js middleware resolves to the custom server's bind address (`localhost:3000`) not the Cloudflare-forwarded Host header. Fix: use `request.headers.get('host')` or `request.headers.get('x-forwarded-host')` instead. The callback route already implements correct origin resolution via `resolveOrigin()` using forwarded headers.
2. **AC5 (session persistence) will fail** -- The chat page component does NOT fetch conversation history on mount. The server-side API exists (`GET /api/conversations/:id/messages` in `server/api-messages.ts`) but the client-side `useWebSocket` hook starts with empty messages array. Page refresh loses all messages. This is a missing feature, not a verification failure.
3. **Concrete auth bypass strategy** -- Supabase admin API (`generateLink` or `createUser` + `signInWithOtp`) is the correct approach. `SUPABASE_ACCESS_TOKEN` is available in Doppler `prd`. Detailed API calls documented below.
4. **Cloudflare Tunnel scope clarified** -- The tunnel serves only `deploy.soleur.ai` (webhook). App traffic at `app.soleur.ai` goes through a Cloudflare-proxied A record. This means the `Host` header IS forwarded correctly by Cloudflare proxy -- the issue is purely in how Next.js middleware reads it.

## Overview

Verify that app.soleur.ai is functional end-to-end by exercising every step of the user journey on production: signup, BYOK key entry, WebSocket connection, agent conversation, session persistence, and console error freedom. This is roadmap item 1.7 and a Phase 1 exit criterion.

All three dependency issues are resolved: #1044 (multi-turn, CLOSED), #1041 (mobile UI, CLOSED), #1042 (PWA, CLOSED).

## Problem Statement / Motivation

Phase 1 cannot exit without production verification. The platform has been developed and deployed incrementally, but no systematic end-to-end validation has been performed on the production environment. Known learnings from prior sessions (WebSocket auth through Cloudflare, BYOK key invalidation, CSP nonce propagation) suggest integration failures are likely to surface only in production.

The health endpoint currently returns `{"status":"ok","version":"0.8.6","supabase":"error"}` -- the Supabase "error" status indicates a potential connectivity issue that must be investigated.

## Proposed Solution

Use Playwright MCP to exercise the production user journey end-to-end, document findings, fix any blockers, and produce a verification report. The verification is structured as 6 acceptance criteria checks, each with deterministic pass/fail criteria.

## Technical Considerations

### Architecture

The production stack is: Next.js custom server (with WebSocket handler) running in Docker on Hetzner, fronted by Cloudflare Tunnel. Auth is Supabase magic link OTP. BYOK uses AES-256-GCM with per-user HKDF key derivation. WebSocket carries the agent conversation protocol.

### Known Issues from Research

1. **CSP `connect-src` contains `wss://localhost:3000` (ROOT CAUSE IDENTIFIED)** -- The production CSP header shows `connect-src 'self' wss://localhost:3000 ...`. Root cause: `middleware.ts` line 26 uses `request.nextUrl.host` to derive `appHost` for `buildCspHeader()`. In a Next.js custom server, `request.nextUrl` reflects the server's bind address (`localhost:3000`), not the client-facing hostname. Cloudflare proxy DOES forward the correct `Host: app.soleur.ai` header -- the issue is purely in how the middleware reads it.

   **Fix:** Replace `request.nextUrl.host` with `request.headers.get('x-forwarded-host') ?? request.headers.get('host') ?? request.nextUrl.host` in `middleware.ts`. The callback route (`app/(auth)/callback/route.ts`) already solves this correctly via `resolveOrigin()` in `lib/auth/resolve-origin.ts`, which reads `x-forwarded-host` with a fallback chain. The middleware should use the same pattern.

   **Impact:** Without this fix, browsers enforcing CSP will block WebSocket connections to `wss://app.soleur.ai/ws` because the CSP only allows `wss://localhost:3000`. Currently working because `'self'` in `connect-src` may match for same-origin WebSocket in some browsers, but this is not reliable across all browsers.

   **Verification:** After fix, `curl -s -I https://app.soleur.ai/signup | grep connect-src` should show `wss://app.soleur.ai` not `wss://localhost:3000`.

2. **Supabase health check returning "error"** -- The `/health` endpoint reports `supabase: "error"`. The health check in `server/index.ts` fetches `${NEXT_PUBLIC_SUPABASE_URL}/rest/v1/` with the anon key and a 2-second timeout. Possible causes: (a) `NEXT_PUBLIC_SUPABASE_URL` not set correctly in Docker runtime env, (b) Supabase project paused (free tier inactivity), (c) network issue between Hetzner and Supabase. Verify by curling the same endpoint from outside: `curl -s -H "apikey: <anon_key>" https://ifsccnjhymdmidffkzhl.supabase.co/rest/v1/`.

3. **WebSocket through Cloudflare** -- Per learning `2026-03-17-websocket-cloudflare-auth-debugging.md`, three layers needed fixing: auth token (`?token=` param), middleware interception (`/ws` in PUBLIC_PATHS), and keepalive (30s `ws.ping()`). All were fixed. The DNS record for `app.soleur.ai` uses `proxied = true` with an A record (not tunnel), so Cloudflare's WebSocket support applies. Cloudflare terminates idle WebSocket connections after 100 seconds -- the server's 30s ping interval provides adequate keepalive margin.

4. **Session cookie handling** -- Per constitution line 98, `NextResponse.redirect()` requires cookies set on the response object directly, not via `cookies()`. The callback route (`callback/route.ts`) correctly accumulates cookies in `pendingCookies[]` and applies them to the redirect response via `redirectWithCookies()`. Production verification needed to confirm cookies survive the Cloudflare proxy hop.

5. **AC5 will fail: chat page does not load message history (NEW FINDING)** -- The chat page (`dashboard/chat/[conversationId]/page.tsx`) does not fetch conversation history on mount. The `useWebSocket` hook initializes with `useState<ChatMessage[]>([])` -- empty array. The server-side API endpoint exists (`GET /api/conversations/:id/messages` in `server/api-messages.ts`) and returns message history from the `messages` table. But the client never calls it. On page refresh, all messages are lost. This means AC5 will document a **missing feature**, not a verification failure. The work to fix this would involve: (a) fetching `/api/conversations/${conversationId}/messages` in a `useEffect` on mount, (b) prepending historical messages to the `messages` state before WebSocket streaming begins.

### Relevant Files

- `apps/web-platform/middleware.ts` -- CSP, auth, T&C enforcement
- `apps/web-platform/lib/csp.ts` -- CSP header builder (`buildCspHeader`)
- `apps/web-platform/server/ws-handler.ts` -- WebSocket auth and session management
- `apps/web-platform/server/byok.ts` -- BYOK encryption/decryption
- `apps/web-platform/lib/ws-client.ts` -- Client-side WebSocket hook
- `apps/web-platform/app/(auth)/signup/page.tsx` -- Signup page
- `apps/web-platform/app/(auth)/setup-key/page.tsx` -- BYOK key entry
- `apps/web-platform/app/(auth)/callback/route.ts` -- Auth callback with routing logic
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` -- Repo connection flow
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- Chat interface
- `apps/web-platform/server/index.ts` -- Custom server with health endpoint
- `apps/web-platform/e2e/smoke.e2e.ts` -- Existing E2E tests (CSP, public pages, auth redirects)

### User Flow (Happy Path)

1. `/signup` -- Enter email, accept T&C checkbox, submit magic link
2. Email -- Click magic link
3. `/callback` -- Exchange code, provision workspace, redirect based on state
4. `/accept-terms` -- Accept T&C (if not accepted)
5. `/setup-key` -- Enter Anthropic API key, validate, encrypt, store
6. `/connect-repo` -- Connect GitHub repo (or skip)
7. `/dashboard` -- Landing page with domain leader cards
8. `/dashboard/chat/new?leader=cto` -- Start conversation, WebSocket connects, agent responds

## Acceptance Criteria

### Functional Requirements

- [ ] **AC1: Signup from mobile browser** -- Navigate to `https://app.soleur.ai/signup` with mobile viewport (375x812), enter email, accept T&C, submit. Verify magic link email is sent (status 200 from Supabase, "Check your email" confirmation displayed).
- [ ] **AC2: BYOK key entry and decryption** -- After auth, navigate to `/setup-key`, enter a valid Anthropic API key, submit. Verify key is validated (API call to Anthropic returns 200), encrypted, stored in `api_keys` table, and can be decrypted by the server to start an agent session.
- [ ] **AC3: WebSocket connection establishes and holds** -- Navigate to `/dashboard/chat/new`, verify WebSocket connects via `wss://app.soleur.ai/ws?token=...`, status indicator shows "Connected" (green dot), connection holds for 30+ seconds without cycling to "Reconnecting".
- [ ] **AC4: Agent responds within acceptable latency** -- Send a message ("What is your role?"), verify agent response stream begins within 10 seconds, stream completes with meaningful content (not error message).
- [ ] **AC5: Session persists across page refresh** -- After receiving agent response, refresh page (F5), verify conversation history is reloaded from Supabase, WebSocket reconnects, previous messages are visible.
- [ ] **AC6: No console errors on production build** -- Capture browser console across all pages in the flow. Verify zero `console.error` entries and zero CSP violation messages ("Refused to...").
- [ ] **AC7: Accept-terms page renders** -- After auth callback for a new user, verify `/accept-terms` page renders correctly with T&C content and accept button.
- [ ] **AC8: Connect-repo page renders and skip works** -- After BYOK setup, verify `/connect-repo` page renders and the skip/continue flow works (user can proceed to dashboard without connecting a repo).

### Non-Functional Requirements

- [ ] Health endpoint returns `supabase: "connected"` (investigate current "error" status)
- [ ] CSP `connect-src` contains `wss://app.soleur.ai` (not `wss://localhost:3000`)
- [ ] All pages render within 3 seconds on mobile viewport
- [ ] No mixed content warnings

## Test Scenarios

### AC1: Mobile Signup

- **Browser:** Navigate to `https://app.soleur.ai/signup` with viewport 375x812. Verify form renders: email input, T&C checkbox, "Sign up with magic link" button. Fill email, check T&C, submit. Verify "Check your email" confirmation appears. Take screenshot.
- Given a new email address, when submitting signup form on mobile viewport, then Supabase sends magic link email and confirmation UI is displayed
- Given T&C checkbox is unchecked, when clicking submit, then button is disabled (HTML `required` attribute)

### AC2: BYOK Key Entry

- **Browser:** Navigate to `https://app.soleur.ai/setup-key` (authenticated). Enter API key `sk-ant-...`. Submit. Verify "Key is valid. Redirecting..." message appears. Verify redirect to `/connect-repo`.
- **API verify:** `curl -s https://app.soleur.ai/health | jq '.supabase'` expects `"connected"`
- Given a valid Anthropic API key, when submitting on setup-key page, then key is validated via Anthropic API, encrypted with HKDF-derived per-user key, and stored
- Given an invalid API key, when submitting, then "Invalid API key" error is displayed

### AC3: WebSocket Connection

- **Browser:** Navigate to `/dashboard/chat/new`. Verify green "Connected" dot appears. Wait 30 seconds. Verify status remains "Connected" (no cycling).
- Given an authenticated user with a valid API key, when opening chat page, then WebSocket connects via `wss://app.soleur.ai/ws` with auth token, server responds with `auth_ok`, status shows "Connected"
- Given Cloudflare 100-second idle timeout, when no messages sent for 30 seconds, then server ping keeps connection alive

### AC4: Agent Latency

- **Browser:** In connected chat, type "What is your role?" and click Send. Verify assistant message bubble appears within 10 seconds with streaming text. Verify content is meaningful (contains domain-relevant text, not an error message).
- Given a connected WebSocket session, when sending a message, then `stream_start` is received within 10 seconds, followed by `stream` chunks, and `stream_end`

### AC5: Session Persistence

- **Browser:** After agent response, note the conversation URL (includes conversationId). Refresh page. Verify messages are still visible. Verify WebSocket reconnects (green dot).
- Given an existing conversation with messages, when page is refreshed, then conversation history loads from Supabase and WebSocket reconnects
- Given a page refresh during active streaming, when reconnecting, then previous messages are preserved
- **CONFIRMED: Chat page does NOT load history on mount.** The `useWebSocket` hook initializes with empty `messages` state. The REST API endpoint exists (`GET /api/conversations/:id/messages` in `server/api-messages.ts`) but the client never calls it. AC5 will fail and should be documented as a missing feature. File a GitHub issue for "feat: load conversation history on page mount" and milestone it to Phase 1 (it is part of multi-turn continuity). The fix involves adding a `useEffect` in the chat page that fetches `/api/conversations/${conversationId}/messages` on mount and prepends historical messages before WebSocket streaming begins.

### AC7: Accept-Terms Page

- **Browser:** After creating a test user via Supabase admin API, navigate to `/accept-terms`. Verify T&C content renders and accept button is present. Click accept. Verify redirect to `/setup-key`.
- Given a new user who has not accepted T&C, when navigating to any protected route, then middleware redirects to `/accept-terms`

### AC8: Connect-Repo Page

- **Browser:** After BYOK setup, verify redirect lands on `/connect-repo`. Verify page renders with repo connection options. Verify skip/continue flow proceeds to `/dashboard`.
- Given an authenticated user with a valid key but no connected repo, when landing on `/connect-repo`, then page renders and user can skip to dashboard

### AC6: Console Errors

- **Browser:** Throughout the entire flow (signup through chat), capture all console messages. Filter for `error` level and CSP violations ("Refused to"). Verify count is zero.
- Given the production build, when navigating through all pages, then no JavaScript errors or CSP violations appear in console

### CSP Regression

- Given production CSP headers, when checking `connect-src` directive, then it contains `wss://app.soleur.ai` (not `wss://localhost:3000`)

## Implementation Phases

### Phase 1: Investigation and Diagnostics (non-code)

1. **Supabase connectivity check:**

   ```bash
   # Get credentials from Doppler
   SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)
   ANON_KEY=$(doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain)
   # Direct REST API test
   curl -s -H "apikey: ${ANON_KEY}" "${SUPABASE_URL}/rest/v1/" | head -5
   ```

2. **CSP localhost confirmation** -- Already confirmed via `curl -s -I https://app.soleur.ai/signup | grep connect-src`. Root cause is `request.nextUrl.host` in middleware.ts. See Known Issue 1 for full analysis and fix.

3. **Sentry production errors:**

   ```bash
   SENTRY_TOKEN=$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
   SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain)
   SENTRY_PROJECT=$(doppler secrets get SENTRY_PROJECT -p soleur -c prd --plain)
   curl -s -H "Authorization: Bearer ${SENTRY_TOKEN}" \
     "https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/issues/?query=is:unresolved&limit=10" \
     | jq '.[].title' | head -10
   ```

4. **Health endpoint version check:**

   ```bash
   # Compare deployed version with latest release
   curl -s https://app.soleur.ai/health | jq '.version'
   gh release list --limit 1 --json tagName --jq '.[0].tagName'
   ```

### Phase 2: Fix Blockers (if any)

1. **CSP `appHost` fix (confirmed needed):**

   In `apps/web-platform/middleware.ts`, replace `request.nextUrl.host` with forwarded-host-aware resolution:

   ```typescript
   // Before (line 26):
   const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
   const cspValue = buildCspHeader({
     nonce,
     isDev: process.env.NODE_ENV === "development",
     supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
     appHost: request.nextUrl.host,  // BUG: returns localhost:3000

   // After:
   const appHost = request.headers.get("x-forwarded-host")
     ?? request.headers.get("host")
     ?? request.nextUrl.host;
   const cspValue = buildCspHeader({
     nonce,
     isDev: process.env.NODE_ENV === "development",
     supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
     appHost,
   ```

   This mirrors the `resolveOrigin()` pattern in `lib/auth/resolve-origin.ts` which already handles the same problem for the callback route.

2. **Supabase connectivity fix** -- Depends on Phase 1 diagnosis. If env var issue, fix in Doppler and redeploy. If project paused, resume via Supabase dashboard.

3. **Deploy fixes** -- Use the existing CI deploy workflow (`web-platform-release.yml`) or direct webhook. Health poll confirms deploy success.

### Phase 3: End-to-End Verification via Playwright MCP

Execute each acceptance criterion using Playwright MCP against `https://app.soleur.ai`:

1. AC6 (console errors) -- run first, captures baseline
2. AC1 (signup) -- use a fresh test email
3. AC7 (accept-terms) -- verify T&C page renders and accept flow works
4. AC2 (BYOK) -- use a real Anthropic API key from Doppler
5. AC8 (connect-repo) -- verify page renders and skip flow works
6. AC3 (WebSocket) -- connect and hold for 30 seconds
7. AC4 (agent latency) -- send message and measure response time
8. AC5 (session persistence) -- refresh and verify

### Auth Bypass Strategy for E2E Testing

AC1 tests the signup UI flow (form rendering, submission). For AC2-AC8, which require an authenticated session, use Supabase admin API to bypass email:

**Option A (recommended): Admin API `generateLink`**

```bash
SERVICE_ROLE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)

# Generate a magic link without sending email
curl -s -X POST "${SUPABASE_URL}/auth/v1/admin/generate_link" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"e2e-test@soleur.ai","type":"magiclink","options":{"redirectTo":"https://app.soleur.ai/callback"}}' \
  | jq '.action_link'
```

Then navigate Playwright to the returned `action_link` URL -- this completes the auth flow without email delivery.

**Option B: Admin API `createUser` + direct session**

```bash
# Create user with email_confirm: true (skip email verification)
curl -s -X POST "${SUPABASE_URL}/auth/v1/admin/users" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"e2e-test@soleur.ai","email_confirm":true}'
```

**Cleanup after tests:**

```bash
# Delete test user to keep production clean
USER_ID=$(curl -s ... | jq -r '.id')
curl -s -X DELETE "${SUPABASE_URL}/auth/v1/admin/users/${USER_ID}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}"
```

Per learning `2026-03-18-supabase-resend-email-configuration.md`, the Supabase project's Site URL is configured as `https://app.soleur.ai` and the redirect allow list includes `https://app.soleur.ai/**`. The `generateLink` approach uses these settings.

### Phase 4: Documentation

1. Record pass/fail for each AC in the GitHub issue
2. Screenshot key states
3. Close issue #1075 if all pass

## Dependencies and Risks

| Dependency | Status | Risk | Mitigation |
|---|---|---|---|
| Supabase connectivity | `error` on health | Medium | Direct REST API curl test in Phase 1. If paused, resume via dashboard. |
| CSP appHost resolution | Broken (`localhost:3000`) | High -- blocks WebSocket | Fix identified: use `x-forwarded-host` header in middleware.ts |
| Magic link email delivery | Depends on Supabase | Low | Bypassed by admin API `generateLink` |
| Session persistence (AC5) | Not implemented | Expected fail | File tracking issue; does not block other ACs |

All three code dependency issues are resolved: #1044 (CLOSED), #1041 (CLOSED), #1042 (CLOSED).

### Research Insights: Institutional Learnings Applied

| Learning | Relevance | Application |
|---|---|---|
| `2026-03-17-websocket-cloudflare-auth-debugging.md` | Direct | WebSocket verification checklist: (1) auth token present, (2) middleware not intercepting, (3) keepalive active. All three must pass. |
| `2026-03-18-typed-error-codes-websocket-key-invalidation.md` | Direct | If BYOK key is invalid during E2E, expect redirect to `/setup-key` via `key_invalid` error code. |
| `2026-03-18-supabase-resend-email-configuration.md` | Direct | Supabase Site URL is `https://app.soleur.ai`. Magic link redirect targets are correctly configured. Admin API `generateLink` uses these settings. |
| `2026-03-20-middleware-error-handling-fail-open-vs-closed.md` | Direct | If Supabase is down during E2E, middleware will fail-open (allow request through) for T&C check. Auth check (`getUser()`) will still fail correctly. |
| `2026-03-20-middleware-prefix-matching-bypass.md` | Indirect | `/ws` is in PUBLIC_PATHS -- verify no prefix collision (e.g., `/ws-evil` should not bypass auth). Already uses exact-or-prefix-with-slash matching. |
| `2026-03-20-nextjs-static-csp-security-headers.md` | Context | CSP evolved from static headers in `next.config.ts` to per-request nonce-based in middleware.ts. The static headers file (`security-headers.ts`) now contains only non-CSP headers (HSTS, X-Frame-Options, etc.). |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a production verification task with no architectural changes. The CTO-relevant findings are: (1) CSP `connect-src` contains `wss://localhost:3000` instead of `wss://app.soleur.ai` -- this is a production bug that may block WebSocket connections on strict CSP-enforcing browsers, (2) Supabase health returning "error" -- needs investigation before E2E verification can proceed. No new infrastructure, no schema changes, no new services.

### Product/UX Gate

Not applicable -- this verifies existing user flows, does not create new ones. Tier: NONE.

## References and Research

### Internal References

- `apps/web-platform/e2e/smoke.e2e.ts` -- Existing CSP and auth redirect E2E tests
- `knowledge-base/project/learnings/2026-03-17-websocket-cloudflare-auth-debugging.md` -- WebSocket through Cloudflare three-layer fix
- `knowledge-base/project/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md` -- BYOK key invalidation error handling
- `knowledge-base/product/roadmap.md` -- Phase 1 item 1.7

### Related Issues

- #1075 -- This issue
- #1044 -- Multi-turn conversation continuity (dependency, CLOSED)
- #1041 -- Mobile-first responsive UI (dependency, CLOSED)
- #1042 -- PWA manifest + service worker (dependency, CLOSED)
- #1045 -- Agent SDK version pinning (Phase 1, separate)
