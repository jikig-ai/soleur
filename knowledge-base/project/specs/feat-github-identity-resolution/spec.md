# Spec: GitHub Identity Resolution for Email-Only Users

**Issue:** #1768
**Brainstorm:** [2026-04-07-github-identity-resolution-brainstorm.md](../../brainstorms/2026-04-07-github-identity-resolution-brainstorm.md)
**Branch:** `github-identity-resolution`

## Problem Statement

Email-only Soleur users cannot auto-detect their GitHub App installation during project setup. The `detect-installation` endpoint requires a GitHub username (resolved from Supabase identity), which email-only users don't have. When the GitHub App is already installed by another Soleur account on the same GitHub identity, the install redirect doesn't trigger a callback (no changes = no redirect back), leaving the user stuck.

## Goals

- G1: Email-only users can connect a project without manual input when the GitHub App is already installed
- G2: Solution works when multiple Soleur accounts share the same GitHub identity
- G3: GitHub username is persisted for future `detect-installation` calls without re-auth
- G4: No identity linking in Supabase -- avoids "already linked to another user" conflicts

## Non-Goals

- NG1: Popup-based OAuth (deferred unless redirect proves problematic on mobile)
- NG2: Storing GitHub user access tokens (installation tokens handle all repo operations)
- NG3: Account consolidation or merging (multi-account is supported)
- NG4: Cleaning up vestigial `link_github` state (separate concern)

## Functional Requirements

- FR1: New API route (`/api/auth/github-resolve`) initiates GitHub App OAuth with `client_id` and `state` parameter
- FR2: New callback route (`/api/auth/github-resolve/callback`) exchanges code for token, calls `GET /user`, stores `github_username`, redirects to `/connect-repo`
- FR3: Connect-repo page shows inline explanation and "Continue with GitHub" button when `detect-installation` returns `no_github_identity`
- FR4: `detect-installation` uses stored `github_username` as fallback when no Supabase GitHub identity exists
- FR5: OAuth `state` parameter verified on callback to prevent CSRF
- FR6: Callback handles missing `code` parameter gracefully (user denied or GitHub error)

## Technical Requirements

- TR1: New `github_username` column on `public.users` table (migration 016)
- TR2: `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` read from environment (already in Doppler `prd`)
- TR3: New callback route added to open redirect allowlist in `lib/auth/resolve-origin.ts`
- TR4: New callback route added to `TC_EXEMPT_PATHS` in middleware
- TR5: Separate callback route from Supabase OAuth callback (different client_id, state, token exchange)
- TR6: OAuth access token discarded after username extraction (not stored)

## UX Flow

```text
1. Email-only user clicks [Connect Project]
2. detect-installation returns { installed: false, reason: "no_github_identity" }
3. Page transitions to github_resolve state
4. Shows inline message: "To find your GitHub App, we need to verify your GitHub account. This is a one-time step."
5. User clicks [Continue with GitHub]
6. Redirect to GitHub OAuth (GET https://github.com/login/oauth/authorize?client_id=...&state=...)
7. User authorizes (or is auto-authorized if previously granted)
8. GitHub redirects to /api/auth/github-resolve/callback?code=...&state=...
9. Server exchanges code for token, calls GET /user, stores github_username
10. Redirect to /connect-repo
11. detect-installation now uses stored github_username -> finds installation
12. User proceeds to select_project state
```

## Test Scenarios

- TS1: Email-only user with no GitHub identity triggers the github_resolve flow
- TS2: OAuth callback stores github_username and redirects to connect-repo
- TS3: detect-installation uses github_username when no Supabase GitHub identity
- TS4: CSRF: callback rejects requests with invalid/missing state parameter
- TS5: Callback handles missing code parameter (user denied)
- TS6: Multiple Soleur accounts can resolve to the same GitHub username independently
- TS7: User with existing Supabase GitHub identity skips the resolve flow entirely
