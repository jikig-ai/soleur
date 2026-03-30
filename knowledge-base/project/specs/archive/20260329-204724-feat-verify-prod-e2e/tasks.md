# Tasks: verify production deployment end-to-end loop

## Phase 1: Investigation and Diagnostics

- [ ] 1.1 Query Supabase REST API directly to confirm connectivity status
  - [ ] 1.1.1 Get `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` from Doppler `prd`
  - [ ] 1.1.2 `curl -s -H "apikey: <anon_key>" "<supabase_url>/rest/v1/"` and verify response
  - [ ] 1.1.3 Document finding: connectivity OK or identify root cause of "error" status
- [ ] 1.2 CSP `wss://localhost:3000` -- ROOT CAUSE CONFIRMED
  - [ ] 1.2.1 Root cause: `request.nextUrl.host` in `middleware.ts` returns `localhost:3000` behind proxy
  - [ ] 1.2.2 Fix: use `request.headers.get('x-forwarded-host') ?? request.headers.get('host')` instead
  - [ ] 1.2.3 Callback route already uses correct pattern via `resolveOrigin()` in `lib/auth/resolve-origin.ts`
- [ ] 1.3 Check Sentry for recent production errors
  - [ ] 1.3.1 Get `SENTRY_API_TOKEN` from Doppler `prd`
  - [ ] 1.3.2 Query Sentry issues API for web-platform project (unresolved, last 7 days)
  - [ ] 1.3.3 Document any blocking errors
- [ ] 1.4 Verify health endpoint version matches latest deploy
  - [ ] 1.4.1 `curl https://app.soleur.ai/health` and check version field
  - [ ] 1.4.2 Compare with `gh release list --limit 1`

## Phase 2: Fix Blockers

- [ ] 2.1 Fix CSP `appHost` resolution in `middleware.ts` (CONFIRMED REQUIRED)
  - [ ] 2.1.1 Replace `request.nextUrl.host` with `request.headers.get('x-forwarded-host') ?? request.headers.get('host') ?? request.nextUrl.host`
  - [ ] 2.1.2 Verify fix locally with simulated proxy headers
  - [ ] 2.1.3 Deploy fix and verify `curl -s -I https://app.soleur.ai/signup | grep connect-src` shows `wss://app.soleur.ai`
- [ ] 2.2 Fix Supabase connectivity (if confirmed broken in 1.1)
  - [ ] 2.2.1 Identify root cause (env var, network, project paused)
  - [ ] 2.2.2 Apply fix
  - [ ] 2.2.3 Verify `/health` returns `supabase: "connected"`

## Phase 3: End-to-End Verification via Playwright MCP

- [ ] 3.1 AC6: Console errors check (baseline)
  - [ ] 3.1.1 Navigate to `/login` with Playwright, capture console messages
  - [ ] 3.1.2 Navigate to `/signup`, capture console messages
  - [ ] 3.1.3 Verify zero `console.error` and zero CSP violations ("Refused to")
  - [ ] 3.1.4 Take screenshots of each page
- [ ] 3.2 AC1: Mobile signup
  - [ ] 3.2.1 Set Playwright viewport to 375x812 (iPhone-sized)
  - [ ] 3.2.2 Navigate to `https://app.soleur.ai/signup`
  - [ ] 3.2.3 Verify form renders: email input, T&C checkbox, submit button
  - [ ] 3.2.4 Enter test email, check T&C, submit
  - [ ] 3.2.5 Verify "Check your email" confirmation
  - [ ] 3.2.6 Take screenshot
- [ ] 3.3 Create authenticated session via Supabase admin API
  - [ ] 3.3.1 Use `generateLink` admin API with `SERVICE_ROLE_KEY` from Doppler `prd`
  - [ ] 3.3.2 Navigate Playwright to the returned `action_link` URL
  - [ ] 3.3.3 Verify auth callback completes and session cookie is set
  - [ ] 3.3.4 Note: cleanup test user after all tests via admin DELETE endpoint
- [ ] 3.4 AC7: Accept-terms page
  - [ ] 3.4.1 Navigate to `/accept-terms` (new user, TC not accepted yet)
  - [ ] 3.4.2 Verify T&C content renders with checkbox and "Accept and continue" button
  - [ ] 3.4.3 Check checkbox, click accept, verify redirect to `/setup-key`
  - [ ] 3.4.4 Take screenshot
- [ ] 3.5 AC2: BYOK key entry
  - [ ] 3.5.1 Navigate to `/setup-key` (authenticated, TC accepted)
  - [ ] 3.5.2 Enter Anthropic API key (`ANTHROPIC_API_KEY` from Doppler `prd`)
  - [ ] 3.5.3 Submit and verify "Key is valid. Redirecting..." message
  - [ ] 3.5.4 Verify redirect to `/connect-repo`
  - [ ] 3.5.5 Take screenshot
- [ ] 3.6 AC8: Connect-repo page
  - [ ] 3.6.1 Verify redirect landed on `/connect-repo`
  - [ ] 3.6.2 Verify page renders with repo connection options
  - [ ] 3.6.3 Verify skip/continue flow proceeds to `/dashboard`
  - [ ] 3.6.4 Take screenshot
- [ ] 3.7 AC3: WebSocket connection stability
  - [ ] 3.7.1 Navigate to `/dashboard/chat/new`
  - [ ] 3.7.2 Verify green "Connected" status dot appears
  - [ ] 3.7.3 Wait 30 seconds, checking status every 5 seconds
  - [ ] 3.7.4 Verify status remains "Connected" (no cycling to "Reconnecting")
  - [ ] 3.7.5 Take screenshot
- [ ] 3.8 AC4: Agent response latency
  - [ ] 3.8.1 In connected chat, type "What is your role?" and click Send
  - [ ] 3.8.2 Record timestamp, wait for assistant message bubble to appear (max 10s)
  - [ ] 3.8.3 Verify response content is meaningful (not error message, contains domain text)
  - [ ] 3.8.4 Verify response completes (stream ends, no "..." indefinitely)
  - [ ] 3.8.5 Take screenshot of completed response
- [ ] 3.9 AC5: Session persistence (EXPECTED FAIL -- missing feature)
  - [ ] 3.9.1 Note: chat page does NOT load history on mount (confirmed by code review)
  - [ ] 3.9.2 Server API exists (`GET /api/conversations/:id/messages`) but client does not call it
  - [ ] 3.9.3 Refresh page and confirm messages are lost (documents the gap)
  - [ ] 3.9.4 File GitHub issue: "feat: load conversation history on page mount" milestone Phase 1
  - [ ] 3.9.5 Take screenshot showing empty chat after refresh

## Phase 4: Documentation and Closure

- [ ] 4.1 Record pass/fail for each AC in GitHub issue #1075
- [ ] 4.2 Attach key screenshots to issue
- [ ] 4.3 File tracking issue for AC5 (session persistence) missing feature
- [ ] 4.4 Close issue #1075 (AC5 expected fail does not block -- tracked separately)
- [ ] 4.5 Update roadmap.md item 1.7 status to "Done"
- [ ] 4.6 Cleanup: delete test user via Supabase admin API
