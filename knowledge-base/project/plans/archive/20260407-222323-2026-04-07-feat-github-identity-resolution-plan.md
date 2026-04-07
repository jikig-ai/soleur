---
title: "feat: GitHub App OAuth for email-only user identity resolution"
type: feat
date: 2026-04-07
---

# GitHub App OAuth for Email-Only User Identity Resolution

## Overview

Add a lightweight GitHub App OAuth flow that resolves a user's GitHub username
without Supabase identity linking, enabling email-only users to auto-detect
their GitHub App installation during project setup. Clean up the vestigial
`link_github` state in the same change.

## Problem Statement / Motivation

Email-only Soleur users (signed up via OTP) cannot auto-detect their GitHub App
installation when the App is already installed by another Soleur account. The
`detect-installation` endpoint requires a GitHub username resolved from Supabase
identity data, which email-only users lack. The GitHub App install redirect
doesn't callback when the App is already installed (no changes = no redirect
back), leaving the user stuck on the `choose` screen.

**Affected population:** 1 known user today (<ops@jikigai.com>). Post-MVP/Later
milestone is correct. The standard signup path (GitHub OAuth) avoids this
entirely.

**Why build now:** The brainstorm and spec are complete. Approach A (GitHub App
OAuth redirect) is validated by CTO, CPO, and CMO assessments. If deferred,
the spec and context will go stale. Estimated effort is small (hours).

## Proposed Solution

### Architecture

```text
Client (connect-repo page)          Server
================================    ================================
1. Click [Connect Project]
2. detect-installation → no_github_identity
3. → github_resolve state
4. Click [Continue with GitHub]
   ↓
5. Navigate to /api/auth/github-resolve
                                    6. Generate state nonce, set cookie
                                    7. 302 → github.com/login/oauth/authorize
   ↓
8. User authorizes on GitHub
   ↓
9. GitHub 302 → /api/auth/github-resolve/callback?code=...&state=...
                                    10. Verify state cookie
                                    11. Exchange code for token (POST github.com/login/oauth/access_token)
                                    12. GET api.github.com/user → extract login
                                    13. Store github_username on users table
                                    14. Delete state cookie
                                    15. 302 → /connect-repo
   ↓
16. Mount: detect-installation
    (now uses github_username as fallback)
17. → select_project (if App installed)
    OR → choose (if App not installed; user clicks
    "Connect Project" again → github_redirect)
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | GitHub App OAuth redirect | Secure (GitHub authenticates), no identity linking conflicts |
| Account model | Multi-account supported | Multiple Soleur accounts can share one GitHub identity |
| Username persistence | `github_username` column on users table | Enables detect-installation on subsequent visits without re-auth |
| Token handling | Discard after username extraction | Installation tokens handle all repo operations |
| UX trigger | On "Connect Project" click | Branches on `reason: "no_github_identity"` from detect-installation |
| State cookie | `SameSite=Lax; Secure; HttpOnly; max-age=300; path=/` | `Lax` required -- `Strict` blocks cross-site redirect from GitHub |
| OAuth scope | Empty (no `scope` parameter) | GitHub App user auth includes `GET /user` by default |
| link_github cleanup | Remove in same PR | CPO: two parallel identity resolution states is UX debt |
| Error redirects | Single `?resolve_error=1` on client; details logged server-side | All errors have same user action (retry). No client-side error code branching. |

## Technical Considerations

### Implementation Phases

#### Phase 0: Prerequisites

- [ ] Verify GitHub App OAuth callback URL is configured in GitHub App settings
  (separate from install redirect URL). Must be:
  `https://app.soleur.ai/api/auth/github-resolve/callback`
  Check via GitHub App settings page or `gh api /apps/soleur-ai`.
- [ ] Verify `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` exist in Doppler
  `prd` config: `doppler secrets get GITHUB_CLIENT_ID -p soleur -c prd --plain`

#### Phase 1: Database Migration

**File:** `apps/web-platform/supabase/migrations/016_github_username.sql`

```sql
-- Add github_username column for email-only user identity resolution.
-- No uniqueness constraint: multi-account model allows multiple Soleur
-- accounts to resolve to the same GitHub username.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS github_username TEXT;
```

No index needed -- the column is queried via user ID (primary key), never
directly.

#### Phase 2: Server-Side Routes

**New: `apps/web-platform/app/api/auth/github-resolve/route.ts`** (OAuth initiate)

- GET handler
- Reads `GITHUB_CLIENT_ID` from env
- Generates random `state` nonce (crypto.randomUUID)
- Sets `soleur_github_resolve` cookie with state value
  (`SameSite=Lax; Secure; HttpOnly; max-age=300; path=/`)
