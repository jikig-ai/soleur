# Tasks: fix-command-center-server-error

## Phase 1: Diagnosis Confirmation

- [ ] 1.1 Use Playwright to navigate to the command center chat page and capture browser console output for CSP violation errors
- [ ] 1.2 Check Docker server logs via SSH for WebSocket close codes and error messages
- [ ] 1.3 Confirm whether the issue is CSP-related (hypothesis 1) or server-side crash (hypothesis 2)

## Phase 2: CSP Fix

- [ ] 2.1 Add `appHost` parameter to `buildCspHeader()` in `apps/web-platform/lib/csp.ts`
- [ ] 2.2 Construct `wss://<appHost>` (prod) or `ws://<appHost>` (dev) and add to `connect-src` directive
- [ ] 2.3 Update `middleware.ts` to pass `request.nextUrl.host` as `appHost` to `buildCspHeader()`
- [ ] 2.4 Update existing CSP tests to include the new `appHost` parameter in `prodCsp` and `devCsp` fixtures
- [ ] 2.5 Add new test: `connect-src includes explicit wss:// for app WebSocket origin`
- [ ] 2.6 Add new test: `connect-src includes ws:// for dev WebSocket origin`
- [ ] 2.7 Add new test: `connect-src does not use bare wss: scheme (overly permissive)`
- [ ] 2.8 Run full test suite to verify no regressions: `npm test`

## Phase 3: Server-Side Hardening (if diagnosis confirms hypothesis 2)

- [ ] 3.1 Add try-catch around the T&C version query in `ws-handler.ts` to prevent unhandled exceptions
- [ ] 3.2 Verify all async operations in the `wss.on("connection")` handler have proper error boundaries
- [ ] 3.3 Add request-level logging for WebSocket connection attempts (connect, auth, close with code)

## Phase 4: Build and Test

- [ ] 4.1 Run `npm run build` to verify no TypeScript/build errors
- [ ] 4.2 Run `npm test` to verify all tests pass including new CSP tests
- [ ] 4.3 Verify CSP header in curl output includes `wss://app.soleur.ai` in `connect-src`

## Phase 5: Deploy and Verify

- [ ] 5.1 Deploy to production via webhook
- [ ] 5.2 Verify via Playwright that StatusIndicator shows "Connected" (green dot)
- [ ] 5.3 Check browser console for absence of CSP violation errors
- [ ] 5.4 Send a test message and verify response streams back
- [ ] 5.5 Verify Supabase realtime connections still work (wss:// to supabase preserved)
