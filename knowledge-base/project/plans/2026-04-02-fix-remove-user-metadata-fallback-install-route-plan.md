---
title: "fix(security): remove user_metadata fallback for GitHub login in install route"
type: fix
date: 2026-04-02
---

# fix(security): remove user_metadata fallback for GitHub login in install route

## Problem

`apps/web-platform/app/api/repo/install/route.ts:50` falls back to `user.user_metadata?.user_name` when no GitHub identity is found in `user.identities`. As noted in the code comment (line 43), `user_metadata` is user-mutable via `auth.updateUser()`.

An attacker who signed up via a non-GitHub provider could set `user_metadata.user_name` to any GitHub username, then claim an org installation where that user is a member.

**Source:** Security sentinel review of PR #1396

### Pre-existing

This fallback existed before #1396, but org installations were previously blanket-rejected. Now that org membership verification is live, the fallback becomes exploitable.

## Proposed Fix

Remove the `user_metadata` fallback entirely. Require the `identities` source. If no GitHub identity exists, reject -- which the code already does on line 52 for the `undefined` case.

### Current code (lines 45-50)

```typescript
const githubLogin =
  user.identities?.find(
    (i: { provider: string; identity_data?: { user_name?: string } }) =>
      i.provider === "github",
  )?.identity_data?.user_name ??
  user.user_metadata?.user_name;
```

### Target code

```typescript
// SECURITY: Extract GitHub username from provider-controlled identity only.
// user_metadata is user-mutable via auth.updateUser() — never trust it for
// security decisions when an immutable source exists.
const githubLogin = user.identities?.find(
  (i: { provider: string; identity_data?: { user_name?: string } }) =>
    i.provider === "github",
)?.identity_data?.user_name;
```

The removal of the `?? user.user_metadata?.user_name` fallback means `githubLogin` will be `undefined` when no GitHub identity exists in `user.identities`, which triggers the existing rejection block at lines 52-61 returning a 403 with "No GitHub identity found on this account".

Note: the code comment on line 43 says "Extract GitHub username from provider-controlled identity **first**" -- update to "**only**" since there is no longer a fallback.

### Note on `setup/route.ts`

`apps/web-platform/app/api/repo/setup/route.ts:90` also reads `user.user_metadata?.full_name`, but this is used only for display name during workspace provisioning (git commit author). It is not used for security decisions and does not need to change.

## Acceptance Criteria

- [ ] Remove `user_metadata?.user_name` fallback on line 50 of `apps/web-platform/app/api/repo/install/route.ts`
- [ ] Ensure non-GitHub-identity users get a clear 403 error with message "No GitHub identity found on this account"
- [ ] Add test coverage for the rejection path when user has no GitHub identity in `identities` array
- [ ] Add structural enforcement test verifying `user_metadata` is not referenced for `user_name` in the install route
- [ ] Existing 12 tests continue to pass

## Test Scenarios

Tests follow the existing pattern in `install-route.test.ts` -- structural (source-reading) tests for route-level concerns, avoiding complex Supabase mocking.

- Given the source code of `install/route.ts`, when checking for `user_metadata` references in the `githubLogin` assignment, then zero matches are found (structural enforcement -- prevents regression of the fallback)
- Given the source code of `install/route.ts`, when `githubLogin` is `undefined` (no GitHub identity), then the existing rejection block returns 403 with "No GitHub identity found on this account" (verified structurally via the existing `!githubLogin` guard at line 52)

## Context

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/app/api/repo/install/route.ts` | Remove `?? user.user_metadata?.user_name` from line 50 |
| `apps/web-platform/test/install-route.test.ts` | Add test for no-GitHub-identity rejection path; add structural test for absence of `user_metadata.user_name` |

### Existing test coverage

`apps/web-platform/test/install-route.test.ts` has 12 passing tests covering `verifyInstallationOwnership` (User/Org paths, error cases) and a structural test verifying ownership check precedes the `.update()` call. No existing tests cover the GitHub identity extraction logic or the rejection path at line 52.

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 1 (security audit)
**Research agents used:** codebase grep audit for `user_metadata` usage patterns

### Key Findings

1. **No other security-relevant `user_metadata` usage exists.** Grep of `apps/web-platform/` confirms only two `user_metadata` references: (a) `install/route.ts:50` -- the vulnerable fallback being removed, and (b) `setup/route.ts:90` -- display-name-only usage (`full_name` for git commit author). No additional routes need remediation.
2. **Supabase trust model context.** `user.identities[].identity_data` is populated by the OAuth provider during authentication and is immutable by the user. `user.user_metadata` is mutable via `supabase.auth.updateUser({ data: {...} })` -- any authenticated user can set arbitrary key-value pairs. The plan correctly identifies this trust boundary.
3. **No deepening needed beyond audit.** This is a minimal security fix (1 line removal + 1 structural test). The plan already contains exact before/after code, file manifest, and test scenarios. Additional research would not change the implementation.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- targeted security bug fix removing a single unsafe fallback.

## References

- Issue: #1400
- Related PR: #1396 (org installation support that made this fallback exploitable)
- Related PR: #1381 / #1387 (installation ownership verification)
