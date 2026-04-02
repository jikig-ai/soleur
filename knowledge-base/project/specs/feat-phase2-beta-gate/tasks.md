# Tasks: Phase 2 — Security Audit, GDPR, Onboarding (Beta Gate)

Source: `knowledge-base/project/plans/2026-04-02-feat-phase2-security-gdpr-onboarding-beta-gate-plan.md`
Issue: [#674](https://github.com/jikig-ai/soleur/issues/674)
PR: [#1361](https://github.com/jikig-ai/soleur/pulls/1361)

## Phase A: All Tasks (parallel)

### 1. Security Audit (OWASP Top 10 + CSP/CORS Verification)

- [ ] 1.1 A01 Broken Access Control — Verify RLS policies, conversation ownership, workspace isolation
- [ ] 1.2 A02 Cryptographic Failures — Review BYOK (AES-256-GCM + HKDF), IV randomness, auth tag validation, TLS/HSTS
- [ ] 1.3 A03 Injection — Review execFileSync usage, SQL parameterization, message content handling
- [ ] 1.4 A04 Insecure Design — Verify canUseTool deny-by-default, Agent tool subagent sandbox inheritance
- [ ] 1.5 A05 Security Misconfiguration — Verify CSP on all response paths (middleware, API Route Handlers, error pages, static). Verify connect-src WebSocket origins. CORS preflight on all mutating routes. Stripe webhook origin-less handling. Integration test for CSP header presence.
- [ ] 1.6 A06 Vulnerable Components — Run npm audit, verify dependency pinning (bunfig.toml), Dockerfile base image
- [ ] 1.7 A07 Auth Failures — Review WS auth token validation, session fixation vectors, token per-connection validation
- [ ] 1.8 A08 Integrity Failures — Review CI pipeline, workflow permissions, input validation
- [ ] 1.9 A09 Logging Failures — Verify Sentry captures rate limit, auth failure, sandbox denial events
- [ ] 1.10 A10 SSRF — Review Anthropic API validation endpoint, URL construction from user input
- [ ] 1.11 Remediate all critical/high findings (create GitHub issues for each)
- [ ] 1.12 Update `test/csp.test.ts` with CSP/CORS response path coverage

### 2. Session Timeout + WebSocket Idle Expiry

- [x] 2.1 Add `WS_IDLE_TIMEOUT_MS` env var (default 30min), track last user message timestamp
- [x] 2.2 Add `IDLE_TIMEOUT` close code to `lib/types.ts`
- [x] 2.3 Handle idle timeout close code in `ws-client.ts` (show reason, offer reconnect)
- [x] 2.4 Reduce inactivity timeout from 24h to 2h for waiting_for_user conversations
- [x] 2.5 Write tests: `test/ws-protocol.test.ts` — idle timeout, timer reset on user message

### 3. UX Audit of Phase 1 Screens

- [ ] 3.1 Invoke ux-design-lead on login page (`app/(auth)/login/page.tsx`)
- [ ] 3.2 Invoke ux-design-lead on signup page (`app/(auth)/signup/page.tsx`)
- [ ] 3.3 Invoke ux-design-lead on accept-terms page
- [ ] 3.4 Invoke ux-design-lead on setup-key page
- [ ] 3.5 Invoke ux-design-lead on connect-repo page
- [ ] 3.6 Invoke ux-design-lead on dashboard page
- [ ] 3.7 Invoke ux-design-lead on chat page
- [ ] 3.8 Invoke ux-design-lead on KB viewer page
- [ ] 3.9 Invoke ux-design-lead on billing page
- [ ] 3.10 Prioritize findings: P1 (blocks beta), P2 (should fix), P3 (post-beta)
- [ ] 3.11 Implement all P1 UX fixes
- [ ] 3.12 Implement P2 UX fixes (or create tracking issues)

### 4. User Settings Page (API Key Rotation + GDPR Deletion)

- [x] 4.1 Create `app/(dashboard)/dashboard/settings/page.tsx` — simple flat layout with section headings
- [x] 4.2 Implement API key status display (valid/invalid, provider, last validated)
- [x] 4.3 Implement key rotation flow (validate -> encrypt -> upsert)
- [x] 4.4 Implement key deletion
- [x] 4.5 Create `app/api/account/delete/route.ts` — account deletion endpoint
  - [x] 4.5.1 Origin validation + auth check + rate limiting
  - [x] 4.5.2 Abort active agent session
  - [x] 4.5.3 Delete workspace directory
  - [x] 4.5.4 Delete database records (cascade from public.users)
  - [x] 4.5.5 Delete Supabase auth record (after public.users)
- [x] 4.6 Add `deleteWorkspace(userId)` to `server/workspace.ts`
- [x] 4.7 Implement confirmation dialog (type email to confirm)
- [x] 4.8 Redirect to `/login` with "Account deleted" flash after success
- [x] 4.9 Handle stale auth cookies on `/login` after deletion (clear cookie, no error)
- [x] 4.10 Add settings link to dashboard layout navigation
- [x] 4.11 Write tests: `test/settings-page.test.tsx`, `test/account-delete.test.ts`

## Phase B: Error/Empty States (after Phase A remediation)

### 5. Error States and Empty States

- [x] 5.1 Chat page: connection failure error card with retry
- [x] 5.2 Chat page: agent failure error card (key_invalid -> link to settings)
- [x] 5.3 Chat page: network loss banner with manual retry
- [x] 5.4 Chat page: rate limited message with countdown
- [x] 5.5 Update `app/error.tsx` — branded error boundary
- [x] 5.6 Update `app/global-error.tsx` — minimal recovery UI
- [x] 5.7 Dashboard: first-visit welcome copy
- [x] 5.8 KB viewer: empty state with explanation
- [x] 5.9 Settings: no API key configured state
- [x] 5.10 Surface specific error codes from `ws-client.ts` to UI components

## Deferred: Onboarding Walkthrough

Task 6 (first-time onboarding walkthrough) deferred to post-beta. Existing dashboard copy with suggested prompts and @-mention hints is sufficient for fewer than 10 invited founders. Tracking issue to be created.
