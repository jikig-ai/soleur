# Tasks: verify production deployment end-to-end loop

## Phase 1: Investigation and Diagnostics

- [ ] 1.1 Query Supabase REST API directly to confirm connectivity status
  - [ ] 1.1.1 Get `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` from Doppler `prd`
  - [ ] 1.1.2 `curl` the Supabase REST API health endpoint and verify response
  - [ ] 1.1.3 Document finding: connectivity OK or identify root cause of "error" status
- [ ] 1.2 Investigate CSP `wss://localhost:3000` in production
  - [ ] 1.2.1 Check Cloudflare tunnel config for Host header forwarding
  - [ ] 1.2.2 Inspect `request.nextUrl.host` value in middleware behind Cloudflare
  - [ ] 1.2.3 Check if `X-Forwarded-Host` header is available and should be used instead
  - [ ] 1.2.4 Document finding and proposed fix
- [ ] 1.3 Check Sentry for recent production errors
  - [ ] 1.3.1 Get `SENTRY_API_TOKEN` from Doppler `prd`
  - [ ] 1.3.2 Query Sentry issues API for web-platform project
  - [ ] 1.3.3 Document any blocking errors
- [ ] 1.4 Verify health endpoint version matches latest deploy
  - [ ] 1.4.1 `curl https://app.soleur.ai/health` and check version field
  - [ ] 1.4.2 Compare with latest GitHub Release tag

## Phase 2: Fix Blockers

- [ ] 2.1 Fix CSP `appHost` resolution (if confirmed broken in 1.2)
  - [ ] 2.1.1 Update `middleware.ts` to use `X-Forwarded-Host` or `Host` header
  - [ ] 2.1.2 Verify fix locally with simulated proxy headers
  - [ ] 2.1.3 Deploy fix and verify production CSP contains `wss://app.soleur.ai`
- [ ] 2.2 Fix Supabase connectivity (if confirmed broken in 1.1)
  - [ ] 2.2.1 Identify root cause (env var, network, credentials)
  - [ ] 2.2.2 Apply fix
  - [ ] 2.2.3 Verify `/health` returns `supabase: "connected"`

## Phase 3: End-to-End Verification via Playwright MCP

- [ ] 3.1 AC6: Console errors check (baseline)
  - [ ] 3.1.1 Navigate to `/login` with Playwright, capture console
  - [ ] 3.1.2 Navigate to `/signup`, capture console
  - [ ] 3.1.3 Verify zero `console.error` and zero CSP violations
  - [ ] 3.1.4 Take screenshots of each page
- [ ] 3.2 AC1: Mobile signup
  - [ ] 3.2.1 Set Playwright viewport to 375x812 (iPhone-sized)
  - [ ] 3.2.2 Navigate to `https://app.soleur.ai/signup`
  - [ ] 3.2.3 Verify form renders: email input, T&C checkbox, submit button
  - [ ] 3.2.4 Enter test email, check T&C, submit
  - [ ] 3.2.5 Verify "Check your email" confirmation
  - [ ] 3.2.6 Take screenshot
- [ ] 3.3 Create authenticated session (for AC2-AC5)
  - [ ] 3.3.1 Use Supabase admin API (service role) to create test user or generate magic link
  - [ ] 3.3.2 Complete auth callback flow
  - [ ] 3.3.3 Verify authenticated session cookie is set
- [ ] 3.4 AC2: BYOK key entry
  - [ ] 3.4.1 Navigate to `/setup-key` (authenticated)
  - [ ] 3.4.2 Enter Anthropic API key (from Doppler `prd`)
  - [ ] 3.4.3 Submit and verify "Key is valid. Redirecting..."
  - [ ] 3.4.4 Verify redirect to `/connect-repo`
  - [ ] 3.4.5 Take screenshot
- [ ] 3.5 AC3: WebSocket connection stability
  - [ ] 3.5.1 Navigate to `/dashboard/chat/new`
  - [ ] 3.5.2 Verify green "Connected" status dot appears
  - [ ] 3.5.3 Wait 30 seconds
  - [ ] 3.5.4 Verify status remains "Connected" (no cycling)
  - [ ] 3.5.5 Take screenshot
- [ ] 3.6 AC4: Agent response latency
  - [ ] 3.6.1 In connected chat, type "What is your role?" and send
  - [ ] 3.6.2 Measure time until first assistant message bubble appears
  - [ ] 3.6.3 Verify response is meaningful (not error message)
  - [ ] 3.6.4 Verify response completes (stream_end)
  - [ ] 3.6.5 Take screenshot of completed response
- [ ] 3.7 AC5: Session persistence
  - [ ] 3.7.1 Note current URL (contains conversationId)
  - [ ] 3.7.2 Refresh page
  - [ ] 3.7.3 Verify previous messages are still visible
  - [ ] 3.7.4 Verify WebSocket reconnects (green dot)
  - [ ] 3.7.5 Take screenshot

## Phase 4: Documentation and Closure

- [ ] 4.1 Record pass/fail for each AC in GitHub issue #1075
- [ ] 4.2 Attach key screenshots to issue
- [ ] 4.3 Close issue #1075 if all pass
- [ ] 4.4 Update roadmap.md item 1.7 status to "Done"