- Returns 302 redirect to:
  `https://github.com/login/oauth/authorize?client_id=${CLIENT_ID}&state=${state}&redirect_uri=${callbackUrl}`
- No `scope` parameter (empty scope is sufficient for `GET /user`)

**New: `apps/web-platform/app/api/auth/github-resolve/callback/route.ts`** (OAuth callback)

- GET handler (GitHub redirects here)
- If no `code` param: log reason, redirect to `/connect-repo?resolve_error=1`
- Read `soleur_github_resolve` cookie, compare to `state` query param
- If mismatch: log reason, redirect to `/connect-repo?resolve_error=1`
- Exchange code for token: POST `https://github.com/login/oauth/access_token`
  with `client_id`, `client_secret`, `code` (server-side, secrets never exposed)
- If exchange fails: log reason, redirect to `/connect-repo?resolve_error=1`
- Call `GET https://api.github.com/user` with Bearer token
- Validate `login` field is non-empty string
- If invalid: log reason, redirect to `/connect-repo?resolve_error=1`
- Store `github_username` on users table via service client
- Delete state cookie
- Redirect to `/connect-repo`
- Log: initiation, success (with username), and all failure modes

**Auth model:** User must have valid Supabase session (cookie survives the
GitHub redirect). If session expired, middleware redirects to `/login` -- user
retries after re-auth. This is an acceptable edge case for a <30s OAuth flow.

#### Phase 3: Middleware & Route Config

**Modify: `apps/web-platform/lib/routes.ts`**

```typescript
export const TC_EXEMPT_PATHS = [
  "/accept-terms",
  "/api/accept-terms",
  "/api/auth/github-resolve/callback",  // OAuth callback mid-flow
];
```

The callback route is NOT added to `PUBLIC_PATHS` -- it requires authentication
(needs to know which user to update). TC exemption prevents redirect to
`/accept-terms` mid-OAuth-flow.

The initiate route (`/api/auth/github-resolve`) does NOT need TC exemption --
it's only reachable from `/connect-repo`, which already requires T&C acceptance.

No changes needed to `resolveOrigin()` or `validateOrigin()` -- the new routes
use cookie-based CSRF (state parameter), not origin-based CSRF. The routes
redirect users to/from GitHub, they don't receive AJAX requests.

#### Phase 4: detect-installation Fallback

**Modify: `apps/web-platform/app/api/repo/detect-installation/route.ts`**

After the existing identity resolution (lines 68-89), before returning
`no_github_identity` (line 91), add a fallback that queries the
`github_username` column:

```typescript
// Existing: resolve from Supabase identity
let githubLogin = /* ... existing code ... */;

// NEW: fallback to stored github_username for email-only users
if (!githubLogin) {
  const { data: usernameRow } = await serviceClient
    .from("users")
    .select("github_username")
    .eq("id", user.id)
    .single();
  githubLogin = usernameRow?.github_username ?? undefined;
}

if (!githubLogin) {
  return NextResponse.json({ installed: false, reason: "no_github_identity" });
}
```

The existing `findInstallationForLogin` and `verifyInstallationOwnership` calls
work unchanged with the resolved username.

#### Phase 5a: Client-Side State Machine (page.tsx)

**Modify: `apps/web-platform/app/(auth)/connect-repo/page.tsx`**

1. Add `"github_resolve"` to State type union (line 23-33)
2. Remove `"link_github"` from State type union
3. Remove `LinkGitHubState` import (line 18) and render case (line 571-576)
4. Remove `?link_error` detection in useState initializer (line 64-66)

5. In `handleConnectExisting()` (line 365-407): after detect-installation
   returns non-installed, check `reason`:

   ```typescript
   if (detectData && !detectData.installed) {
     if (detectData.reason === "no_github_identity") {
       setState("github_resolve");
       return;
     }
   }
   // Existing fallthrough to github_redirect
   setState("github_redirect");
   ```

6. In `handleCreateSubmit()` (line 432-480): same branching on
   `no_github_identity`. Route to `github_resolve` (no `pendingCreate`
   threading -- user re-enters project name after resolve; one-time flow for
   1 user, trivial re-entry cost vs. cross-redirect state recovery complexity).

7. In useState initializer: detect `?resolve_error=1` param. If present,
   start on `choose` with a generic error banner: "GitHub connection failed.
   Please try again."

8. Mount auto-detect behavior unchanged. After resolve, user returns to
   `choose` and clicks "Connect Project" again if App install is also needed.
   No auto-chaining (never auto-redirect twice without user interaction).

#### Phase 5b: github-resolve-state Component

**New: `apps/web-platform/components/connect-repo/github-resolve-state.tsx`**

New component matching existing component pattern (badge, serif title, body,
buttons):

