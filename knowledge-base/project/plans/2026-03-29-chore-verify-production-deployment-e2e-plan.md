---
title: "chore: verify production deployment end-to-end loop"
type: chore
date: 2026-03-29
---

# chore: verify production deployment end-to-end loop

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

1. **CSP `connect-src` contains `wss://localhost:3000`** -- The production CSP header shows `connect-src 'self' wss://localhost:3000 ...` which is incorrect. The `appHost` parameter in `buildCspHeader()` comes from `request.nextUrl.host` in middleware.ts. Behind Cloudflare Tunnel, the custom server receives `localhost:3000` as the host, not `app.soleur.ai`. This needs investigation -- it may be that Cloudflare is not forwarding the `Host` header correctly, or the custom server is not respecting `X-Forwarded-Host`.

2. **Supabase health check returning "error"** -- The `/health` endpoint reports `supabase: "error"`. This could be a temporary connectivity issue or a misconfigured URL/key.

3. **WebSocket through Cloudflare** -- Per learning `2026-03-17-websocket-cloudflare-auth-debugging.md`, three layers needed fixing: auth token, middleware interception, and keepalive. All were fixed but need production re-verification.

4. **Session cookie handling** -- Per constitution line 98, `NextResponse.redirect()` requires cookies set on the response object directly, not via `cookies()`. The callback route already implements this correctly, but production verification is needed.

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

### AC6: Console Errors

- **Browser:** Throughout the entire flow (signup through chat), capture all console messages. Filter for `error` level and CSP violations ("Refused to"). Verify count is zero.
- Given the production build, when navigating through all pages, then no JavaScript errors or CSP violations appear in console

### CSP Regression

- Given production CSP headers, when checking `connect-src` directive, then it contains `wss://app.soleur.ai` (not `wss://localhost:3000`)

## Implementation Phases

### Phase 1: Investigation and Diagnostics (non-code)

1. Check Supabase "error" status -- query Supabase REST API directly to confirm connectivity
2. Investigate CSP `wss://localhost:3000` issue -- check Cloudflare tunnel config, `X-Forwarded-Host` header propagation
3. Check Sentry for recent production errors (`curl` with `SENTRY_API_TOKEN` from Doppler `prd` config)
4. Verify health endpoint version matches latest deploy

### Phase 2: Fix Blockers (if any)

1. Fix CSP `appHost` resolution if confirmed broken (likely needs `X-Forwarded-Host` or `Host` header from Cloudflare)
2. Fix Supabase connectivity if confirmed broken
3. Any other blockers found during Phase 1

### Phase 3: End-to-End Verification via Playwright MCP

Execute each acceptance criterion using Playwright MCP against `https://app.soleur.ai`:

1. AC6 (console errors) -- run first, captures baseline
2. AC1 (signup) -- use a fresh test email
3. AC2 (BYOK) -- use a real Anthropic API key from Doppler
4. AC3 (WebSocket) -- connect and hold for 30 seconds
5. AC4 (agent latency) -- send message and measure response time
6. AC5 (session persistence) -- refresh and verify

Note: AC1 requires magic link email. Options: (a) use Supabase admin API to create user directly, bypassing email, (b) use a real email and Playwright to open the email, (c) use Supabase's test OTP if configured. Supabase admin API (service role) is the most automatable approach.

### Phase 4: Documentation

1. Record pass/fail for each AC in the GitHub issue
2. Screenshot key states
3. Close issue #1075 if all pass

## Dependencies and Risks

| Dependency | Status | Risk |
|---|---|---|
| #1044 multi-turn | CLOSED | None |
| #1041 mobile UI | CLOSED | None |
| #1042 PWA | CLOSED | None |
| Supabase connectivity | `error` on health | Medium -- may block BYOK and auth |
| Cloudflare tunnel | Running | Low -- CSP host issue needs investigation |
| Anthropic API key | Available in Doppler `prd` | Low |
| Magic link email delivery | Depends on Supabase | Medium -- may need admin API bypass |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a production verification task with no architectural changes. The CTO-relevant findings are: (1) CSP `connect-src` contains `wss://localhost:3000` instead of `wss://app.soleur.ai` -- this is a production bug that may block WebSocket connections on strict CSP-enforcing browsers, (2) Supabase health returning "error" -- needs investigation before E2E verification can proceed. No new infrastructure, no schema changes, no new services.

### Product/UX Gate

Not applicable -- this verifies existing user flows, does not create new ones. Tier: NONE.

## Success Metrics

- All 6 acceptance criteria pass on production
- Zero console errors across the full user journey
- WebSocket holds for 30+ seconds without reconnection cycling
- Agent response begins streaming within 10 seconds
- CSP headers are correct for production (no localhost references)

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
