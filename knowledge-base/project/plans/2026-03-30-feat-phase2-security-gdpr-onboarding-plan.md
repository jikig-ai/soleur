---
title: "feat: Phase 2 security audit, GDPR compliance, and onboarding (beta gate)"
type: feat
date: 2026-03-30
issue: "#674"
milestone: "Phase 2: Secure for Beta"
deepened: 2026-03-30
---

# Phase 2: Security Audit, GDPR, Onboarding (Beta Gate)

## Enhancement Summary

**Deepened on:** 2026-03-30
**Sections enhanced:** 7 (all task groups)
**Research sources:** OWASP cheat sheets, MDN CORS spec, ws library docs,
Supabase admin API docs, 8 project learnings, plan review feedback

### Key Improvements

1. **Account deletion cascade order corrected** -- auth.users first
   (triggers FK cascade), workspace last (best-effort). Soft delete
   (`shouldSoftDelete: true`) does NOT trigger FK cascade; must use hard
   delete.
2. **WebSocket maxPayload must be reduced** -- ws library defaults to
   100 MiB, far too generous for chat messages. Set to 1 MiB.
3. **CORS must include `Vary: Origin`** -- required for correct CDN/proxy
   caching when Access-Control-Allow-Origin is not `*`.
4. **Session timeout must check readyState after async** -- existing
   TOCTOU learning applies to timeout handlers the same way it applies
   to auth handlers.
5. **Six project learnings directly applicable** -- CSP nonce rendering,
   WS close code routing, TOCTOU race, connect-src scheme mismatch,
   error sanitization, path traversal patterns.

### New Considerations Discovered

- Supabase `shouldSoftDelete: true` preserves the auth.users row (hashed
  ID) but does NOT trigger ON DELETE CASCADE on public.users -- must use
  `shouldSoftDelete: false` for GDPR full deletion
- CORS `Access-Control-Allow-Origin: *` cannot be used with credentials
  (cookies) -- must use specific origin with `Vary: Origin`
- ws library `maxPayload` default is 100 MiB -- set to 1 MiB for chat
- RFC 6455 close codes 4000-4999 are application-defined; existing close
  code routing in ws-client.ts must be extended for new timeout codes

## Overview

Phase 2 is the mandatory gate before inviting beta users to the Soleur cloud
platform (app.soleur.ai). It covers three pillars: **security hardening**
(OWASP top 10, CSP/CORS, session management, WebSocket expiry), **GDPR
compliance** (account deletion, data purge, API key rotation), and **UX
polish** (error/empty states, onboarding walkthrough, UX audit of Phase 1
screens).

No external user touches the platform until every must-pass gate clears.