- Props: `onContinue: () => void`, `onBack: () => void`
- Badge: "QUICK SETUP"
- Title: "Connect to GitHub"
- Body: "Your Soleur account was created with email. A quick GitHub sign-in
  lets us find the app installation on your account and connect your project."
- "What happens next" card (2 steps):
  1. Sign in to GitHub (quick authorization)
  2. Return here to connect your project
- Primary button: [Continue with GitHub] → navigates to `/api/auth/github-resolve`
- Secondary: [Go Back] → returns to `choose`

**Delete: `apps/web-platform/components/connect-repo/link-github-state.tsx`**

Remove the vestigial `LinkGitHubState` component. The `link_github` state and
`supabase.auth.linkIdentity()` approach is fully replaced by the OAuth resolve
flow.

#### Phase 6: Tests

**Modify: `apps/web-platform/test/connect-repo-page.test.ts`**

- Update existing `no_github_identity` test cases (lines 681-727) to expect
  `github_resolve` state instead of staying on `choose`
- Add test: detect-installation returns `no_github_identity` → transitions to
  `github_resolve`
- Add test: returning from OAuth with `?resolve_error` param → shows error
- Remove tests for `link_github` state / `?link_error` handling

**New: `apps/web-platform/test/github-resolve.test.ts`**

- OAuth initiate sets state cookie and redirects to GitHub
- Callback with valid code+state stores `github_username` and redirects
- Callback with missing code redirects with `resolve_error=1` and logs reason
- Callback with invalid state redirects with `resolve_error=1` and logs reason
- Callback with failed token exchange redirects with `resolve_error=1`
- Callback with empty `login` from GitHub redirects with `resolve_error=1`

**Modify: `apps/web-platform/test/detect-installation.test.ts`** (if exists)

- Add test: user with no GitHub identity but stored `github_username` →
  uses `github_username` as fallback
- Add test: user with both GitHub identity and `github_username` →
  prefers Supabase identity

**Modify: `apps/web-platform/test/middleware.test.ts`**

- Add OAuth callback paths to TC_EXEMPT_PATHS verification

### Security Considerations

| Concern | Mitigation |
|---------|-----------|
| CSRF on OAuth callback | `state` parameter (random nonce in HttpOnly cookie, verified on callback) |
| Token leakage | Access token used server-side only, discarded after `GET /user` |
| Client secret exposure | `GITHUB_CLIENT_SECRET` only used in server-side token exchange |
| Open redirect | Callback always redirects to `/connect-repo` (hardcoded), never to user-controlled URL |
| State cookie cross-site | `SameSite=Lax` ensures cookie is sent on GitHub redirect back |
| Installation squatting | GitHub authenticates the user; we trust the `login` from `GET /user` |
| Username spoofing | Username comes from GitHub API with Bearer token, not user input |
| Stale username | GitHub username renames are rare; if `findInstallationForLogin` fails with stale username, user can re-resolve (manual retry via `choose` screen) |

### Implementation Landmines (from learnings)

1. **Open redirect allowlist** (`lib/auth/resolve-origin.ts`): NOT affected --
   new routes use cookie-based CSRF, not origin validation
2. **TC_EXEMPT_PATHS** (`lib/routes.ts:15`): Must add callback route only
3. **Supabase silent errors**: Every `{ data, error }` must be destructured
4. **State cookie SameSite**: MUST be `Lax`, not `Strict` -- GitHub redirect is
   cross-site. `Strict` silently drops the cookie, causing all CSRF verifications
   to fail permanently.
5. **NEXT_PUBLIC_ vars**: Not needed -- `GITHUB_CLIENT_ID` is server-side only
   (used in the route handler, not in client components)
6. **No-code callback**: Handle `?error=access_denied` (no `code` param) per
   PR #1764 pattern
7. **signInWithOtp guard**: Not affected -- OAuth redirect doesn't pass through
   login page
8. **Callback/trigger parity**: Not affected -- no user row creation in this flow

## Acceptance Criteria

- [ ] Email-only user clicks "Connect Project" and sees `github_resolve` state
      (not `github_redirect`) when detect-installation returns `no_github_identity`
- [ ] OAuth flow completes: user authorizes on GitHub, callback stores
      `github_username`, redirects to `/connect-repo`
- [ ] On return, detect-installation uses stored `github_username` as fallback
      and finds the installation
- [ ] "Create Project" flow routes to `github_resolve` when needed (user
      re-enters project name after resolve -- no cross-redirect state threading)
