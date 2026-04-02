---
title: "feat: Phase 2 — Security audit, GDPR, onboarding (beta gate)"
type: feat
date: 2026-04-02
semver: minor
---

# Phase 2: Security Audit, GDPR, Onboarding (Beta Gate)

## Overview

Phase 2 is the mandatory gate before inviting beta users. It covers seven workstreams: OWASP security audit, CSP/CORS hardening, session timeout + WebSocket expiry, UX audit of Phase 1 screens, user settings page (API key rotation, GDPR account deletion), error/empty states, and first-time onboarding. All items in this plan are traced to [#674](https://github.com/jikig-ai/soleur/issues/674) and the Phase 2 milestone.

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

Seven tasks organized in dependency order. Tasks 1-3 are security hardening (can partially parallelize). Task 4 is UX audit (can run in parallel with 1-3). Tasks 5-7 depend on having the security foundation stable.

### Task 1: Security Audit (OWASP Top 10)

**Scope:** Systematic review of the existing codebase against OWASP Top 10 2021, focusing on the attack surfaces specific to this application: WebSocket handler, API routes, agent sandbox, BYOK key handling, workspace isolation.

**Approach:** Inline findings only (constitution: never persist aggregated security findings to files in an open-source repository). Create GitHub issues for each finding.

**Checklist:**

- [ ] **A01:2021 Broken Access Control** — Verify RLS policies on all Supabase tables. Check that conversation ownership is enforced on resume_session. Verify workspace isolation in sandbox.ts resolves symlinks correctly.
- [ ] **A02:2021 Cryptographic Failures** — Review BYOK encryption (AES-256-GCM + HKDF). Verify IV is random per encryption, auth tags are validated, key derivation uses proper info parameter per RFC 5869. Check TLS enforcement (HSTS preload).
- [ ] **A03:2021 Injection** — Review Bash command execution in agent-runner. Verify execFileSync usage (not exec). Check SQL injection vectors (Supabase client parameterizes, but verify custom queries). Review message content handling in ws-handler.
- [ ] **A04:2021 Insecure Design** — Review the agent permission model (canUseTool). Verify deny-by-default for unknown tools. Check that the Agent tool spawns subagents with parent sandbox constraints.
- [ ] **A05:2021 Security Misconfiguration** — Verify CSP headers on all response paths (middleware, static, API). Check CORS validation covers all API routes. Verify no debug endpoints exposed in production.
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

**Acceptance criteria:**

- [ ] All 10 OWASP categories reviewed with findings documented as GitHub issues
- [ ] 0 critical or high severity findings remain open after remediation
- [ ] Medium/low findings tracked with milestone assignment

### Task 2: CSP Headers + CORS Hardening

**Scope:** Verify existing CSP and CORS coverage is complete. The foundation is already strong (nonce-based strict-dynamic CSP, origin validation). This task is about gap-filling.

**Work items:**

- [ ] Audit all response paths for CSP header presence: middleware responses, API route responses (Next.js Route Handlers bypass middleware for direct responses), static file responses, error pages (`error.tsx`, `global-error.tsx`)
- [ ] Verify `connect-src` includes all legitimate WebSocket origins (dev and prod)
- [ ] Add `report-to` directive alongside `report-uri` for CSP Level 3 (Reporting API v1)
- [ ] Verify CORS preflight handling on all API routes that accept POST/PUT/DELETE
- [ ] Verify the Stripe webhook endpoint (`/api/webhooks/stripe`) correctly handles origin-less requests (webhooks have no Origin header)
- [ ] Add integration test: CSP header present on every response type

**Files to modify:**

- `lib/csp.ts` — Add report-to directive
- `test/csp.test.ts` — Additional coverage for response paths
- API route handlers — Verify origin validation on all mutating endpoints

### Task 3: Session Timeout + WebSocket Expiry

**Scope:** Add configurable idle timeout and maximum connection lifetime to the WebSocket handler.

**Current state:**

- Auth timeout: 5s (existing)
- Heartbeat: 30s ping (existing)
- Disconnect grace: 30s (existing)
- Inactivity timeout: 24h for waiting_for_user conversations (existing, too long for beta)

**Work items:**

- [ ] Add `WS_IDLE_TIMEOUT_MS` env var (default: 30 minutes). Track last user message timestamp per session. Close with a new `WS_CLOSE_CODES.IDLE_TIMEOUT` code when exceeded.
- [ ] Add `WS_MAX_LIFETIME_MS` env var (default: 8 hours). Close with `WS_CLOSE_CODES.MAX_LIFETIME` code when connection age exceeds limit.
- [ ] Add `SESSION_EXPIRED` close code and client-side handling in `ws-client.ts` — show "Session expired" message and offer reconnect.
- [ ] Reduce inactivity timeout from 24h to 2h for waiting_for_user conversations.
- [ ] Send a `session_expiring` warning message 2 minutes before idle timeout fires, giving the client time to show a warning toast.
- [ ] Add tests for idle timeout, max lifetime, and warning message timing.

**Files to modify:**

- `server/ws-handler.ts` — Add idle tracking, max lifetime timer, warning message
- `lib/types.ts` — Add new WS_CLOSE_CODES
- `lib/ws-client.ts` — Handle new close codes (display reason, offer reconnect)
- `server/agent-runner.ts` — Reduce INACTIVITY_TIMEOUT_MS
- `test/ws-protocol.test.ts` — Timeout and expiry tests

### Task 4: UX Audit of Phase 1 Screens

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

**Acceptance criteria:**

- [ ] All 9 screens reviewed by ux-design-lead
- [ ] 0 P1 UX issues remain (blocks beta)
- [ ] P2 issues either fixed or tracked as GitHub issues
- [ ] Accessibility: all interactive elements have labels, color contrast meets AA, keyboard navigation works

### Task 5: User Settings Page (API Key Rotation + GDPR Account Deletion)

**Scope:** New `/dashboard/settings` page with two sections: API key management and account management (GDPR).

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

### Task 6: Error States and Empty States

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

### Task 7: First-Time Onboarding Walkthrough

**Scope:** Guide new users through their first session: explain the Command Center, demonstrate @-mentions, surface key features.

**Approach:** Lightweight, non-blocking tooltip walkthrough (not a modal wizard). Triggered on first dashboard visit. Tracks completion in localStorage (no database state needed for MVP).

**Steps in walkthrough:**

1. **Welcome** — "Welcome to your Command Center. Your 8 department leaders are ready."
2. **Chat input** — "Type your question here. Your leaders will auto-route to the right experts."
3. **@-mention** — "Type @ to direct your question to a specific leader."
4. **Suggested prompts** — "Or start with one of these templates."
5. **PWA install** — (iOS only) "Add to Home Screen for the best experience." Show iOS-specific instructions (Share > Add to Home Screen).

**Implementation:**

- [ ] Create `components/onboarding/walkthrough.tsx` — Tooltip overlay component
- [ ] Create `lib/onboarding.ts` — localStorage state management (`onboarding_completed` flag)
- [ ] Modify `app/(dashboard)/dashboard/page.tsx` — Mount walkthrough on first visit
- [ ] Add iOS PWA detection (`navigator.standalone === undefined && /iPad|iPhone/.test(navigator.userAgent)`)
- [ ] Add "Skip walkthrough" and "Don't show again" options
- [ ] Test: walkthrough shows on first visit, does not show on subsequent visits

## Non-Goals

- **Full offline mode** — PWA offline support is Phase 1 scope (#1042), not Phase 2
- **Conversation history export** — GDPR Article 20 (data portability) is a valid requirement but deferred to Phase 3. Account deletion (Article 17) is the beta gate requirement.
- **Multi-factor authentication** — Beyond scope for beta. Supabase auth handles this if enabled later.
- **Automated penetration testing** — Manual OWASP audit is sufficient for beta. Automated scanning (ZAP, Nuclei) deferred to Phase 3.
- **Admin dashboard** — No admin UI for managing users. Server-side Supabase queries suffice for beta.
- **Audit logging to external SIEM** — Sentry + Better Stack structured logging is sufficient. External SIEM integration deferred.

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
Phase A (parallel):
  Task 1: Security audit ──→ remediate findings
  Task 2: CSP/CORS gaps ──→ fix gaps
  Task 3: Session timeout ──→ implement + test

Phase B (parallel, after Phase A stable):
  Task 4: UX audit ──→ fix P1/P2 issues
  Task 5: Settings page ──→ implement + test

Phase C (after Phase B):
  Task 6: Error/empty states ──→ implement
  Task 7: Onboarding walkthrough ──→ implement + test
```

## Acceptance Criteria

- [ ] OWASP Top 10 audit completed, 0 critical/high findings open
- [ ] CSP headers verified on all response types (middleware, API, error pages)
- [ ] CORS validation on all mutating API endpoints
- [ ] WebSocket idle timeout closes connections after configurable period
- [ ] WebSocket max lifetime enforced
- [ ] Session expiry warning sent before timeout
- [ ] All Phase 1 screens reviewed by ux-design-lead
- [ ] User settings page accessible at `/dashboard/settings`
- [ ] API key rotation works (validate + encrypt + upsert)
- [ ] Account deletion purges all user data (workspace, DB records, auth record)
- [ ] Account deletion redirects to login with confirmation
- [ ] Error states visible for: connection failure, agent failure, network loss, invalid key, rate limit
- [ ] Empty states visible for: no conversations, empty KB, no API key
- [ ] First-time onboarding walkthrough triggers on first dashboard visit
- [ ] Onboarding can be skipped and does not re-trigger
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

### Task 1: Security Audit

- Given the security audit agent reviews all OWASP categories, when findings are reported, then each finding has a severity rating and a GitHub issue
- Given a path traversal attempt via `../../etc/passwd` in a tool input, when the sandbox checks it, then it is denied and logged

### Task 3: Session Timeout

- Given a WebSocket connection with no user messages for 30 minutes, when the idle timeout fires, then the server sends a `session_expiring` warning 2 minutes before closing
- Given a WebSocket connection that has been open for 8 hours, when the max lifetime is reached, then the connection is closed with `MAX_LIFETIME` code
- Given the client receives a `session_expiring` message, when the user sends a message before timeout, then the idle timer resets and the session continues
- Given the client receives an idle timeout close, when it processes the close event, then it shows "Session expired" and offers a reconnect button

### Task 5: Account Deletion

- Given an authenticated user on the settings page, when they click "Delete Account" and confirm by typing their email, then the API deletes workspace, DB records, and auth record
- Given an unauthenticated request to POST `/api/account/delete`, then it returns 401
- Given a request with wrong CSRF origin to the delete endpoint, then it returns 403
- Given an account deletion succeeds, when the user is redirected to `/login`, then no stale auth cookie errors are shown
- Given an account deletion is in progress, when another request arrives, then it is rate-limited

### Task 5: API Key Rotation

- Given a user with an existing valid key, when they submit a new key via settings, then the old key is replaced and the new key is validated and encrypted
- Given a user submits an invalid Anthropic key, then the UI shows "Invalid key" and does not store it

### Task 6: Error States

- Given the WebSocket connection fails, when the chat page renders, then an error card with "Connection failed" and a retry button is shown
- Given the agent returns an `error` message with `errorCode: "key_invalid"`, then the chat shows an inline card linking to settings

### Task 7: Onboarding

- Given a user visits the dashboard for the first time, when the page loads, then the onboarding walkthrough tooltip appears
- Given the user clicks "Skip", then the walkthrough closes and `onboarding_completed` is set in localStorage
- Given the user visits the dashboard a second time, when `onboarding_completed` is true, then no walkthrough appears

## References

- Issue: [#674](https://github.com/jikig-ai/soleur/issues/674)
- PR: [#1361](https://github.com/jikig-ai/soleur/pulls/1361)
- OWASP Top 10 2021: [owasp.org/Top10](https://owasp.org/Top10/)
- GDPR Article 17: Right to erasure
- Existing security learnings: `knowledge-base/project/learnings/2026-03-20-*.md` (CSP, nonce, security headers)
- Constitution: `knowledge-base/project/constitution.md` (security patterns, testing conventions)
- Roadmap: `knowledge-base/product/roadmap.md` (Phase 2 table)
