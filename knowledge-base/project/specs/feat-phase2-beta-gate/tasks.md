# Tasks: Phase 2 Security Audit, GDPR, Onboarding

Issue: [#674](https://github.com/jikig-ai/soleur/issues/674)
Plan: `knowledge-base/project/plans/2026-03-30-feat-phase2-security-gdpr-onboarding-plan.md`

## Phase 1: Security Audit (TG-1)

### 1.1 OWASP Top 10 Code Review

- [ ] 1.1.1 A01 Broken Access Control: Audit RLS policies on all 4 tables (users, api_keys, conversations, messages) -- verify user_id ownership checks prevent cross-user access
- [ ] 1.1.2 A01 Broken Access Control: Verify conversation ownership check in `resume_session` handler (ws-handler.ts:207-234)
- [ ] 1.1.3 A01 Broken Access Control: Verify workspace isolation -- user A cannot read/write user B's workspace via agent tools
- [ ] 1.1.4 A02 Cryptographic Failures: Audit BYOK key handling -- verify no plaintext key in logs, error messages, or Sentry breadcrumbs
- [ ] 1.1.5 A02 Cryptographic Failures: Verify HKDF salt/info usage follows RFC 5869 (already uses empty salt + userId in info per constitution)
- [ ] 1.1.6 A03 Injection: Audit all `execFileSync` calls in workspace.ts -- verify no user input reaches command arguments without validation
- [ ] 1.1.7 A03 Injection: Verify WebSocket message parsing rejects non-JSON and oversized payloads
- [ ] 1.1.8 A04 Insecure Design: Review agent `maxBudgetUsd` and `maxTurns` limits -- verify they prevent runaway costs
- [ ] 1.1.9 A05 Security Misconfiguration: Verify sandbox `denyRead` blocks `/proc` for all PIDs (not just `/proc/self`)
- [ ] 1.1.10 A07 Auth Failures: Verify auth timeout (5s) prevents slow-loris attacks on WebSocket
- [ ] 1.1.11 A07 Auth Failures: Verify T&C enforcement on both HTTP (middleware.ts) and WS (ws-handler.ts) surfaces
- [ ] 1.1.12 A08 Data Integrity: Verify Stripe webhook signature validation in `api/webhooks/stripe/route.ts`
- [ ] 1.1.13 A09 Logging Failures: Verify security events are logged (rate limit rejections, auth failures, sandbox denials) without sensitive data
- [ ] 1.1.14 A10 SSRF: Verify agent network sandbox (`allowedDomains: []`, `allowManagedDomainsOnly: true`) prevents SSRF
- [ ] 1.1.15 Write test: workspace isolation -- agent cannot read another user's workspace path
- [ ] 1.1.16 Write test: BYOK error sanitization -- no key material in sanitized errors

### 1.2 Remediation

- [ ] 1.2.1 Fix any critical/high findings from 1.1 (tasks added dynamically based on audit results)
- [ ] 1.2.2 Add WebSocket message size limit (defense-in-depth against oversized payloads)

## Phase 2: CSP + CORS Hardening (TG-2)

### 2.1 CSP Enhancements

- [ ] 2.1.1 Add `Report-To` response header in middleware.ts with Sentry CSP endpoint group
- [ ] 2.1.2 Verify `report-uri` directive already uses `SENTRY_CSP_REPORT_URI` env var
- [ ] 2.1.3 Add test: `Report-To` header present in middleware response

### 2.2 CORS Configuration

- [ ] 2.2.1 Add explicit CORS headers to API routes via next.config.ts `headers()` -- restrict `Access-Control-Allow-Origin` to `https://app.soleur.ai`
- [ ] 2.2.2 Add `Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS` for API routes
- [ ] 2.2.3 Add `Access-Control-Allow-Headers: Content-Type, Authorization`
- [ ] 2.2.4 Handle OPTIONS preflight requests in API routes
- [ ] 2.2.5 Add test: CORS headers on API responses, reject disallowed origins

## Phase 3: Session Timeout + WebSocket Expiry (TG-3)

### 3.1 Server-Side Timers

- [ ] 3.1.1 Add constants: `IDLE_TIMEOUT_MS` (30 min), `ABSOLUTE_TIMEOUT_MS` (8 hours), `IDLE_WARNING_MS` (60s before expiry) to ws-handler.ts
- [ ] 3.1.2 Add `WS_CLOSE_CODES.IDLE_TIMEOUT` (4008) and `WS_CLOSE_CODES.ABSOLUTE_TIMEOUT` (4009) to lib/types.ts
- [ ] 3.1.3 Start idle and absolute timers after auth success in ws-handler.ts
- [ ] 3.1.4 Reset idle timer on every authenticated message in `handleMessage()`
- [ ] 3.1.5 Send `session_expiring` WSMessage 60s before idle timeout
- [ ] 3.1.6 Close WebSocket with appropriate code on idle/absolute timeout
- [ ] 3.1.7 Clear timers on WebSocket close/disconnect

### 3.2 Client-Side Handling

- [ ] 3.2.1 Handle `session_expiring` message in ws-client.ts -- display toast/banner
- [ ] 3.2.2 Handle idle/absolute timeout close codes -- display appropriate message
- [ ] 3.2.3 Auto-reconnect on timeout (prompt re-auth if session expired)

### 3.3 Tests

- [ ] 3.3.1 Test: idle timeout fires after 30 min of no messages
- [ ] 3.3.2 Test: message resets idle timer
- [ ] 3.3.3 Test: absolute timeout fires at 8 hours regardless of activity
- [ ] 3.3.4 Test: warning sent 60s before idle timeout
- [ ] 3.3.5 Test: timers cleared on disconnect

## Phase 4: User Settings Page + GDPR Account Deletion (TG-4)

### 4.1 Settings Page UI

- [ ] 4.1.1 Create `app/(dashboard)/dashboard/settings/page.tsx` with tabbed layout (API Keys, Account)
- [ ] 4.1.2 Add settings link to dashboard navigation in `app/(dashboard)/layout.tsx`
- [ ] 4.1.3 Add `/dashboard/settings` to `lib/routes.ts`
- [ ] 4.1.4 API Keys tab: show masked key status (has key / no key), rotate button, delete button
- [ ] 4.1.5 Account tab: show email, account created date, danger zone with delete button

### 4.2 API Key Management

- [ ] 4.2.1 Add DELETE handler to `app/api/keys/route.ts` -- set `is_valid = false`
- [ ] 4.2.2 Add origin validation to DELETE handler (same pattern as POST)
- [ ] 4.2.3 Test: key deletion sets is_valid to false
- [ ] 4.2.4 Test: key rotation replaces old key with new validated key

### 4.3 Account Deletion

- [ ] 4.3.1 Create `app/api/account/delete/route.ts` with POST handler
- [ ] 4.3.2 Require email confirmation in request body (must match authenticated user email)
- [ ] 4.3.3 Add rate limit: 3 deletion attempts per hour per user
- [ ] 4.3.4 Implement deletion cascade:
  - 4.3.4.1 Delete workspace directory (`rm -rf /workspaces/{userId}`)
  - 4.3.4.2 Delete auth.users entry via `supabase.auth.admin.deleteUser(userId)`
  - 4.3.4.3 DB cascade handles conversations, messages, api_keys via FK constraints
- [ ] 4.3.5 Return 200 with `Set-Cookie` clearing all session cookies
- [ ] 4.3.6 Log deletion event (user ID only, no PII)
- [ ] 4.3.7 Confirmation UI: modal with email re-entry, "I understand this is irreversible" checkbox
- [ ] 4.3.8 Test: full deletion cascade removes all user data
- [ ] 4.3.9 Test: email mismatch returns 400
- [ ] 4.3.10 Test: rate limit enforced on deletion endpoint

## Phase 5: Error + Empty States (TG-5)

### 5.1 Reusable Components

- [ ] 5.1.1 Create `components/ui/empty-state.tsx` -- icon, title, description, optional action button
- [ ] 5.1.2 Create `components/ui/connection-status.tsx` -- WebSocket status indicator (connected/reconnecting/disconnected)

### 5.2 WebSocket Reconnection

- [ ] 5.2.1 Add reconnection logic to `lib/ws-client.ts` with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- [ ] 5.2.2 Show connection status indicator in dashboard layout
- [ ] 5.2.3 Handle `session_ended` reason variants (idle_timeout, absolute_timeout, closed)

### 5.3 Page-Level Empty/Error States

- [ ] 5.3.1 Dashboard page: empty state for users with no conversations (point to suggested prompts)
- [ ] 5.3.2 KB page: empty state with "Your knowledge base will grow as you work with your leaders"
- [ ] 5.3.3 Chat page: agent failure error with retry button
- [ ] 5.3.4 Chat page: rate limit error with countdown timer
- [ ] 5.3.5 Chat page: session expired message with re-login link
- [ ] 5.3.6 Update `app/error.tsx` and `app/global-error.tsx` with more helpful messages

### 5.4 Tests

- [ ] 5.4.1 Test: EmptyState component renders with all prop variants
- [ ] 5.4.2 Test: ConnectionStatus shows correct state for each WebSocket readyState

## Phase 6: UX Audit (TG-6)

### 6.1 Screen-by-Screen Audit

- [ ] 6.1.1 Run ux-design-lead on login page
- [ ] 6.1.2 Run ux-design-lead on signup page
- [ ] 6.1.3 Run ux-design-lead on accept-terms page
- [ ] 6.1.4 Run ux-design-lead on setup-key page
- [ ] 6.1.5 Run ux-design-lead on connect-repo page
- [ ] 6.1.6 Run ux-design-lead on dashboard page
- [ ] 6.1.7 Run ux-design-lead on chat page
- [ ] 6.1.8 Run ux-design-lead on KB page
- [ ] 6.1.9 Run ux-design-lead on billing page
- [ ] 6.1.10 Run ux-design-lead on settings page (from TG-4)

### 6.2 Fix Critical Findings

- [ ] 6.2.1 Fix critical usability issues identified by audit (tasks added dynamically)
- [ ] 6.2.2 Verify mobile responsiveness on all screens
- [ ] 6.2.3 Add missing ARIA labels and keyboard navigation

## Phase 7: Onboarding Walkthrough (TG-7)

### 7.1 Walkthrough Component

- [ ] 7.1.1 Create `components/onboarding/walkthrough.tsx` -- step container with spotlight overlay
- [ ] 7.1.2 Create `components/onboarding/walkthrough-step.tsx` -- step content renderer
- [ ] 7.1.3 Create `lib/onboarding.ts` -- step definitions, completion tracking via localStorage

### 7.2 Step Definitions

- [ ] 7.2.1 Step 1: "Welcome to your Command Center" -- highlights chat input area
- [ ] 7.2.2 Step 2: "Mention a leader" -- highlights @-mention with example
- [ ] 7.2.3 Step 3: "Try a suggested prompt" -- highlights prompt cards
- [ ] 7.2.4 Step 4: "Your AI organization" -- highlights leader strip
- [ ] 7.2.5 Step 5 (iOS PWA): "Install as an app" -- PWA install guidance

### 7.3 Integration

- [ ] 7.3.1 Show walkthrough on first dashboard visit (check localStorage)
- [ ] 7.3.2 Skip/dismiss button on all steps
- [ ] 7.3.3 Step counter (e.g., "2 of 5")
- [ ] 7.3.4 Mark complete in localStorage on final step or dismiss

### 7.4 Tests

- [ ] 7.4.1 Test: walkthrough renders on first visit
- [ ] 7.4.2 Test: walkthrough does not render when localStorage flag is set
- [ ] 7.4.3 Test: dismiss sets localStorage flag
- [ ] 7.4.4 Test: step navigation (next, back, skip)