- [ ] CSRF: callback rejects requests with invalid/missing state parameter
- [ ] Callback handles missing code parameter (user denied OAuth)
- [ ] Multiple Soleur accounts can resolve to the same GitHub username
- [ ] User with existing Supabase GitHub identity skips github_resolve entirely
- [ ] `link_github` state and `LinkGitHubState` component are removed
- [ ] Migration 016 adds `github_username` column with no uniqueness constraint
- [ ] OAuth callback path added to `TC_EXEMPT_PATHS`

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Approach A is LOW risk, SMALL complexity. `GITHUB_CLIENT_ID`/
`GITHUB_CLIENT_SECRET` already provisioned in Doppler `prd`. Existing server
functions work once a username is available. Key requirement: separate callback
route from Supabase OAuth callback.

### Product/UX Gate

**Tier:** advisory (promoted to full review at user request)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter
**Skipped specialists:** none
**Pencil available:** pending

#### Findings

**CPO:** Timing concern noted (6 unstarted P1 features). Recommended either
deferring entirely or cleaning up `link_github` in the same PR. Plan adopts the
cleanup recommendation -- `link_github` removal is now a requirement, not NG4.

**Spec-flow-analyzer:** 21 gaps identified. Critical gaps addressed in plan:

- Client routing to `github_resolve` (branch on `reason: "no_github_identity"`)
- `detect-installation` github_username fallback
- Two-redirect scenario (user clicks through `choose` between redirects)
- State cookie `SameSite=Lax` requirement
- Single error redirect with server-side logging

**CMO:** No marketing action required. Brief copy review of OAuth prompt text
at PR time. Copywriter agent invoked for the github_resolve screen copy.

## Test Scenarios

### Acceptance Tests

- Given an email-only user on the choose screen, when they click "Connect
  Project" and detect-installation returns `no_github_identity`, then the page
  transitions to `github_resolve` state
- Given a user on the `github_resolve` screen, when they click "Continue with
  GitHub", then they are redirected to GitHub OAuth authorize URL with
  client_id and state params
- Given a valid OAuth callback with code and state, when the server processes
  it, then `github_username` is stored and user is redirected to `/connect-repo`
- Given a returning user with stored `github_username`, when detect-installation
  runs, then it uses `github_username` as fallback and finds the installation
- Given an email-only user who resolves their username but the App is NOT
  installed, when they return to `/connect-repo`, then they land on `choose`
  and can proceed to install the App via "Connect Project"

### Error Handling

- Given a callback with no `code` parameter (user denied), when the server
  processes it, then log the reason and redirect to `/connect-repo?resolve_error=1`
- Given a callback with invalid `state` parameter, when the server processes
  it, then log the reason and redirect to `/connect-repo?resolve_error=1`
- Given a callback where token exchange fails, when the server processes it,
  then log the reason and redirect to `/connect-repo?resolve_error=1`
- Given a callback where `GET /user` returns empty login, when the server
  processes it, then log the reason and redirect to `/connect-repo?resolve_error=1`

### Regression

- Given a user with existing Supabase GitHub identity, when they visit
  `/connect-repo`, then the existing flow works unchanged (github_resolve never
  triggered)
- Given a user with stored `github_installation_id`, when detect-installation
  runs, then repos are returned immediately (no fallback needed)

### Edge Cases

- Given two Soleur accounts sharing the same GitHub identity, when both resolve
  via OAuth, then both store the same `github_username` independently (no
  uniqueness constraint violation)
- Given an email-only user on "Create Project" who gets routed through
  `github_resolve`, when they return after OAuth, then they land on `choose`
  and can re-enter their project name (no cross-redirect state threading)

## Dependencies & Risks

| Dependency | Type | Risk | Mitigation |
|-----------|------|------|-----------|
| GitHub App OAuth callback URL configured | Config | High -- flow fails entirely without it | Phase 0 prerequisite check |
| `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` in Doppler | Config | Low -- already in `prd` | Verify with `doppler secrets get` |
| Supabase migration applied | Deploy | Medium -- column must exist before code ships | Run migration before deploying |
| Session survives OAuth redirect | Runtime | Low -- redirect is <30s | Accept retry-on-expiry as edge case |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-07-github-identity-resolution-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-github-identity-resolution/spec.md`
- detect-installation: `apps/web-platform/app/api/repo/detect-installation/route.ts:91`
- connect-repo page: `apps/web-platform/app/(auth)/connect-repo/page.tsx:365`
- TC_EXEMPT_PATHS: `apps/web-platform/lib/routes.ts:15`
- validate-origin: `apps/web-platform/lib/auth/validate-origin.ts:3`
- State cookie pattern: `apps/web-platform/components/connect-repo/link-github-state.tsx:27`
- Recent PRs: #1760, #1761, #1762, #1764, #1767
- Learnings: 7 relevant files in `knowledge-base/project/learnings/`

### External References

- GitHub App user authorization: <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app>
- GitHub OAuth endpoints: <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps>
