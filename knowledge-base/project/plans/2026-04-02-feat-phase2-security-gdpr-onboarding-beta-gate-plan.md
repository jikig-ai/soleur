---
title: "feat: Phase 2 — Security audit, GDPR, onboarding (beta gate)"
type: feat
date: 2026-04-02
semver: minor
---

# Phase 2: Security Audit, GDPR, Onboarding (Beta Gate)

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 5 of 5 active tasks
**Research sources:** Context7 (Supabase, Next.js), 12 institutional learnings, OWASP Top 10 2021

### Key Improvements

1. Explicit account deletion order with Supabase cascade semantics and stale cookie clearing strategy
2. Security audit checklist enriched with 8 codebase-specific learnings (TOCTOU race, CSP strict-dynamic, /proc sandbox, attack surface enumeration)
3. Error boundary implementation updated to Next.js `unstable_retry` API (replaces deprecated `reset`)
4. WebSocket idle timeout implementation pattern with timer cleanup to prevent memory leaks

### New Considerations Discovered

- Supabase `auth.admin.deleteUser()` also cascades to `public.users` via the `on_auth_user_deleted` trigger if one exists -- verify trigger state to avoid double-delete errors
- Next.js `global-error.tsx` must include its own `<html>` and `<body>` tags (replaces root layout when active)
- Stale auth cookies after account deletion cause wasted `getUser()` calls on every middleware invocation until cleared -- must explicitly clear Supabase cookies on the redirect response

## Overview

