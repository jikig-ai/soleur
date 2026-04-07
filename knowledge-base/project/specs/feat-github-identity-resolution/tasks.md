# Tasks: GitHub Identity Resolution for Email-Only Users

**Plan:** [2026-04-07-feat-github-identity-resolution-plan.md](../../plans/2026-04-07-feat-github-identity-resolution-plan.md)
**Issue:** #1768
**Branch:** `github-identity-resolution`

## Phase 0: Prerequisites

- [ ] 0.1 Verify GitHub App OAuth callback URL is configured in App settings
  - URL: `https://app.soleur.ai/api/auth/github-resolve/callback`
  - Check via GitHub App settings page
- [ ] 0.2 Verify `GITHUB_CLIENT_ID` exists in Doppler `prd`:
  `doppler secrets get GITHUB_CLIENT_ID -p soleur -c prd --plain`
- [ ] 0.3 Verify `GITHUB_CLIENT_SECRET` exists in Doppler `prd`:
  `doppler secrets get GITHUB_CLIENT_SECRET -p soleur -c prd --plain`

## Phase 1: Database Migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/016_github_username.sql`
  - Add `github_username TEXT` column to `public.users`
  - No uniqueness constraint (multi-account model)
  - No index needed (queried via user ID primary key)

## Phase 2: Server-Side Routes

- [ ] 2.1 Create OAuth initiate route: `apps/web-platform/app/api/auth/github-resolve/route.ts`
  - GET handler
  - Generate state nonce, set `soleur_github_resolve` cookie
  - Cookie: `SameSite=Lax; Secure; HttpOnly; max-age=300; path=/`
  - Redirect to GitHub OAuth authorize URL (no scope parameter)
- [ ] 2.2 Create OAuth callback route: `apps/web-platform/app/api/auth/github-resolve/callback/route.ts`
  - GET handler
  - Verify state cookie matches state query param
  - Exchange code for token (POST github.com/login/oauth/access_token)
  - Call GET api.github.com/user, extract login
  - Store `github_username` on users table
  - Delete state cookie
  - Redirect to `/connect-repo`
  - All errors: log specific reason, redirect to `/connect-repo?resolve_error=1`
- [ ] 2.3 Add structured logging for all OAuth flow events

## Phase 3: Middleware & Route Config

- [ ] 3.1 Add `/api/auth/github-resolve/callback` to `TC_EXEMPT_PATHS` in `apps/web-platform/lib/routes.ts`
  - Initiate route does NOT need exemption (only reachable from T&C-gated pages)

## Phase 4: detect-installation Fallback

- [ ] 4.1 Modify `apps/web-platform/app/api/repo/detect-installation/route.ts`
  - After Supabase identity resolution fails (line 91), query `github_username` column
  - Use stored `github_username` as `githubLogin` fallback
  - Existing `findInstallationForLogin` and `verifyInstallationOwnership` work unchanged

## Phase 5a: Client-Side State Machine (page.tsx)

- [ ] 5.1 Add `"github_resolve"` to State type union in `page.tsx`
- [ ] 5.2 Modify `handleConnectExisting()` to branch on `reason: "no_github_identity"`
  - Route to `github_resolve` instead of `github_redirect`
- [ ] 5.3 Modify `handleCreateSubmit()` to branch on `reason: "no_github_identity"`
  - Route to `github_resolve` (no pendingCreate threading -- user re-enters name after resolve)
- [ ] 5.4 Handle `?resolve_error=1` param in useState initializer
  - Start on `choose` with generic error banner
- [ ] 5.5 Remove `link_github` state, `LinkGitHubState` import, and render case
- [ ] 5.6 Remove `?link_error` detection in useState initializer

## Phase 5b: github-resolve-state Component

- [ ] 5.7 Create `apps/web-platform/components/connect-repo/github-resolve-state.tsx`
  - Props: `onContinue`, `onBack`
  - Badge: "QUICK SETUP"
  - Title: "Connect to GitHub"
  - Body: "Your Soleur account was created with email. A quick GitHub sign-in lets us find the app installation on your account and connect your project."
  - "What happens next" 2-step card
  - Buttons: [Continue with GitHub], [Go Back]

## Phase 6: Tests

- [ ] 6.1 Update `connect-repo-page.test.ts` for new `github_resolve` behavior
- [ ] 6.2 Create `github-resolve.test.ts` for OAuth route handlers
  - Initiate sets cookie and redirects
  - Callback with valid code/state stores username
  - Error cases: no code, invalid state, exchange failure, invalid user
- [ ] 6.3 Update `middleware.test.ts` for new TC_EXEMPT_PATHS entries
- [ ] 6.4 Add detect-installation tests for `github_username` fallback

## Phase 7: Cleanup & Verification

- [ ] 7.1 Delete `apps/web-platform/components/connect-repo/link-github-state.tsx`
- [ ] 7.2 Remove any remaining references to `link_github` state
- [ ] 7.3 Run full test suite: `cd apps/web-platform && npx vitest run`
- [ ] 7.4 Verify E2E: email-only user → github_resolve → OAuth → connect-repo → select_project
