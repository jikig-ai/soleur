# Tasks: Phase 2 — Security Audit, GDPR, Onboarding (Beta Gate)

Source: `knowledge-base/project/plans/2026-04-02-feat-phase2-security-gdpr-onboarding-beta-gate-plan.md`
Issue: [#674](https://github.com/jikig-ai/soleur/issues/674)
PR: [#1361](https://github.com/jikig-ai/soleur/pulls/1361)

## Phase A: Security Hardening (parallel)

### 1. Security Audit (OWASP Top 10)

- [ ] 1.1 A01 Broken Access Control — Verify RLS policies, conversation ownership, workspace isolation
- [ ] 1.2 A02 Cryptographic Failures — Review BYOK (AES-256-GCM + HKDF), IV randomness, auth tag validation, TLS/HSTS
- [ ] 1.3 A03 Injection — Review execFileSync usage, SQL parameterization, message content handling
- [ ] 1.4 A04 Insecure Design — Verify canUseTool deny-by-default, Agent tool subagent sandbox inheritance
- [ ] 1.5 A05 Security Misconfiguration — Verify CSP on all paths, CORS coverage, no debug endpoints in prod
- [ ] 1.6 A06 Vulnerable Components — Run npm audit, verify dependency pinning (bunfig.toml), Dockerfile base image
- [ ] 1.7 A07 Auth Failures — Review WS auth token validation, session fixation vectors, token per-connection validation
- [ ] 1.8 A08 Integrity Failures — Review CI pipeline, workflow permissions, input validation
- [ ] 1.9 A09 Logging Failures — Verify Sentry captures rate limit, auth failure, sandbox denial events
- [ ] 1.10 A10 SSRF — Review Anthropic API validation endpoint, URL construction from user input
- [ ] 1.11 Remediate all critical/high findings (create GitHub issues for each)

### 2. CSP + CORS Hardening

- [ ] 2.1 Audit all response paths for CSP header presence (middleware, API routes, error pages, static)
- [ ] 2.2 Verify `connect-src` covers all WebSocket origins (dev: ws://localhost:3000, prod: wss://app.soleur.ai)
- [ ] 2.3 Add `report-to` directive for CSP Level 3 Reporting API
- [ ] 2.4 Verify CORS preflight handling on all mutating API routes (POST/PUT/DELETE)
- [ ] 2.5 Verify Stripe webhook handles origin-less requests correctly
- [ ] 2.6 Add integration test: CSP header present on every response type
- [ ] 2.7 Update `test/csp.test.ts` with new coverage

### 3. Session Timeout + WebSocket Expiry

- [ ] 3.1 Add `WS_IDLE_TIMEOUT_MS` env var (default 30min), track last user message timestamp
- [ ] 3.2 Add `WS_MAX_LIFETIME_MS` env var (default 8h), close on max lifetime
- [ ] 3.3 Add new WS_CLOSE_CODES: `IDLE_TIMEOUT`, `MAX_LIFETIME`, `SESSION_EXPIRED`
- [ ] 3.4 Send `session_expiring` warning 2min before idle timeout fires
- [ ] 3.5 Handle new close codes in `ws-client.ts` (show reason, offer reconnect)
- [ ] 3.6 Reduce inactivity timeout from 24h to 2h for waiting_for_user conversations
- [ ] 3.7 Write tests: `test/ws-protocol.test.ts` — idle timeout, max lifetime, warning message

## Phase B: UX + Settings (parallel, after Phase A stable)

### 4. UX Audit of Phase 1 Screens

- [ ] 4.1 Invoke ux-design-lead on login page (`app/(auth)/login/page.tsx`)
- [ ] 4.2 Invoke ux-design-lead on signup page (`app/(auth)/signup/page.tsx`)
- [ ] 4.3 Invoke ux-design-lead on accept-terms page
- [ ] 4.4 Invoke ux-design-lead on setup-key page
- [ ] 4.5 Invoke ux-design-lead on connect-repo page
- [ ] 4.6 Invoke ux-design-lead on dashboard page
- [ ] 4.7 Invoke ux-design-lead on chat page
- [ ] 4.8 Invoke ux-design-lead on KB viewer page
- [ ] 4.9 Invoke ux-design-lead on billing page
- [ ] 4.10 Prioritize findings: P1 (blocks beta), P2 (should fix), P3 (post-beta)
- [ ] 4.11 Implement all P1 UX fixes
- [ ] 4.12 Implement P2 UX fixes (or create tracking issues)

### 5. User Settings Page (API Key Rotation + GDPR Deletion)

- [ ] 5.1 Create `app/(dashboard)/dashboard/settings/page.tsx` — tabbed/sectioned layout
- [ ] 5.2 Implement API key status display (valid/invalid, provider, last validated)
- [ ] 5.3 Implement key rotation flow (validate → encrypt → upsert)
- [ ] 5.4 Implement key deletion
- [ ] 5.5 Create `app/api/account/delete/route.ts` — account deletion endpoint
  - [ ] 5.5.1 Origin validation + auth check + rate limiting
  - [ ] 5.5.2 Abort active agent session
  - [ ] 5.5.3 Delete workspace directory
  - [ ] 5.5.4 Delete database records (cascade)
  - [ ] 5.5.5 Delete Supabase auth record
- [ ] 5.6 Add `deleteWorkspace(userId)` to `server/workspace.ts`
- [ ] 5.7 Implement confirmation dialog (type email to confirm)
- [ ] 5.8 Redirect to `/login` with "Account deleted" flash after success
- [ ] 5.9 Handle stale auth cookies on `/login` after deletion
- [ ] 5.10 Add settings link to dashboard layout navigation
- [ ] 5.11 Write tests: `test/settings-page.test.tsx`, `test/account-delete.test.ts`
- [ ] 5.12 Add data export callout (Article 20 acknowledgment, not implemented yet)

## Phase C: Polish (after Phase B)

### 6. Error States and Empty States

- [ ] 6.1 Create `components/ui/error-card.tsx` — reusable error display component
- [ ] 6.2 Chat page: connection failure error card with retry
- [ ] 6.3 Chat page: agent failure error card (key_invalid → link to settings)
- [ ] 6.4 Chat page: network loss banner with manual retry
- [ ] 6.5 Chat page: rate limited message with countdown
- [ ] 6.6 Update `app/error.tsx` — branded error boundary
- [ ] 6.7 Update `app/global-error.tsx` — minimal recovery UI
- [ ] 6.8 Dashboard: first-visit welcome copy
- [ ] 6.9 KB viewer: empty state with explanation
- [ ] 6.10 Settings: no API key configured state
- [ ] 6.11 Surface specific error codes from `ws-client.ts` to UI components

### 7. First-Time Onboarding Walkthrough

- [ ] 7.1 Create `lib/onboarding.ts` — localStorage state management
- [ ] 7.2 Create `components/onboarding/walkthrough.tsx` — tooltip overlay component
- [ ] 7.3 Step 1: Welcome message
- [ ] 7.4 Step 2: Chat input highlight
- [ ] 7.5 Step 3: @-mention demonstration
- [ ] 7.6 Step 4: Suggested prompts highlight
- [ ] 7.7 Step 5: iOS PWA install guidance (conditional on iOS Safari)
- [ ] 7.8 Add skip/dismiss controls
- [ ] 7.9 Mount walkthrough in `app/(dashboard)/dashboard/page.tsx`
- [ ] 7.10 Write tests: `test/onboarding.test.tsx`