Related: [#674](https://github.com/jikig-ai/soleur/issues/674) |
Milestone: Phase 2: Secure for Beta |
Depends on: Phase 1 blockers resolved (#667, #668, #670)

## Problem Statement / Motivation

The platform currently handles PII (email addresses), API keys (BYOK
encrypted with AES-256-GCM + HKDF), and conversation data. Five Phase 1
screens were built without design review. There is no account deletion
flow, no session timeout/WebSocket expiry, and no onboarding walkthrough.
Inviting founders without addressing these gaps creates legal liability
(GDPR Article 17), security exposure (OWASP), and a poor first impression
that poisons beta feedback.

The CPO assessment is unambiguous: "The platform must be functional and
secure before any founder touches it."

## Proposed Solution

Implement Phase 2 as **seven sequential task groups** ordered by dependency
and risk. Security audit findings from Task Group 1 may produce additional
remediation work that feeds into subsequent groups. The plan is structured
so each group produces a shippable commit.

### Task Groups

| # | Group | Priority | Est. Complexity |
|---|-------|----------|-----------------|
| TG-1 | Security audit (OWASP top 10 review) | P1 | High |
| TG-2 | CSP headers + CORS hardening | P1 | Medium |
| TG-3 | Session timeout + WebSocket expiry | P1 | Medium |
| TG-4 | User settings page (API key rotation + GDPR account deletion) | P1 | High |
| TG-5 | Error states + empty states | P2 | Medium |
| TG-6 | UX audit of Phase 1 screens | P2 | Medium |
| TG-7 | First-time onboarding walkthrough | P2 | Medium |

## Technical Considerations

### Architecture Impacts

- **User settings page** is a new route (`/dashboard/settings`) with
  sub-sections for API keys and account management. This is the first page
  with destructive server actions (key deletion, account deletion).
- **Account deletion** requires a Supabase Edge Function or API route that
  cascades through: conversations, messages, api_keys, users table rows,
  workspace filesystem, and Supabase auth.users entry. The `ON DELETE CASCADE`
  constraints on conversations/messages/api_keys handle DB cleanup, but
  workspace filesystem cleanup and auth.users deletion require server-side
  logic.
- **Session timeout** adds idle tracking to the WebSocket layer
  (`ws-handler.ts`). A new `IDLE_TIMEOUT_MS` constant triggers WebSocket
  close with a specific close code after inactivity.
- **Onboarding** is a lightweight client-side walkthrough (no external
  library) using a step-based overlay that highlights key UI regions.

### Security Considerations

#### Existing Security Posture (from codebase audit)

**Strong foundations already in place:**

- CSP with nonce + strict-dynamic in middleware.ts
- HKDF per-user key derivation for BYOK (byok.ts)
- Bubblewrap sandbox with filesystem deny lists (agent-runner.ts)
- Path traversal protection with symlink resolution (sandbox.ts)
- Rate limiting: 3-layer (IP connection throttle, pending auth limit,
  per-user session throttle) in rate-limiter.ts
- Error sanitization preventing internal details leaking (error-sanitizer.ts)
- CSRF protection via Origin header validation (validate-origin.ts)
- Security headers: HSTS, X-Frame-Options DENY, nosniff, COOP, CORP,
  Permissions-Policy, X-XSS-Protection: 0 (security-headers.ts)
- Env access defense-in-depth patterns in bash-sandbox.ts
- Tool path checking with deny-by-default (tool-path-checker.ts)

**Gaps to address in this phase:**

1. **No session timeout / WebSocket idle expiry** -- connections live
   forever once authenticated. OWASP recommends 15-30 min idle timeout
   for low-risk apps, 2-5 min for high-value. A 30-minute idle timeout
   is appropriate for this platform (users step away mid-conversation).
2. **No absolute session timeout** -- Supabase JWT expiry handles HTTP
   sessions, but WebSocket connections bypass JWT refresh. Add an absolute
   timeout (8 hours per OWASP guidance).
3. **`/proc` not in sandbox deny list** -- roadmap item 2.6 (CTO review).
   Currently `/proc` is in the `denyRead` list in agent-runner.ts sandbox
   config. Verify this blocks `/proc/self/environ` and all PIDs.
   **Update:** Reading the code, `/proc` IS already in the deny list
   (`denyRead: ["/workspaces", "/proc"]`). This task is already done.
   The bash-sandbox.ts also blocks `/proc/*/environ` patterns. Verify
   via test.
4. **No account deletion flow** -- GDPR Article 17 requires "without undue
   delay" (approximately 30 days). Need both UI and server-side cascade.
5. **No API key rotation** -- users cannot replace their BYOK key without
   manual DB intervention.
6. **CSP partially done** -- CSP is implemented with nonce + strict-dynamic
   but lacks `report-to` header for CSP violation reporting.
7. **CORS not explicitly configured** -- Next.js defaults apply. Need
   explicit CORS headers on API routes.

### Performance Implications

- Session timeout timers add negligible memory overhead (one `setTimeout`
  per connection).
- Account deletion is a background operation -- the UI shows immediate
  confirmation while cascading deletes run asynchronously.

### Attack Surface Enumeration

All code paths that handle auth, sessions, and data access:

| Surface | Files | Checked By |
|---------|-------|------------|
| HTTP auth | middleware.ts | Supabase getUser() |
| WebSocket auth | ws-handler.ts | Supabase getUser(token) |
| API key storage | api/keys/route.ts, byok.ts | Origin validation, auth |
| File access | sandbox.ts, sandbox-hook.ts, tool-path-checker.ts | isPathInWorkspace, PreToolUse hooks |
| Bash execution | bash-sandbox.ts, sandbox-hook.ts | Env access patterns, bubblewrap |
| Agent tool use | agent-runner.ts canUseTool | FILE_TOOLS, SAFE_TOOLS, deny-by-default |
| Conversation data | ws-handler.ts, agent-runner.ts | user_id ownership checks |
| Workspace isolation | workspace.ts | UUID validation, separate directories |
| Checkout flow | api/checkout/route.ts | Auth + Stripe session |
| Webhook | api/webhooks/stripe/route.ts | Stripe signature verification |
| T&C enforcement | middleware.ts, ws-handler.ts | tc_accepted_version check |

## Acceptance Criteria

### Security Audit (TG-1)

- [ ] OWASP top 10 review completed for all API routes and WebSocket handler
- [ ] Workspace isolation verified: user A cannot access user B's files or conversations
- [ ] BYOK key handling reviewed: no plaintext key in logs, no key in error messages
- [ ] Path traversal mitigations verified: symlink escape, `..` sequences, null bytes
- [ ] `/proc` deny verified in sandbox with test coverage
- [ ] WebSocket message size limit enforced (defense-in-depth against oversized payloads)
- [ ] No high or critical findings remain open

### CSP + CORS (TG-2)

- [ ] CSP `report-to` / `report-uri` headers configured (Sentry CSP reporting)
- [ ] CORS explicitly configured on all API routes (allow only app.soleur.ai origin)
- [ ] Existing CSP test suite passes with any additions
- [ ] `connect-src` verified to include only necessary WebSocket and API origins

### Session Timeout + WebSocket Expiry (TG-3)

- [ ] Idle timeout (30 min) closes WebSocket with code 4008 (or similar) and
  sends `session_ended` with reason `idle_timeout`
- [ ] Absolute timeout (8 hours) closes WebSocket regardless of activity
- [ ] Client receives a warning message 60 seconds before idle timeout
- [ ] Client can extend session by sending any message (resets idle timer)
- [ ] Disconnected sessions still honor the existing 30s grace period
- [ ] Test coverage for idle timeout, absolute timeout, and timer reset

### User Settings Page (TG-4)

- [ ] New route at `/dashboard/settings` with tabbed UI (API Keys, Account)
- [ ] API key rotation: user can submit a new key, old key is replaced
- [ ] API key deletion: user can remove their key entirely
- [ ] Account deletion: user confirms with email re-entry, then:
  - Supabase auth.users entry deleted (via admin API) -- triggers FK cascade
  - Conversations, messages, API keys cascade-deleted via FK constraints
  - HTTP session cookies cleared
  - Workspace directory removed (best-effort, cron cleanup as backup)
- [ ] Account deletion is irreversible and clearly communicated in UI
- [ ] Rate limit on account deletion API (prevent abuse)
- [ ] Test coverage for the full deletion cascade

### Error + Empty States (TG-5)

- [ ] Agent failure: meaningful error message with retry option
- [ ] Network loss: WebSocket reconnection with status indicator
- [ ] Rate limit hit: user-friendly message with retry-after countdown
- [ ] Empty dashboard: guidance for first-time users (not just blank page)
- [ ] Empty KB page: placeholder with explanation
- [ ] Empty chat: prompt suggestions visible
- [ ] Session expired: clear message with re-login link

### UX Audit (TG-6)

- [ ] All 10+ screens reviewed by ux-design-lead agent
- [ ] Critical usability issues documented and fixed
- [ ] Mobile responsiveness verified on all screens
- [ ] Accessibility basics: focus management, ARIA labels, keyboard navigation

### Onboarding Walkthrough (TG-7)

- [ ] First-time user sees a step-based walkthrough covering:
  1. Chat input and @-mention system
  2. Suggested prompts
  3. Organization/leader strip
  4. Navigation to KB and settings
- [ ] Walkthrough is dismissible and does not reappear after completion
- [ ] Completion state persisted (localStorage or DB flag)
- [ ] iOS PWA install guidance included as a step (per roadmap 2.11)

## Test Scenarios

### Security

- Given a user with workspace at `/workspaces/user-a`, when the agent
  attempts to read `/workspaces/user-b/file.txt`, then the sandbox denies
  access
- Given a symlink `../../../etc/passwd` inside workspace, when the agent
  reads it, then `isPathInWorkspace` returns false (resolves real path)
- Given a Bash command `cat /proc/self/environ`, when executed in the agent
  sandbox, then bubblewrap blocks access and bash-sandbox.ts denies it
- Given a BYOK key decryption error, when the error is sent to the client,
  then the message contains no key material or internal details

### Session Management

- Given an authenticated WebSocket with no messages for 30 minutes, when
  the idle timer fires, then the server sends `session_ended` with
  `reason: idle_timeout` and closes the connection with code 4008
- Given an authenticated WebSocket active for 8 hours, when the absolute
  timer fires, then the connection closes regardless of recent activity
- Given a user who sends a message at 29 minutes of idle, when the message
  is processed, then the idle timer resets to 30 minutes

### GDPR Account Deletion

- Given a user requests account deletion via `/api/account/delete`, when
  confirmed with email, then all conversations, messages, API keys, workspace
  files, and auth entry are removed
- Given a user requests deletion, when the workspace filesystem removal
  fails, then the error is logged but the database deletion proceeds
- Given a deleted user's ID, when querying any table, then zero rows are
  returned

### API Key Rotation

- Given a user with an existing API key, when they submit a new key via
  settings, then the old key is replaced and the new key is validated
- Given an invalid API key submission, when Anthropic validation fails,
  then the UI shows an error and the old key remains active

### Error States

- **Browser:** Navigate to `/dashboard`, disconnect network, attempt to
  send a message, verify reconnection indicator appears
- **Browser:** Navigate to `/dashboard/kb` with no KB artifacts, verify
  empty state placeholder renders
- **Browser:** Trigger rate limit (30+ sessions/hour), verify user-friendly
  rate limit message appears

### Onboarding

- **Browser:** Sign up as new user, verify walkthrough overlay appears
  on first dashboard visit
- **Browser:** Dismiss walkthrough, refresh page, verify it does not
  reappear
- **Browser:** Complete walkthrough on desktop, visit on mobile (PWA),
  verify completion persists

## Implementation Plan

### TG-1: Security Audit (OWASP Top 10 Review)

**Approach:** Systematic review of each OWASP top 10 category against the
existing codebase. This is a code review exercise, not a penetration test.

| OWASP Category | Status | Notes |
|----------------|--------|-------|
| A01: Broken Access Control | Review needed | Verify RLS policies, conversation ownership checks, workspace isolation |
| A02: Cryptographic Failures | Strong | AES-256-GCM + HKDF per-user keys, but verify no plaintext key logging |
| A03: Injection | Review needed | Agent Bash commands are sandboxed, but review all `execFileSync` calls in workspace.ts |
| A04: Insecure Design | Review needed | Review gate flow, session management gaps |
| A05: Security Misconfiguration | Partially done | CSP + security headers present, verify CORS, verify sandbox deny lists complete |
| A06: Vulnerable Components | Deferred to #1174 | Supply chain hardening is a separate issue |
| A07: Auth Failures | Review needed | Verify session fixation, brute force protection, token validation |
| A08: Data Integrity Failures | Review needed | Verify Stripe webhook signatures, SDK update verification |
| A09: Logging Failures | Review needed | Verify security events logged, no sensitive data in logs |
| A10: SSRF | Review needed | Agent network sandbox (`allowedDomains: []`), verify no server-side fetch with user input |

**Files to audit:**

- `middleware.ts` -- auth flow, redirect logic
- `ws-handler.ts` -- WebSocket auth, message routing
- `agent-runner.ts` -- canUseTool, sandbox config, key handling
- `server/workspace.ts` -- workspace provisioning, `execFileSync` calls
- `server/byok.ts` -- encryption/decryption
- `app/api/keys/route.ts` -- key storage endpoint
- `app/api/workspace/route.ts` -- workspace API
- `app/(auth)/callback/route.ts` -- OAuth callback
- All API routes under `app/api/`

**Deliverable:** Security audit findings document (inline in conversation
only per constitution rule -- never persist aggregated findings to files).
Any critical/high findings become immediate remediation tasks inserted
before TG-2.

#### Research Insights (TG-1)

**From project learnings:**

- **Path traversal (CWE-22):** Never use string prefix matching
  (`startsWith`) on raw paths. Always canonicalize with
  `fs.realpathSync()` first, append trailing `/` to prevent prefix
  collisions. Already fixed in `sandbox.ts` (learning: 2026-03-20).
- **Error sanitization (CWE-209):** Allowlist-with-fallback is the
  correct posture. Unknown errors automatically get the safe generic
  message. Already implemented in `error-sanitizer.ts` (learning:
  2026-03-20).
- **TOCTOU race in WS auth:** Any async operation between a timer-based
  deadline and a state mutation creates a TOCTOU window. Always check
  `ws.readyState` after every `await` before mutating shared state.
  Already fixed in auth handler (learning: 2026-03-20). Apply the same
  pattern to the new idle/absolute timeout handlers.
- **Symlink escape (CWE-59):** `resolveRealPath()` in `sandbox.ts`
  handles dangling symlinks, circular symlinks, and non-ENOENT errors.
  Verify test coverage includes these edge cases.

**WebSocket message size limit:**

- The `ws` library defaults `maxPayload` to 100 MiB (104,857,600 bytes).
  This is excessive for a chat application where messages are typically
  under 10 KB.
- Set `maxPayload: 1_048_576` (1 MiB) on the `WebSocketServer`
  constructor. The ws library automatically closes the connection with
  code 1009 (Message Too Big) when a message exceeds the limit.
- Implementation: add `maxPayload` to the `new WebSocketServer({ noServer: true })`
  call in `ws-handler.ts`.

```typescript
const wss = new WebSocketServer({
  noServer: true,
  maxPayload: 1_048_576, // 1 MiB -- defense-in-depth against oversized payloads
});
```

### TG-2: CSP + CORS Hardening

**Files to modify:**

- `lib/csp.ts` -- add `report-to` directive alongside existing `report-uri`
- `next.config.ts` -- add explicit CORS configuration via `headers()`
- `lib/security-headers.ts` -- verify no gaps

**Implementation:**

1. Add `Report-To` response header in middleware.ts with Sentry endpoint
2. Add explicit `Access-Control-Allow-Origin` for API routes
   (`app.soleur.ai` only, no wildcard)
3. Add `Access-Control-Allow-Methods` and `Access-Control-Allow-Headers`
4. Verify `connect-src` in CSP allows only the required WebSocket and
   Supabase origins
5. Add tests for CORS headers on API responses

#### Research Insights (TG-2)

**From project learnings:**

- **CSP connect-src and WebSocket schemes:** `'self'` does NOT cover
  `wss://` in all browsers (learning: 2026-03-28). The current
  `buildCspHeader()` already includes explicit `wss://` origins -- verify
  this is preserved when modifying CSP directives.
- **CSP strict-dynamic requires dynamic rendering:** The root layout
  must call `await headers()` or equivalent to force dynamic rendering.
  Already fixed (learning: 2026-03-27). Verify this is not regressed.
- **Forwarded host validation:** The `resolveOrigin()` function already
  validates `x-forwarded-host` to prevent CSP injection via spoofed
  headers (learning: 2026-03-29). Use the same validated origin for
  CORS `Access-Control-Allow-Origin`.

**CORS implementation details (from MDN CORS spec):**

- **Never use `Access-Control-Allow-Origin: *` with credentials.**
  Since Supabase auth uses cookies (`sameSite: lax`, `secure: true`),
  CORS must use specific origin, not wildcard.
- **Always include `Vary: Origin`** when ACAO is not `*`. This prevents
  CDN/proxy caching from serving a response with the wrong origin header.
- **Preflight caching:** Set `Access-Control-Max-Age: 86400` (24 hours)
  to reduce preflight overhead. Browsers cap this (Chrome: 2 hours,
  Firefox: 24 hours).
- **Handle OPTIONS explicitly** in API routes. Next.js does not
  auto-respond to preflight requests.

**Implementation pattern for Next.js CORS via headers():**

```typescript
// next.config.ts headers() addition for API routes
{
  source: "/api/:path*",
  headers: [
    {
      key: "Access-Control-Allow-Origin",
      value: "https://app.soleur.ai",
    },
    { key: "Access-Control-Allow-Methods", value: "GET, POST, DELETE, OPTIONS" },
    { key: "Access-Control-Allow-Headers", value: "Content-Type, Authorization" },
    { key: "Access-Control-Max-Age", value: "86400" },
    { key: "Vary", value: "Origin" },
  ],
},
```

**Note:** This is complementary to the existing Origin validation in
`validate-origin.ts`. CORS is browser-enforced (prevents cross-origin
JS from reading responses); Origin validation is server-enforced (rejects
requests from non-allowed origins regardless of browser behavior).

**Report-To header format:**

```typescript
// In middleware.ts, after CSP header
response.headers.set("Report-To", JSON.stringify({
  group: "csp-endpoint",
  max_age: 10_886_400,
  endpoints: [{ url: sentryReportUri }],
  include_subdomains: true,
}));
```

### TG-3: Session Timeout + WebSocket Expiry

**Files to modify:**

- `server/ws-handler.ts` -- add idle and absolute timeout logic
- `lib/types.ts` -- add new `WS_CLOSE_CODES` entries
- `lib/ws-client.ts` -- handle timeout close codes on client side

**Implementation:**

1. Add constants: `IDLE_TIMEOUT_MS = 30 * 60 * 1_000` (30 min),
   `ABSOLUTE_TIMEOUT_MS = 8 * 60 * 60 * 1_000` (8 hours),
   `IDLE_WARNING_MS = 60 * 1_000` (1 min before expiry)
2. After auth success in `wss.on("connection")`, start both timers
3. On any client message, reset the idle timer
4. At `IDLE_TIMEOUT_MS - IDLE_WARNING_MS`, send a `session_expiring`
   message to the client
5. At `IDLE_TIMEOUT_MS`, close with code 4008 and reason `idle_timeout`
6. At `ABSOLUTE_TIMEOUT_MS`, close with code 4009 and reason
   `absolute_timeout`
7. Client-side: display "Session expiring" toast, auto-reconnect on
   timeout close codes
8. Tests: idle timeout fires, absolute timeout fires, message resets
   idle timer, warning sent before expiry

#### Research Insights (TG-3)

**From OWASP Session Management Cheat Sheet:**

- **Idle timeout:** 15-30 min for low-risk apps, 2-5 min for high-value.
  30 min is appropriate -- users step away mid-conversation with agents.
- **Absolute timeout:** 4-8 hours. 8 hours covers a full workday.
- **Renewal timeout (optional):** Regenerate session IDs mid-session at
  intervals. Not applicable here since WebSocket connections don't use
  session IDs (Supabase JWT handles HTTP sessions).

**From project learnings:**

- **Close code routing (learning: 2026-03-27):** The client's `onclose`
  handler already routes on close codes via `NON_TRANSIENT_CLOSE_CODES`
  map. New timeout codes (4008, 4009) must be added to this map with
  appropriate behavior:
  - 4008 (idle timeout): show "Session expired due to inactivity"
    message, offer reconnect
  - 4009 (absolute timeout): show "Session expired" message, redirect
    to re-auth
- **TOCTOU race (learning: 2026-03-20):** The idle timer callback
  must check `ws.readyState === WebSocket.OPEN` before calling
  `ws.close()`. If the socket closed between timer scheduling and
  firing, `ws.close()` on a non-OPEN socket throws.

**Implementation pattern for idle timer with TOCTOU guard:**

```typescript
// After auth success, start timers
let idleTimer: ReturnType<typeof setTimeout> | undefined;
let absoluteTimer: ReturnType<typeof setTimeout> | undefined;
let warningTimer: ReturnType<typeof setTimeout> | undefined;

function resetIdleTimer() {
  if (idleTimer) clearTimeout(idleTimer);
  if (warningTimer) clearTimeout(warningTimer);

  warningTimer = setTimeout(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: "session_expiring", secondsLeft: 60 }));
    }
  }, IDLE_TIMEOUT_MS - IDLE_WARNING_MS);
  warningTimer.unref();

  idleTimer = setTimeout(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.close(WS_CLOSE_CODES.IDLE_TIMEOUT, "Idle timeout");
    }
  }, IDLE_TIMEOUT_MS);
  idleTimer.unref();
}

absoluteTimer = setTimeout(() => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.close(WS_CLOSE_CODES.ABSOLUTE_TIMEOUT, "Absolute timeout");
  }
}, ABSOLUTE_TIMEOUT_MS);
absoluteTimer.unref();

resetIdleTimer();
```

**Edge cases:**

- Timer `.unref()` prevents timers from keeping the Node process alive
  during graceful shutdown.
- On disconnect, clear all three timers to prevent memory leaks.
- The existing `pingInterval` (30s heartbeat) does NOT count as user
  activity -- only client-originated messages reset the idle timer.
- If an agent session is actively streaming when idle timeout fires,
  the agent session continues independently (it has its own lifecycle
  via `AbortController`). The client reconnects and can resume.

### TG-4: User Settings Page

**New files:**

- `app/(dashboard)/dashboard/settings/page.tsx` -- settings page with tabs
- `app/api/account/delete/route.ts` -- account deletion endpoint

**Files to modify:**

- `app/(dashboard)/layout.tsx` -- add settings link to navigation
- `app/api/keys/route.ts` -- add DELETE handler for key removal
- `lib/routes.ts` -- add settings to route configuration

**Implementation:**

1. **Settings page UI:**
   - Tab 1: API Keys -- show masked current key, rotate button, delete button
   - Tab 2: Account -- account info, danger zone with delete button
   - Use existing design patterns from dashboard (dark theme, neutral colors)

2. **API key rotation** (`POST /api/keys` already exists, enhance):
   - Show success/error feedback
   - Validate new key before replacing old one (already implemented)

3. **API key deletion** (`DELETE /api/keys`):
   - Add DELETE handler to existing route
   - Soft-delete: set `is_valid = false` rather than hard delete
   - Return confirmation

4. **Account deletion** (`POST /api/account/delete`):
   - Require email confirmation (user types their email to confirm)
   - Rate limit: 3 attempts per hour per user
   - Server-side cascade (order matters -- delete auth first, workspace
     last so user cannot be stranded if filesystem cleanup fails):
     a. Delete auth.users entry via Supabase Admin API
        (`supabase.auth.admin.deleteUser(userId)`) -- triggers FK
        cascade on users table, which cascades to conversations,
        messages, api_keys
     b. Clear all cookies in response
     c. Delete workspace directory (best-effort, log errors) -- a cron
        job cleans orphaned workspaces if this step fails
   - Return 200 with redirect to `/login`
   - Log deletion event (user ID only, no PII)

#### Research Insights (TG-4)

**Supabase admin.deleteUser behavior:**

- `supabase.auth.admin.deleteUser(id)` with default `shouldSoftDelete:
  false` performs a hard delete of the `auth.users` row.
- **Critical:** The `public.users` table has `id uuid primary key
  references auth.users(id) on delete cascade`. Hard-deleting the
  `auth.users` row triggers FK cascade: `public.users` -> `api_keys`,
  `conversations` -> `messages`. This is the correct behavior for GDPR.
- **Warning:** `shouldSoftDelete: true` does NOT delete the `auth.users`
  row -- it marks it as deleted with a hashed ID. This does NOT trigger
  the FK cascade, leaving orphaned data in public tables. **Always use
  `shouldSoftDelete: false` for GDPR deletion.**
- The function requires `service_role` key -- never call from browser.

**FK cascade chain (verified from migrations):**

```text
auth.users (hard delete)
  └─> public.users (ON DELETE CASCADE)
       ├─> public.api_keys (ON DELETE CASCADE via user_id FK)
       ├─> public.conversations (ON DELETE CASCADE via user_id FK)
       │    └─> public.messages (ON DELETE CASCADE via conversation_id FK)
       └─> [workspace filesystem -- NOT handled by FK, requires manual rm]
```

**Account deletion implementation pattern:**

```typescript
// POST /api/account/delete
export async function POST(request: Request) {
  // 1. Auth + validate email confirmation
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await request.json();
  if (body.confirmEmail !== user.email) {
    return NextResponse.json({ error: "Email does not match" }, { status: 400 });
  }

  // 2. Get workspace path before deletion (needed for filesystem cleanup)
  const service = createServiceClient();
  const { data: userRow } = await service
    .from("users")
    .select("workspace_path")
    .eq("id", user.id)
    .single();

  // 3. Hard delete auth.users (triggers FK cascade on all public tables)
  const { error } = await service.auth.admin.deleteUser(user.id);
  if (error) {
    return NextResponse.json({ error: "Deletion failed" }, { status: 500 });
  }

  // 4. Filesystem cleanup (best-effort)
  if (userRow?.workspace_path) {
    try {
      execFileSync("rm", ["-rf", userRow.workspace_path], { stdio: "pipe" });
    } catch (err) {
      log.error({ userId: user.id, err }, "Workspace cleanup failed");
      // Don't fail the request -- cron cleanup handles orphaned dirs
    }
  }

  // 5. Clear cookies and return
  const response = NextResponse.json({ deleted: true });
  response.cookies.delete("sb-access-token");
  response.cookies.delete("sb-refresh-token");
  // Clear all Supabase cookies (pattern: sb-*-auth-token)
  request.cookies.getAll()
    .filter(c => c.name.startsWith("sb-"))
    .forEach(c => response.cookies.delete(c.name));

  return response;
}
```

**GDPR compliance notes:**

- GDPR Article 17 requires deletion "without undue delay" (~30 days).
  Immediate deletion on confirmation exceeds this requirement.
- Log the deletion event with user ID only (no email, no PII) for
  audit trail. GDPR allows retention of processing records.
- If workspace cleanup fails, the orphaned directory contains no PII
  (it's the user's project files, not personal data). A cleanup cron
  can sweep `/workspaces/` for directories whose UUID doesn't match
  any `auth.users` ID.

**API key deletion (soft delete rationale):**

- Soft-delete (`is_valid = false`) rather than hard delete preserves
  the encrypted_key row for audit trail. The encrypted data is
  unreadable without the BYOK master key + user's HKDF-derived key.
- When the user hard-deletes their account, the FK cascade removes
  the api_keys row entirely.

### TG-5: Error + Empty States

**Files to modify:**

- `app/(dashboard)/dashboard/page.tsx` -- empty state for new users
- `app/(dashboard)/dashboard/kb/page.tsx` -- empty KB state
- `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- error states
- `lib/ws-client.ts` -- reconnection logic with status indicator
- `app/error.tsx` -- global error boundary improvements
- New: `components/ui/empty-state.tsx` -- reusable empty state component
- New: `components/ui/connection-status.tsx` -- WebSocket status indicator

**Implementation:**

1. Create reusable `EmptyState` component (icon, title, description, action)
2. Create `ConnectionStatus` component (connected/reconnecting/disconnected)
3. Add reconnection logic to ws-client.ts with exponential backoff
4. Update each page with contextual empty states
5. Add rate limit error display with countdown timer

#### Research Insights (TG-5)

**WebSocket reconnection with exponential backoff:**

```typescript
// In ws-client.ts
const MAX_RECONNECT_DELAY_MS = 30_000;
const BASE_DELAY_MS = 1_000;
let reconnectAttempt = 0;

function scheduleReconnect() {
  const delay = Math.min(
    BASE_DELAY_MS * Math.pow(2, reconnectAttempt),
    MAX_RECONNECT_DELAY_MS,
  );
  // Add jitter to prevent thundering herd
  const jitter = delay * 0.2 * Math.random();
  reconnectAttempt += 1;
  setTimeout(connect, delay + jitter);
}

function onOpen() {
  reconnectAttempt = 0; // Reset on successful connection
}
```

**From project learnings:**

- **Close code routing (learning: 2026-03-27):** Non-transient close
  codes (4001 auth failure, 4004 T&C, 4005 server error) must NOT
  trigger reconnection. Only transient codes (1006 abnormal closure,
  1001 going away) should reconnect. The existing `NON_TRANSIENT_CLOSE_CODES`
  map in `ws-client.ts` handles this. New codes 4008/4009 should be
  added as non-transient with appropriate UI messages.

**Empty state design principles:**

- Empty states are onboarding opportunities, not dead ends. Each empty
  state should include: (1) what this page is for, (2) why it's empty,
  (3) a single primary action to populate it.
- Use consistent visual treatment: centered layout, muted icon, short
  title, one-line description, prominent CTA button.

### TG-6: UX Audit

**Approach:** Run ux-design-lead agent against each screen. The audit
covers:

**Screens to audit (10 total):**

1. `/login` -- login page
2. `/signup` -- signup page
3. `/accept-terms` -- T&C acceptance
4. `/setup-key` -- BYOK key setup
5. `/connect-repo` -- repository connection
6. `/dashboard` -- main dashboard (chat-first)
7. `/dashboard/chat/[id]` -- conversation view
8. `/dashboard/kb` -- knowledge base viewer
9. `/dashboard/billing` -- billing page
10. `/dashboard/settings` -- new settings page (from TG-4)

**Audit criteria:**

- Visual hierarchy and information density
- Touch target sizes (min 44x44 px for mobile)
- Color contrast (WCAG AA minimum)
- Loading states and skeleton screens
- Error recovery paths
- Keyboard navigation flow

**Deliverable:** Issues filed for each finding, critical fixes applied
in this PR, non-critical deferred to future phases.

### TG-7: First-Time Onboarding Walkthrough

**New files:**

- `components/onboarding/walkthrough.tsx` -- step-based overlay component
- `components/onboarding/walkthrough-step.tsx` -- individual step renderer
- `lib/onboarding.ts` -- step definitions and completion tracking

**Implementation:**

1. Define walkthrough steps (4-5 steps):
   - Step 1: "This is your Command Center" -- highlights chat input
   - Step 2: "Mention a leader with @" -- highlights @-mention area
   - Step 3: "Try a suggested prompt" -- highlights prompt cards
   - Step 4: "Your AI organization" -- highlights leader strip
   - Step 5 (iOS only): "Install as app" -- PWA install guidance
2. Spotlight overlay: semi-transparent backdrop with cutout around
   highlighted element
3. Completion tracking: `localStorage.setItem('onboarding_complete', 'true')`
   (upgrade to DB flag in Phase 3 when user settings table is richer)
4. Skip button and step counter visible at all times
5. Does not block interaction -- user can click through the overlay

#### Research Insights (TG-7)

**Spotlight overlay implementation (no external library):**

The overlay uses a CSS `box-shadow` trick to create the spotlight effect
without complex SVG clipping:

```typescript
// Walkthrough spotlight overlay
const Spotlight = ({ targetRect }: { targetRect: DOMRect }) => (
  <div
    style={{
      position: "fixed",
      top: targetRect.top - 8,
      left: targetRect.left - 8,
      width: targetRect.width + 16,
      height: targetRect.height + 16,
      borderRadius: 12,
      boxShadow: "0 0 0 9999px rgba(0, 0, 0, 0.7)",
      zIndex: 9999,
      pointerEvents: "none",
    }}
  />
);
```

**Key implementation details:**

- Use `getBoundingClientRect()` to position the spotlight. Recalculate
  on window resize with `ResizeObserver`.
- Set `pointer-events: none` on the overlay so users can interact with
  the highlighted element.
- Use `data-onboarding="step-1"` attributes on target elements rather
  than querying by class/ID -- decouples onboarding from component
  implementation.
- Animate transitions between steps with CSS `transition: all 300ms
  ease-in-out` on the spotlight `div`.

**iOS PWA install detection:**

```typescript
// Detect iOS and whether app is already installed as PWA
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
const isStandalone = window.matchMedia("(display-mode: standalone)").matches
  || (navigator as any).standalone === true;
const showPWAStep = isIOS && !isStandalone;
```

**Completion persistence:**

- `localStorage` is appropriate for beta (single device).
- Key: `soleur_onboarding_complete` with value `"1"` (not boolean --
  localStorage stores strings).
- Check on mount with `useEffect`, not during render, to avoid SSR
  hydration mismatch.

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Security audit finds critical issues | Blocks all other work | TG-1 runs first; findings become immediate tasks |
| Account deletion breaks FK constraints | Data integrity | Test cascade on dev DB first; `ON DELETE CASCADE` already set |
| Workspace filesystem deletion fails | Orphaned files | Log error, continue DB deletion; add cleanup cron later |
| Onboarding interferes with existing UI | UX regression | Overlay is non-blocking; can be disabled via localStorage |
| Session timeout interrupts active agent runs | Lost work | Agent sessions have their own lifecycle; only WS closes |

## Non-Goals / Out of Scope

- **Supply chain hardening** (#1174) -- separate issue, separate PR
- **OAuth sign-in** (#1210) -- already merged (PR #1211)
- **Legal doc updates** (AUP, Cookie Policy, Privacy Policy) -- separate
  CLO-led tasks (roadmap 2.7-2.9)
- **WebSocket rate limiting** -- already implemented (rate-limiter.ts)
- **Sandbox `/proc` deny** -- already implemented (`denyRead: ["/workspaces", "/proc"]`)
- **Full penetration testing** -- this is a code-level audit, not a pentest
- **Storybook / visual regression** -- deferred to Phase 3

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| External auth library (NextAuth.js) | Battle-tested session management | Supabase already handles auth well | Keep Supabase auth, add timeout at WS layer |
| Cookie-based session timeout | Server-side control | WS connections bypass cookie refresh | Timer-based WS expiry (chosen) |
| Hard account deletion via SQL function | Atomic, reliable | Complex to test, less visibility | API route with cascade + admin API (chosen) |
| Shepherd.js for onboarding | Feature-rich | External dependency, attack surface | Custom lightweight overlay (chosen) |
| Server-side onboarding state | Survives device changes | Requires DB migration for a flag | localStorage for MVP, upgrade later |

## References & Research

- [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
  -- idle timeout 15-30 min, absolute 4-8 hours
- [OWASP CSP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html)
  -- strict-dynamic + nonce, report-to
- [GDPR Article 17](https://gdpr.eu/right-to-be-forgotten/) -- erasure
  "without undue delay" (~30 days), cascade across all systems
- Constitution rule: "When adding a compliance gate to one enforcement
  surface, update all enforcement surfaces to use the same check"
- Constitution rule: "CSP with strict-dynamic + nonce requires dynamic
  rendering in root layout"
- Existing implementation: `middleware.ts` already forces dynamic rendering
  via `await supabase.auth.getUser()`

## Domain Review

**Domains relevant:** Engineering, Legal, Product, Operations

### Engineering

**Status:** reviewed
**Assessment:** The existing security posture is strong for a pre-beta
platform. The main gaps are session management (no idle/absolute timeout
on WebSocket), missing CORS headers on API routes, and no account
deletion flow. The sandbox and BYOK implementations follow security best
practices (HKDF, bubblewrap, symlink resolution, deny-by-default). The
`/proc` deny is already implemented. Rate limiting is comprehensive
(3-layer). The primary engineering risk is the account deletion cascade
-- test thoroughly on dev before production.

### Legal

**Status:** reviewed
**Assessment:** GDPR Article 17 compliance requires account deletion
with full data purge. The 30-day timeline is met by implementing
immediate deletion on request. The cascade must cover: database rows
(handled by FK constraints), workspace filesystem, auth.users entry, and
any cached data. Legal doc updates (AUP, Cookie Policy, Privacy Policy)
are tracked separately in roadmap items 2.7-2.9 and should be completed
before beta invitations but are not blocked by this PR.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial)
**Agents invoked:** spec-flow-analyzer (inline analysis)
**Skipped specialists:** ux-design-lead (TG-6 runs UX audit as part of
implementation -- wireframes produced during work phase, not plan phase),
copywriter (no domain leader recommended)
**Pencil available:** N/A

#### Findings

The user settings page and onboarding walkthrough are new user-facing
pages requiring BLOCKING-tier review. However, these are functional
pages (settings form, step overlay) rather than marketing/landing pages.
The UX audit in TG-6 covers all screens including the new settings page.
Wireframes will be produced during the work phase when ux-design-lead
runs the full audit.

**User flow analysis:**

- Settings page: Dashboard nav -> Settings -> API Keys tab / Account tab
  -> Rotate key / Delete account -> Confirmation -> Success/Redirect
- Onboarding: First login -> Walkthrough overlay -> Step 1-5 -> Complete
  -> Dashboard (normal)
- Account deletion: Settings -> Account tab -> Delete Account -> Email
  confirmation modal -> Processing -> Redirect to login

No dead ends identified. Error states covered in TG-5. The deletion flow
requires explicit confirmation (email re-entry) to prevent accidental
deletion.

### Operations

**Status:** reviewed
**Assessment:** No new vendor signups or service provisioning required.
All infrastructure already exists (Supabase, Sentry, Cloudflare). The
CSP report-uri uses the existing Sentry endpoint. No expense ledger
updates needed. The session timeout and account deletion features are
pure code changes with no operational cost implications.
