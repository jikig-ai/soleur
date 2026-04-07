# GitHub Identity Resolution for Email-Only Users

**Date:** 2026-04-07
**Issue:** #1768
**Branch:** `github-identity-resolution`
**Status:** Brainstorm complete

## What We're Building

A GitHub App OAuth flow that resolves a user's GitHub username without linking identities in Supabase, enabling email-only users to auto-detect their GitHub App installation during project setup.

**The problem:** Email-only Soleur users (signed up via OTP, no GitHub OAuth) cannot connect a project when the GitHub App is already installed by another Soleur account. The `detect-installation` endpoint returns `no_github_identity` because there is no GitHub username to call `GET /users/{login}/installation`.

**The solution:** Add a lightweight GitHub App OAuth flow (user authorization) that:

1. Redirects to GitHub with the App's `client_id`
2. Exchanges the callback code for a user access token
3. Calls `GET /user` to get the GitHub username
4. Stores `github_username` on the users table
5. Discards the access token (all repo operations use installation tokens)
6. Runs the existing `findInstallationForLogin` logic

## Why This Approach

### Approach A: GitHub App OAuth redirect (Selected)

- Uses GitHub's own authentication to prove account ownership
- `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` already exist in Doppler `prd`
- Does NOT call `supabase.auth.linkIdentity()` -- avoids the "identity already linked to another user" conflict entirely
- Multiple Soleur accounts can independently resolve to the same GitHub username
- Existing server functions (`findInstallationForLogin`, `verifyInstallationOwnership`) work without changes
- LOW risk, SMALL complexity (hours)

### Rejected approaches

| Approach | Reason |
|----------|--------|
| B: Popup-based OAuth | Popup blockers on Safari/iOS break this silently. Marginal UX improvement doesn't justify complexity. Deferred -- only revisit if A proves problematic on mobile. |
| C: GitHub device flow | CLI-style UX is wrong for a web app. Users shouldn't copy codes and visit URLs. |
| D: Username input field | No proof the user owns the GitHub account they type. Fails "must not leak information about other users' installations" requirement. |
| E: Supabase auto-linking | Fails when emails differ (the actual case: <ops@jikigai.com> vs <jean@osmosis.team>). Supabase doesn't allow one GitHub identity linked to two users. Changes behavior for ALL providers globally. |

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | A: GitHub App OAuth redirect | Secure (GitHub authenticates), scalable, no identity linking conflicts |
| Account model | Multi-account supported | People may have legitimate reasons for multiple Soleur accounts per GitHub identity |
| Username persistence | Store `github_username` on users table | Enables `detect-installation` on subsequent visits without re-auth. Requires migration 016. |
| Token handling | Discard OAuth access token after username extraction | All repo operations use GitHub App installation tokens, not user tokens |
| UX trigger | On "Connect Project" click | When `detect-installation` returns `no_github_identity`, show inline explanation + "Continue with GitHub" button before OAuth redirect |
| Callback route | Separate from Supabase OAuth callback | Different `client_id`, different `state` parameter, different token exchange. Must NOT multiplex through `/callback`. |

## Implementation Landmines

From institutional learnings -- these must be addressed during implementation:

1. **Open redirect allowlist** -- New OAuth callback origin must be added to `resolveOrigin()` in `lib/auth/resolve-origin.ts` (uses `Set.has()` exact-match)
2. **TC_EXEMPT_PATHS** -- New callback route must be in `TC_EXEMPT_PATHS` or users get redirected to `/accept-terms` mid-flow
3. **Supabase silent errors** -- Every Supabase client call must destructure `{ error }`. Client never throws.
4. **CSRF protection** -- OAuth `state` parameter (random nonce, stored in cookie) required. Established pattern: `soleur_link_attempt` cookie.
5. **NEXT_PUBLIC_ vars** -- If any new `NEXT_PUBLIC_` env vars are needed, they require Dockerfile `ARG` directives and CI `build-args`
6. **No code callback** -- The callback URL may lack a `code` parameter if the user denies or GitHub fails. PR #1764 fixed this for Supabase; new route needs the same handling.
7. **signInWithOtp guard** -- If redirect chain passes through login page, `shouldCreateUser: false` must be preserved to prevent duplicate accounts.

## Affected Components

- `apps/web-platform/app/api/repo/detect-installation/route.ts` -- Use stored `github_username` when no Supabase identity
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` -- New state: `github_resolve` for OAuth prompt
- `apps/web-platform/components/connect-repo/link-github-state.tsx` -- May be repurposed or replaced
- `apps/web-platform/server/github-app.ts` -- No changes; existing functions work
- **New:** `apps/web-platform/app/api/auth/github-resolve/route.ts` (OAuth initiate)
- **New:** `apps/web-platform/app/api/auth/github-resolve/callback/route.ts` (OAuth callback)
- **New:** `supabase/migrations/016_github_username.sql` (add column)

## Open Questions

1. Is the GitHub App's OAuth callback URL configured in GitHub App settings? (Separate from the install redirect URL.)
2. Does the `dev` Doppler config need `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` too, or is local dev testing out of scope?
3. Should the `link_github` state and `LinkGitHubState` component be cleaned up (vestigial after PR #1767)?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Approach A is LOW risk, SMALL complexity. `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` already provisioned in Doppler `prd`. The existing `findInstallationForLogin` and `verifyInstallationOwnership` functions work once a username is available. Key concern: keep the new OAuth callback route separate from the Supabase OAuth callback.

### Product (CPO)

**Summary:** Affected population is 1 known user today. Post-MVP/Later milestone is correct. Multi-account model is the most important strategic decision (confirmed: supported). The OAuth redirect on "Connect Project" click is the right UX trigger -- minimal friction in a flow where the user already expects GitHub interaction.

### Marketing (CMO)

**Summary:** No marketing action required. This is internal plumbing, not a feature announcement. Only touchpoint: brief copy review of the OAuth prompt text at PR time to ensure brand guide compliance.
