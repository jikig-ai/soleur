---
title: "feat: support GitHub App organization installations in ownership verification"
type: feat
date: 2026-04-02
---

# feat: support GitHub App organization installations in ownership verification

## Overview

The `verifyInstallationOwnership()` function in `apps/web-platform/server/github-app.ts` currently rejects all organization-type GitHub App installations with a 403 "not yet supported" error. Users who install the Soleur GitHub App on an organization account cannot complete the connect-repo flow. This plan implements org membership verification so that org installations are accepted when the authenticated user is a member of the organization.

**Source:** Issue #1392, deferred from PR #1387 (original security fix)

## Problem Statement

**Location:** `apps/web-platform/server/github-app.ts:156-168`

When a GitHub App is installed on an organization, the installation's `account.login` is the org name, not the installing user's login. The current code handles only `account.type === "User"` by comparing `account.login` against `expectedLogin`. For organizations, it logs a warning and returns `{ verified: false, error: "Organization installations are not yet supported", status: 403 }`.

This blocks any user who installs the App on their org from using the repo connection flow.

## Proposed Solution

Replace the org rejection block (lines 158-168) with an org membership check using `GET /orgs/{org}/members/{username}`.

### API Endpoint Choice

Two GitHub API endpoints can verify org membership:

| Endpoint | Response | Auth Required |
|----------|----------|---------------|
| `GET /orgs/{org}/members/{username}` | 204 (member) / 404 (not member) | Requester must be org member; "Members" org permission (read) for Apps |
| `GET /orgs/{org}/memberships/{username}` | 200 with `state`, `role` fields | Same as above |

**Decision:** Use `GET /orgs/{org}/members/{username}` (the simpler endpoint). It returns 204/404 with no body to parse. The `state` and `role` fields from the memberships endpoint are not needed -- membership presence is sufficient for ownership verification.

**Auth token:** Use the installation token (not the App JWT). The installation token is scoped to the org and has the permissions the org admin granted. If the App lacks "Members" read permission, the API returns 403, which the code handles as a verification failure with a clear error message.

### Implementation Steps

**File:** `apps/web-platform/server/github-app.ts`

1. Replace the org rejection block (lines 156-168) with:
   - Generate an installation token via `generateInstallationToken(installationId)`
   - Call `GET /orgs/{account.login}/members/{expectedLogin}` with the installation token
   - 204 response: return `{ verified: true }`
   - 404 response: return `{ verified: false, error: "User is not a member of the organization", status: 403 }`
   - Other errors (403 for missing permissions, 5xx): return `{ verified: false, error: "Failed to verify organization membership", status: 502 }`

2. The case-insensitive comparison is handled by the GitHub API itself (org names and usernames are case-insensitive in GitHub's API routing), so no manual `toLowerCase()` is needed for the API call. However, GitHub's API path parameters are case-insensitive, so passing the values as-is from the installation response is correct.

**File:** `apps/web-platform/test/install-route.test.ts`

3. Update the existing "rejects organization installations with 403" test to instead verify the new org membership flow.

4. Add new test cases (note: each org test requires three mock fetch calls -- (1) installation lookup GET, (2) token exchange POST from `generateInstallationToken`, (3) membership check GET):
   - Org installation where user IS a member (mocks: installation returns org account, token exchange succeeds, membership returns 204) -- expect `verified: true`
   - Org installation where user is NOT a member (mocks: installation returns org account, token exchange succeeds, membership returns 404) -- expect `verified: false, status: 403`
   - Org installation where membership check fails with 403 (missing Members permission) (mocks: installation returns org account, token exchange succeeds, membership returns 403) -- expect `verified: false, status: 502` with descriptive error
   - Org installation where membership check returns 500 (mocks: installation returns org account, token exchange succeeds, membership returns 500) -- expect `verified: false, status: 502`

## Acceptance Criteria

- [ ] `verifyInstallationOwnership()` handles `account.type === "Organization"` by checking org membership via `GET /orgs/{org}/members/{username}`
- [ ] Tests cover org member verification: happy path (member, verified=true), non-member rejection (verified=false, 403), and API error handling (502)
- [ ] Error message updated from "Organization installations are not yet supported" to specific success/failure messages
- [ ] Existing User-type tests continue to pass unchanged

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- server-side security logic change with no UI, legal, or operational impact.

## Test Scenarios

- Given an org installation and a user who IS a member of the org, when `verifyInstallationOwnership()` is called, then it returns `{ verified: true }`
- Given an org installation and a user who is NOT a member of the org, when `verifyInstallationOwnership()` is called, then it returns `{ verified: false, error: "User is not a member of the organization", status: 403 }`
- Given an org installation where the GitHub App lacks "Members" read permission, when `verifyInstallationOwnership()` is called, then it returns `{ verified: false, error: "Failed to verify organization membership", status: 502 }`
- Given a User-type installation (existing behavior), when `verifyInstallationOwnership()` is called, then existing login comparison logic is unchanged

## Edge Cases

- **Token generation failure:** `generateInstallationToken()` already throws on failure. The caller (`POST /api/repo/install`) does not catch this, so it will propagate as a 500. This is acceptable -- the existing token generation path has the same behavior for `listInstallationRepos` and `createRepo`.
- **Pending org invitations:** `GET /orgs/{org}/members/{username}` returns 404 for pending invitations (only confirmed members return 204). This is the desired behavior -- pending members should not be able to claim the installation.
- **GitHub App "Members" permission not granted:** The org admin may not have granted the "Members" organization permission. The API returns 403, which the code handles as a 502 with "Failed to verify organization membership". The error is clear enough for the user to understand the App needs additional permissions.

## Context

- The original security fix (PR #1387, commit `58bcad2f`) deliberately deferred org support with a TODO comment
- The `verifyInstallationOwnership` function is called from a single location: `apps/web-platform/app/api/repo/install/route.ts:63`
- The `generateInstallationToken` function is already exported and handles caching, so it can be reused within `verifyInstallationOwnership` without adding a new dependency
- The `githubFetch` helper already sets the correct `Accept` and `X-GitHub-Api-Version` headers

## References

- GitHub issue: #1392
- Original security fix: #1387 (PR), `58bcad2f` (commit)
- GitHub API docs: [Check organization membership](https://docs.github.com/en/rest/orgs/members#check-organization-membership-for-a-user)
- Original plan: `knowledge-base/project/plans/2026-04-02-security-github-app-install-id-verification-plan.md`