Phase 2 is the mandatory gate before inviting beta users. It covers five active workstreams: OWASP security audit (including CSP/CORS verification), session idle timeout, UX audit of Phase 1 screens, user settings page (API key rotation, GDPR account deletion), and error/empty states. One workstream (onboarding walkthrough) is deferred to post-beta. All items traced to [#674](https://github.com/jikig-ai/soleur/issues/674) and the Phase 2 milestone.

**Preconditions (all CLOSED):** #667 (BYOK fix), #668 (integration tests), #670 (DPA review).

## Problem Statement / Motivation

The platform handles PII (email, workspace data) and user-provided API keys. Before any external user touches it:

1. Security posture must be auditable against OWASP Top 10
2. GDPR Article 17 (right to erasure) must work end-to-end
3. Session management must prevent stale/orphaned connections
4. UX must have error states, empty states, and onboarding so users do not hit dead ends

From CPO review: "The platform must be functional and secure before any founder touches it."

## Existing State

**Already implemented:**

- CSP with nonce-based `strict-dynamic` policy (`lib/csp.ts`, `middleware.ts`)
- Security headers: HSTS, X-Frame-Options DENY, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP, CORP (`lib/security-headers.ts`)
- CORS/CSRF origin validation on API routes (`lib/auth/validate-origin.ts`)
- BYOK encryption with AES-256-GCM + HKDF per-user key derivation (`server/byok.ts`)
- Workspace sandbox with symlink-aware path traversal prevention (`server/sandbox.ts`)
- Bash command env-access defense-in-depth (`server/bash-sandbox.ts`)
- Tool path checking for all file-accessing tools (`server/tool-path-checker.ts`)
- PreToolUse sandbox hook (`server/sandbox-hook.ts`)
- 3-layer WebSocket rate limiting: IP connection throttle, pending connection tracker, per-user session throttle (`server/rate-limiter.ts`)
- Error sanitization preventing internal details leaking to clients (`server/error-sanitizer.ts`)
- Supabase RLS on all tables
- WebSocket auth timeout (5s), heartbeat (30s ping), disconnect grace period (30s)
- Orphaned conversation cleanup on server restart
- 24h inactivity timeout for waiting_for_user conversations

**Not yet implemented:**

- Configurable idle session timeout (WebSocket closes after X minutes of no user activity)
- WebSocket connection expiry (max lifetime per connection)
- User settings page (API key rotation, account deletion)
- GDPR account deletion with full data purge
- Error states and empty states for all failure paths
- First-time onboarding walkthrough
- UX audit of Phase 1 screens
- `/proc` in sandbox deny list (noted in roadmap 2.6 but already done per learnings)

## Proposed Solution

Six tasks organized in two phases. The security audit now subsumes CSP/CORS verification (previously a separate task). Onboarding walkthrough deferred to post-beta (existing dashboard copy with suggested prompts and @-mention hints is sufficient for <10 invited founders). Tasks 1-4 can run in parallel. Tasks 5-6 follow once the security foundation is stable.

### Task 1: Security Audit (OWASP Top 10)

**Scope:** Systematic review of the existing codebase against OWASP Top 10 2021, focusing on the attack surfaces specific to this application: WebSocket handler, API routes, agent sandbox, BYOK key handling, workspace isolation.

**Approach:** Inline findings only (constitution: never persist aggregated security findings to files in an open-source repository). Create GitHub issues for each finding.

**Checklist:**

- [ ] **A01:2021 Broken Access Control** — Verify RLS policies on all Supabase tables. Check that conversation ownership is enforced on resume_session. Verify workspace isolation in sandbox.ts resolves symlinks correctly.
- [ ] **A02:2021 Cryptographic Failures** — Review BYOK encryption (AES-256-GCM + HKDF). Verify IV is random per encryption, auth tags are validated, key derivation uses proper info parameter per RFC 5869. Check TLS enforcement (HSTS preload).
- [ ] **A03:2021 Injection** — Review Bash command execution in agent-runner. Verify execFileSync usage (not exec). Check SQL injection vectors (Supabase client parameterizes, but verify custom queries). Review message content handling in ws-handler.
- [ ] **A04:2021 Insecure Design** — Review the agent permission model (canUseTool). Verify deny-by-default for unknown tools. Check that the Agent tool spawns subagents with parent sandbox constraints.
- [ ] **A05:2021 Security Misconfiguration** — Verify CSP headers on all response paths (middleware responses, API Route Handler responses, error pages, static files). Verify `connect-src` includes all legitimate WebSocket origins. Check CORS preflight handling on all mutating API routes. Verify Stripe webhook handles origin-less requests. Verify no debug endpoints exposed in production. Add integration test for CSP header presence on every response type.
- [ ] **A06:2021 Vulnerable and Outdated Components** — Check npm audit. Verify dependency pinning (bunfig.toml minimumReleaseAge). Review Dockerfile base image pinning.
- [ ] **A07:2021 Identification and Authentication Failures** — Review Supabase auth token validation in WS handler. Check session fixation vectors. Verify token is validated on every connection (not cached).
- [ ] **A08:2021 Software and Data Integrity Failures** — Review CI pipeline integrity. Check GitHub Actions workflow permissions. Verify no user-controlled inputs flow into `run:` blocks unvalidated.
- [ ] **A09:2021 Security Logging and Monitoring Failures** — Verify Sentry is capturing security-relevant events (rate limit triggers, auth failures, sandbox denials). Check structured logging for forensic trail.
- [ ] **A10:2021 Server-Side Request Forgery** — Review the Anthropic API key validation endpoint. Check if any user input is used to construct URLs for server-side fetches.

**Files to audit:**

| File | Attack surface |
|------|---------------|
| `server/ws-handler.ts` | WebSocket auth, message routing |
| `server/agent-runner.ts` | Agent execution, BYOK key retrieval, tool permissions |
| `server/sandbox.ts` | Path traversal, symlink resolution |
| `server/sandbox-hook.ts` | PreToolUse deny decisions |
| `server/bash-sandbox.ts` | Env-access pattern matching |
| `server/byok.ts` | Key encryption/decryption |
| `server/workspace.ts` | Workspace provisioning, git operations |
| `server/rate-limiter.ts` | Rate limiting correctness |
| `server/error-sanitizer.ts` | Information leakage |
| `middleware.ts` | Auth, CSP injection, redirect chain |
| `app/api/keys/route.ts` | API key storage |
| `app/api/*/route.ts` | All API route handlers |
| `lib/auth/validate-origin.ts` | CSRF protection |
| `lib/csp.ts` | CSP construction |

#### Research Insights

**Institutional learnings to apply during audit (from `knowledge-base/project/learnings/`):**

- **TOCTOU race in WS auth** (`2026-03-20-websocket-first-message-auth-toctou-race.md`): The auth timeout can fire during the async `getUser()` call, creating a phantom session. Already fixed with `readyState` guard, but verify this guard is still present and covers all async gaps.
- **CSP strict-dynamic requires dynamic rendering** (`2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`): Root layout must call `await headers()` or equivalent to force dynamic rendering. Without it, Next.js renders scripts without nonces and strict-dynamic blocks everything. Verify root layout is still dynamic.
- **CSP connect-src needs explicit WS schemes** (`2026-03-28-csp-connect-src-websocket-scheme-mismatch.md`): `'self'` does not cover `wss://` in all browsers. Verify `buildCspHeader()` still includes explicit `wss://app.soleur.ai` in connect-src.
- **CSP localhost forwarded-host validation** (`2026-03-29-csp-localhost-forwarded-host-validation.md`): `request.nextUrl.host` returns `localhost:3000` behind Cloudflare. Verify middleware still uses `resolveOrigin()` for CSP host, not `request.nextUrl.host`.
- **/proc in sandbox deny list** (`2026-03-29-proc-sandbox-deny-session.md`): `/proc` added to `denyRead` in agent-runner.ts. Verify it is still present. Check if `/sys` follow-up (#1285) is tracked.
- **Attack surface enumeration pattern** (`2026-03-20-security-fix-attack-surface-enumeration.md`): When auditing, enumerate ALL code paths that touch each security surface, not just the reported vector. Write negative-space tests that assert every tool routes through the security check or is explicitly documented as exempt.
- **Adjacent config audit** (`2026-03-20-security-refactor-adjacent-config-audit.md`): When reviewing config objects (AgentRunner config, sandbox config), verify no adjacent options were accidentally removed in prior refactors. Check `settingSources: []` is still present.
- **Agent tool not in SAFE_TOOLS** (`2026-03-20-agent-safe-tools-audit.md`): Agent tool was removed from SAFE_TOOLS and given an explicit block in canUseTool for auditability. Verify this is still the case.

**OWASP audit methodology:**

- For each category, enumerate the full attack surface before checking individual files
- Write at least one negative-space test per category (test that the boundary works, not just that expected paths work)
- Document findings inline only (constitution rule: never persist aggregated security findings to open-source repo files)
- Create GitHub issues with severity labels for each finding, milestoned to Phase 2

**Acceptance criteria:**

- [ ] All 10 OWASP categories reviewed with findings documented as GitHub issues
- [ ] 0 critical or high severity findings remain open after remediation
- [ ] Medium/low findings tracked with milestone assignment

### Task 2: Session Timeout + WebSocket Idle Expiry

**Scope:** Add configurable idle timeout to the WebSocket handler. Close idle connections cleanly with a specific close code so the client can show "Session expired" and offer reconnect.

**Current state:**

- Auth timeout: 5s (existing)
- Heartbeat: 30s ping (existing)
- Disconnect grace: 30s (existing)
- Inactivity timeout: 24h for waiting_for_user conversations (existing, too long for beta)

**Work items:**

- [ ] Add `WS_IDLE_TIMEOUT_MS` env var (default: 30 minutes). Track last user message timestamp per session. Close with a new `WS_CLOSE_CODES.IDLE_TIMEOUT` code when exceeded.
- [ ] Add `IDLE_TIMEOUT` close code to `lib/types.ts` and handle in `ws-client.ts` — show "Session expired due to inactivity" and offer reconnect button.
- [ ] Reduce inactivity timeout from 24h to 2h for waiting_for_user conversations.
- [ ] Add tests for idle timeout reset on user message, idle close code propagation.

**Deferred (review consensus):** Max WebSocket lifetime (8h cap) dropped — idle timeout handles abandoned connections; max lifetime interrupts active users with no benefit at beta scale. Pre-close warning message dropped — just close the connection; the client already handles reconnection.

#### Research Insights

**Implementation pattern:**

```typescript
// In ClientSession interface (ws-handler.ts), add:
interface ClientSession {
  ws: WebSocket;
  conversationId?: string;
  disconnectTimer?: ReturnType<typeof setTimeout>;
  lastActivity: number;        // Date.now() timestamp
  idleTimer?: ReturnType<typeof setTimeout>;
}

// On session creation and each user message:
function resetIdleTimer(userId: string, session: ClientSession): void {
  if (session.idleTimer) clearTimeout(session.idleTimer);
  session.lastActivity = Date.now();
  const timeoutMs = parseInt(process.env.WS_IDLE_TIMEOUT_MS ?? "1800000", 10);
  session.idleTimer = setTimeout(() => {
    session.ws.close(WS_CLOSE_CODES.IDLE_TIMEOUT, "Idle timeout");
  }, timeoutMs);
  session.idleTimer.unref(); // Do not prevent Node.js exit
}
```

**Edge cases:**

- Timer must be cleared on disconnect (`ws.on("close")`) to prevent memory leaks from accumulated `setTimeout` references for disconnected users
- Timer must be cleared when session is superseded (existing `abortActiveSession` path)
- `timer.unref()` prevents idle timers from keeping the Node.js process alive during graceful shutdown
- The `handleMessage` switch for `chat` type is the correct place to reset the timer (only user-initiated messages count as activity, not server-to-client streams)

**Files to modify:**

- `server/ws-handler.ts` — Add idle tracking per session, clear timer on close/supersede
- `lib/types.ts` — Add IDLE_TIMEOUT close code
- `lib/ws-client.ts` — Handle idle timeout close code (add to `NON_TRANSIENT_CLOSE_CODES` with reconnect button, no redirect)
- `server/agent-runner.ts` — Reduce INACTIVITY_TIMEOUT_MS from 24h to 2h
- `test/ws-protocol.test.ts` — Idle timeout tests (timer reset, timer cleanup on close, close code propagation)

### Task 3: UX Audit of Phase 1 Screens

**Scope:** Systematic review of all existing screens built in Phase 1 via ux-design-lead agent. 5+ screens were built without design review (per #671).

**Screens to audit:**

| Screen | File | Purpose |
|--------|------|---------|
| Login | `app/(auth)/login/page.tsx` | Email/password + OAuth sign-in |
| Signup | `app/(auth)/signup/page.tsx` | Account creation |
| Accept Terms | `app/(auth)/accept-terms/page.tsx` | T&C acceptance gate |
| Setup Key | `app/(auth)/setup-key/page.tsx` | BYOK API key entry |
| Connect Repo | `app/(auth)/connect-repo/page.tsx` | GitHub repo connection |
| Dashboard | `app/(dashboard)/dashboard/page.tsx` | Command center home |
| Chat | `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | Conversation view |
| KB Viewer | `app/(dashboard)/dashboard/kb/page.tsx` | Knowledge base viewer |
| Billing | `app/(dashboard)/dashboard/billing/page.tsx` | Stripe billing portal |

**Approach:**

1. Invoke ux-design-lead agent to audit each screen for: visual consistency, accessibility (WCAG 2.1 AA), mobile responsiveness, interaction patterns, information hierarchy
2. Document findings per screen
3. Prioritize fixes: P1 (blocks beta), P2 (should fix before beta), P3 (post-beta polish)
4. Implement P1 and P2 fixes

#### Research Insights

**WCAG 2.1 AA priority checklist for this audit:**

- **Color contrast** — The dashboard uses `text-neutral-400` on `bg-neutral-950`. Verify contrast ratio meets 4.5:1 for normal text, 3:1 for large text. The amber accent colors (`text-amber-500`, `bg-amber-950/30`) must also meet ratio against their backgrounds.
- **Keyboard navigation** — Tab order must be logical across: chat input, suggested prompts, leader strip. The `@-mention` dropdown must be navigable with arrow keys and dismissible with Escape.
- **Focus indicators** — Verify all interactive elements have visible focus rings. Tailwind's default `focus-visible:ring` may be suppressed by custom styles.
- **Screen reader** — Chat messages need `role="log"` or `aria-live="polite"` for dynamic updates. The routing badge ("Auto-routed to CMO") needs `aria-live="polite"`. The status indicator dot needs an `aria-label`.
- **Touch targets** — The leader strip buttons (`px-2 py-1`) may be too small for mobile (44x44px minimum per WCAG). The suggested prompt cards look adequate.
- **Motion** — The `animate-pulse` on the classification indicator respects `prefers-reduced-motion` if Tailwind's config includes the default animation utilities. Verify.

**Common P1 issues in dark-theme chat UIs:**

- Placeholder text that is invisible or nearly invisible against the dark background
- Error states that use red-on-dark-red which fails contrast
- Links that are indistinguishable from surrounding text without color differentiation
- Missing focus management when modals/dialogs open (trap focus) and close (return focus)

**Acceptance criteria:**

- [ ] All 9 screens reviewed by ux-design-lead
- [ ] 0 P1 UX issues remain (blocks beta)
- [ ] P2 issues either fixed or tracked as GitHub issues
- [ ] Accessibility: all interactive elements have labels, color contrast meets AA, keyboard navigation works

### Task 4: User Settings Page (API Key Rotation + GDPR Account Deletion)

**Scope:** New `/dashboard/settings` page with two sections: API key management and account management (GDPR). Simple flat layout with section headings — no tabs or complex navigation until there are 3+ sections.

**API Key Management:**

- [ ] Display current key status (valid/invalid, provider, last validated)
- [ ] "Rotate Key" flow: enter new key, validate against Anthropic API, encrypt with HKDF, upsert. Old key is overwritten (not versioned).
- [ ] "Delete Key" button: removes the api_keys row for the user

**Account Deletion (GDPR Article 17):**

- [ ] "Delete Account" button with confirmation dialog (type account email to confirm)
- [ ] Server-side deletion cascade:
  1. Abort any active agent session
  2. Delete workspace directory (`rm -rf /workspaces/{userId}`)
  3. Delete all database records: messages, conversations, api_keys, users row (cascade from users.id FK handles most)
  4. Call `supabase.auth.admin.deleteUser(userId)` to remove auth record
  5. Return confirmation
- [ ] POST `/api/account/delete` route with origin validation, auth check, and rate limiting
- [ ] Client redirects to `/login` after successful deletion with "Account deleted" flash message
- [ ] Audit: verify no orphaned data remains (check all tables with user_id FK)
- [ ] After deletion, `/login` page handles stale auth cookies gracefully (clears cookie, no error displayed)

**Files to create:**

- `app/(dashboard)/dashboard/settings/page.tsx` — Settings page component
- `app/api/account/delete/route.ts` — Account deletion endpoint

**Files to modify:**

- `app/(dashboard)/layout.tsx` — Add settings link to navigation
- `lib/routes.ts` — No change needed (settings is behind auth via middleware)
- `server/workspace.ts` — Add `deleteWorkspace(userId)` function

**Database considerations:**

- All user-related tables have `ON DELETE CASCADE` from users.id
- Supabase auth.users deletion must happen AFTER public.users deletion (foreign key order)
- The `handle_new_user()` trigger only fires on INSERT, no conflict with DELETE

#### Research Insights

**Deletion order (verified against Supabase docs and schema):**

The correct server-side deletion sequence:

1. **Abort active agent session** — Call `abortSession(userId, convId)` for any active conversation
2. **Delete workspace directory** — `rm -rf /workspaces/{userId}` via `deleteWorkspace()`. Use `execFileSync("rm", ["-rf", path])` (not `exec`) to prevent shell injection via crafted userId (though UUID validation already blocks this)
3. **Delete `public.users` row** — This cascades to `api_keys`, `conversations`, and `messages` via FK constraints. Use service role client to bypass RLS.
4. **Delete `auth.users` record** — Call `supabase.auth.admin.deleteUser(userId)`. This must happen AFTER step 3 because `public.users.id` references `auth.users(id)` with `ON DELETE CASCADE`. If we deleted auth first, the cascade would also delete `public.users`, which is fine functionally but means step 3 would be a no-op. Keeping explicit step 3 first gives us a clean audit trail (we know public data was deleted before auth).

**Critical: Check for `on_auth_user_deleted` trigger.** The schema has `on_auth_user_created` trigger but no `on_auth_user_deleted`. If a delete trigger exists on `auth.users` that cascades to `public.users`, deleting auth first would double-cascade. Verify with `SELECT tgname FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass;`

**Stale cookie clearing strategy:**

After account deletion, the response must clear Supabase auth cookies to prevent wasted `getUser()` calls on every subsequent request:

```typescript
// In the delete API route, after successful deletion:
const response = NextResponse.json({ success: true });
// Clear all Supabase auth cookies (prefixed with sb-)
const cookieNames = request.cookies.getAll()
  .filter(c => c.name.startsWith("sb-"))
  .map(c => c.name);
for (const name of cookieNames) {
  response.cookies.delete(name);
}
return response;
```

The client-side redirect to `/login` should also clear local Supabase state by calling `supabase.auth.signOut()` before navigation, which clears the in-memory session and local storage tokens.

**Rate limiting the delete endpoint:**

Apply a strict per-user rate limit (1 request per 60 seconds) using the existing `SlidingWindowCounter` pattern from `rate-limiter.ts`. Account deletion is an irreversible operation — rate limiting prevents accidental double-submissions and abuse.

**Confirmation dialog security:**

The "type your email to confirm" pattern is standard (GitHub, Heroku, AWS all use it). Verify the typed email against `user.email` server-side, not just client-side. The API route should reject the request if the confirmation email does not match.

### Task 5: Error States and Empty States

**Scope:** Ensure every failure path shows a meaningful UI state instead of a blank screen or cryptic error.

**Error states to implement:**

| Scenario | Current behavior | Target behavior |
|----------|-----------------|-----------------|
| WebSocket connection failed | Blank "Connecting" | Error card with retry button |
| Agent session failed to start | Generic "error" message | Specific error card (key invalid, rate limited, internal error) |
| Network loss during chat | "Reconnecting" status dot | Banner: "Connection lost. Reconnecting..." with manual retry |
| API key invalid/expired | Error toast only | Inline card: "Your API key is invalid. [Update key]" with link to settings |
| Rate limited | Generic error | "You've been rate limited. Try again in X seconds." |
| Server error (500) | White page | `error.tsx` boundary with branded error page |
| Global error | White page | `global-error.tsx` with minimal recovery UI |

**Empty states to implement:**

| Screen | Empty condition | Target UI |
|--------|----------------|-----------|
| Dashboard | No conversations yet | Already has suggested prompts (good). Add "Welcome" copy for first visit. |
| Chat list | No past conversations | "Start your first conversation" CTA |
| KB viewer | Empty knowledge base | "Your knowledge base is empty" with explanation |
| Settings | No API key set | "No API key configured" with setup CTA |

**Files to modify:**

- `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — Error/empty states in chat
- `app/(dashboard)/dashboard/page.tsx` — First-visit empty state
- `app/(dashboard)/dashboard/kb/page.tsx` — Empty KB state
- `app/error.tsx` — Branded error boundary
- `app/global-error.tsx` — Global error boundary
- `lib/ws-client.ts` — Surface specific error codes to UI
- New component: `components/ui/error-card.tsx` — Reusable error display

#### Research Insights

**Next.js error boundary API (verified via Context7, Next.js v16):**

The error boundary API now uses `unstable_retry` instead of the deprecated `reset` function:

```typescript
// app/error.tsx — Route-level error boundary
'use client';

import { useEffect } from 'react';
import * as Sentry from '@sentry/nextjs';

export default function Error({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4">
      <h2 className="text-xl font-semibold text-white">Something went wrong</h2>
      <p className="text-sm text-neutral-400">
        {error.digest ? `Error ID: ${error.digest}` : 'An unexpected error occurred.'}
      </p>
      <button
        onClick={() => unstable_retry()}
        className="rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-300 hover:border-neutral-500"
      >
        Try again
      </button>
    </div>
  );
}
```

```typescript
// app/global-error.tsx — MUST include <html> and <body> tags
// Replaces root layout when active
'use client';

export default function GlobalError({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  return (
    <html lang="en">
      <body className="bg-neutral-950 text-white">
        <div className="flex min-h-screen flex-col items-center justify-center gap-4">
          <h2 className="text-xl font-semibold">Something went wrong</h2>
          <button
            onClick={() => unstable_retry()}
            className="rounded-lg border border-neutral-700 px-4 py-2 text-sm"
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
```

**WebSocket error surfacing pattern:**

The `ws-client.ts` hook already has `NON_TRANSIENT_CLOSE_CODES` mapping. For error states, expose a structured `lastError` field from the hook:

```typescript
interface WebSocketError {
  code: string;        // 'key_invalid' | 'rate_limited' | 'connection_failed' | 'internal'
  message: string;     // User-friendly message
  action?: {           // Optional recovery action
    label: string;     // "Update key" | "Try again" | "Reconnect"
    href?: string;     // "/dashboard/settings" for key_invalid
    onClick?: () => void; // reconnect function for connection errors
  };
}
```

This structured error object lets the chat page render appropriate inline cards without parsing error message strings.

**Empty state design principles:**

- Every empty state must have a clear CTA (call to action) that leads to the next step
- Use the same visual language (neutral-400 text, neutral-800 borders) as existing dashboard components
- Empty states should feel inviting, not broken — "Your knowledge base is empty" with "Start a conversation to build it" is better than "No data found"

### Task 6 (Deferred): First-Time Onboarding Walkthrough

**Status:** Deferred to post-beta. The dashboard already provides onboarding through suggested prompts and "@-mention" hint text. With fewer than 10 personally invited beta founders, a tooltip walkthrough adds complexity without proportional value. A tracking GitHub issue will be created.

**Re-evaluation criteria:** Defer until beta user count exceeds 10 or user feedback indicates confusion about the Command Center UI.

## Non-Goals

- **First-time onboarding walkthrough** — Deferred to post-beta (review consensus: existing dashboard copy is sufficient for <10 invited founders). Tracking issue to be created.
- **Full offline mode** — PWA offline support is Phase 1 scope (#1042), not Phase 2
- **Conversation history export** — GDPR Article 20 (data portability) deferred to Phase 3. Account deletion (Article 17) is the beta gate requirement.
- **Multi-factor authentication** — Beyond scope for beta. Supabase auth handles this if enabled later.
- **Automated penetration testing** — Manual OWASP audit is sufficient for beta. Automated scanning (ZAP, Nuclei) deferred to Phase 3.
- **Admin dashboard** — No admin UI for managing users. Server-side Supabase queries suffice for beta.
- **Audit logging to external SIEM** — Sentry + Better Stack structured logging is sufficient.
- **CSP Level 3 `report-to` directive** — `report-uri` works. Browser support for Reporting API v1 is inconsistent. Defer.
- **Max WebSocket lifetime** — Idle timeout handles abandoned connections. Max lifetime interrupts active users with no benefit at beta scale.

## Alternative Approaches Considered

| Approach | Rejected because |
|----------|-----------------|
| Session timeout via Supabase auth token expiry only | Supabase tokens have configurable JWT expiry but this only affects HTTP auth, not WebSocket connections which are long-lived |
| GDPR deletion via Supabase Edge Function | Adds deployment complexity. A Next.js API route with service role key achieves the same result without another runtime |
| Onboarding as a separate page (`/onboarding`) | Forces users through a gate. Tooltip walkthrough is less intrusive and can be dismissed |
| Error boundaries only (no inline error states) | React error boundaries catch render errors but not async failures (WebSocket, API calls). Both are needed. |
| Session management via Redis | Adds infrastructure. In-memory session tracking in the Node.js server is sufficient for single-server beta deployment |

## Dependencies

- Phase 1 blockers (#667, #668, #670) — All CLOSED
- Supabase service role key in production Doppler config — Required for account deletion
- `BYOK_ENCRYPTION_KEY` in production — Already provisioned
- No new external services or vendors required

## Implementation Order

```text
Phase A (parallel — all can start immediately):
  Task 1: Security audit (OWASP + CSP/CORS verification) ──→ remediate findings
  Task 2: Session timeout ──→ implement + test
  Task 3: UX audit ──→ fix P1/P2 issues
  Task 4: Settings page (key rotation + GDPR deletion) ──→ implement + test

Phase B (after Phase A remediation):
  Task 5: Error/empty states ──→ implement (informed by UX audit findings)

Task 6: Onboarding walkthrough ──→ DEFERRED to post-beta
```

## Acceptance Criteria

- [ ] OWASP Top 10 audit completed, 0 critical/high findings open
- [ ] CSP headers verified on all response types (middleware, API, error pages)
- [ ] CORS validation on all mutating API endpoints
- [ ] WebSocket idle timeout closes connections after configurable period (default 30min)
- [ ] Inactivity timeout reduced from 24h to 2h for waiting_for_user conversations
- [ ] All Phase 1 screens reviewed by ux-design-lead
- [ ] User settings page accessible at `/dashboard/settings`
- [ ] API key rotation works (validate + encrypt + upsert)
- [ ] Account deletion purges all user data (workspace, DB records, auth record)
- [ ] Account deletion redirects to login with confirmation, no stale cookie errors
- [ ] Error states visible for: connection failure, agent failure, network loss, invalid key, rate limit
- [ ] Empty states visible for: no conversations, empty KB, no API key
- [ ] All new code has corresponding test files

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The existing security posture is strong (sandbox with symlink resolution, HKDF per-user keys, 3-layer rate limiting, nonce-based CSP). The main gaps are session lifecycle management (idle timeout, max lifetime) and the account deletion cascade. The agent sandbox correctly uses deny-by-default for unknown tools. The BYOK implementation follows RFC 5869 correctly (userId in info, empty salt for high-entropy IKM). Risk areas: the TOCTOU gap in sandbox.ts (mitigated by bubblewrap), and the 24h inactivity timeout being too generous for beta.

### Legal (CLO)

**Status:** reviewed
**Assessment:** GDPR Article 17 (right to erasure) is the primary legal requirement. The deletion cascade must cover: workspace files, all database rows (users, api_keys, conversations, messages), and the Supabase auth record. The ON DELETE CASCADE foreign keys handle the database side. Workspace file deletion must be verified (no backup or replica that retains data). Privacy Policy and Data Protection Disclosure should be updated to document the deletion mechanism (roadmap items 2.7-2.9 cover this separately). No new data processing activities introduced by this plan.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo
**Skipped specialists:** ux-design-lead (will be invoked during Task 4 execution, not during planning), copywriter (no content-heavy pages — settings and error states use functional copy)
**Pencil available:** N/A

#### Findings

**spec-flow-analyzer:** The account deletion flow has a critical UX gap: after deletion, the user is redirected to `/login` but the middleware will try to read a cookie for a deleted user. The callback and login pages must handle the case where the auth cookie references a non-existent user gracefully (redirect to login without error, clear stale cookies). The onboarding walkthrough must not block chat functionality — it should be dismissible at any step.

**CPO:** The settings page is the first "account management" surface in the product. It establishes the pattern for all future settings (notification preferences, team management, billing). Design it as a tabbed or sectioned layout that can grow, not a flat page with two sections. The GDPR deletion flow needs a "data export" callout even if not implemented yet — acknowledge Article 20 exists and is coming.

## Test Scenarios

### Task 1: Security Audit + CSP/CORS

- Given the security audit reviews all OWASP categories, when findings are reported, then each finding has a severity rating and a GitHub issue
- Given a path traversal attempt via `../../etc/passwd` in a tool input, when the sandbox checks it, then it is denied and logged
- Given a POST request to `/api/keys` with a spoofed Origin header, then the request returns 403
- Given any HTTP response from the application, then the `Content-Security-Policy` header is present

### Task 2: Session Timeout

- Given a WebSocket connection with no user messages for 30 minutes, when the idle timeout fires, then the connection is closed with `IDLE_TIMEOUT` code
- Given the user sends a message during an active session, when the idle timer is running, then the timer resets to the full idle timeout period
- Given the client receives an idle timeout close, when it processes the close event, then it shows "Session expired due to inactivity" and offers a reconnect button

### Task 4: Account Deletion

- Given an authenticated user on the settings page, when they click "Delete Account" and confirm by typing their email, then the API deletes workspace, DB records, and auth record
- Given an unauthenticated request to POST `/api/account/delete`, then it returns 401
- Given a request with wrong CSRF origin to the delete endpoint, then it returns 403
- Given an account deletion succeeds, when the user is redirected to `/login`, then no stale auth cookie errors are shown
- Given an account deletion is in progress, when another request arrives, then it is rate-limited

### Task 4: API Key Rotation

- Given a user with an existing valid key, when they submit a new key via settings, then the old key is replaced and the new key is validated and encrypted
- Given a user submits an invalid Anthropic key, then the UI shows "Invalid key" and does not store it

### Task 5: Error States

- Given the WebSocket connection fails, when the chat page renders, then an error card with "Connection failed" and a retry button is shown
- Given the agent returns an `error` message with `errorCode: "key_invalid"`, then the chat shows an inline card linking to settings

## References

- Issue: [#674](https://github.com/jikig-ai/soleur/issues/674)
- PR: [#1361](https://github.com/jikig-ai/soleur/pulls/1361)
- OWASP Top 10 2021: [owasp.org/Top10](https://owasp.org/Top10/)
- GDPR Article 17: Right to erasure
- Existing security learnings: `knowledge-base/project/learnings/2026-03-20-*.md` (CSP, nonce, security headers)
- Constitution: `knowledge-base/project/constitution.md` (security patterns, testing conventions)
- Roadmap: `knowledge-base/product/roadmap.md` (Phase 2 table)
