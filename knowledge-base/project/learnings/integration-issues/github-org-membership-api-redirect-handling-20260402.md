---
module: GitHub App
date: 2026-04-02
problem_type: integration_issue
component: authentication
symptoms:
  - "Organization installations rejected with 403 'not yet supported'"
  - "account.login for org installations returns org name, not installing user's login"
root_cause: missing_permission
resolution_type: code_fix
severity: medium
tags: [github-api, org-membership, redirect-handling, token-cache-isolation]
---

# Troubleshooting: GitHub Org Membership API 302 Redirect and Test Isolation

## Problem

Organization installations of the GitHub App were rejected because `verifyInstallationOwnership()` compared `account.login` (the org name) against the expected user login. Implementing org membership verification required handling a non-obvious 302 redirect edge case in the GitHub API.

## Environment

- Module: GitHub App authentication
- Affected Component: `apps/web-platform/server/github-app.ts:verifyInstallationOwnership()`
- Date: 2026-04-02

## Symptoms

- Organization installations rejected with 403 "Organization installations are not yet supported"
- `account.login` for org installations returns the org name, not the installing user's login

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt, guided by the plan's research into GitHub API docs.

## Session Errors

**`npx vitest run` pulled wrong global version with missing native bindings**

- **Recovery:** Used project-local `node_modules/.bin/vitest` instead of global `npx vitest`
- **Prevention:** In worktrees, always use the local `node_modules/.bin/` binary for test runners, not `npx` which may resolve to a different version

**CWD confusion after `cd` in prior command**

- **Recovery:** Used absolute paths or verified CWD before running commands
- **Prevention:** Avoid `cd` in chained commands; use absolute paths when running test commands in worktrees

## Solution

Replace the org rejection block with org membership verification using `GET /orgs/{org}/members/{username}`:

**Code changes:**

```typescript
// Before (broken):
if (account.type === "Organization") {
  return { verified: false, error: "Organization installations are not yet supported", status: 403 };
}

// After (fixed):
if (account.type === "Organization") {
  const token = await generateInstallationToken(installationId);
  const memberResponse = await githubFetch(
    `${GITHUB_API}/orgs/${account.login}/members/${expectedLogin}`,
    { headers: { Authorization: `token ${token}` }, redirect: "manual" },
  );
  if (memberResponse.status === 204) return { verified: true };
  if (memberResponse.status === 404 || memberResponse.status === 302) {
    return { verified: false, error: "User is not a member of the organization", status: 403 };
  }
  return { verified: false, error: "Failed to verify organization membership", status: 502 };
}
```

## Why This Works

1. **Root cause:** The original code only handled `account.type === "User"` by comparing logins directly. For orgs, `account.login` is the org name, not a user — a different verification strategy is needed.
2. **302 redirect edge case:** GitHub's `/orgs/{org}/members/{username}` returns 302 (not 404) when the requester lacks org-member perspective. Without `redirect: "manual"`, Node's `fetch` follows the redirect to the public members endpoint, which returns 200 — creating a false positive that would allow non-members to pass verification.
3. **Token cache test isolation:** The `tokenCache` Map in `github-app.ts` is module-level and persists across vitest tests. Using the same `installationId` across org tests causes the second test to hit the cache and skip the token exchange POST mock, breaking the mock sequence count. Each org test must use a unique `installationId` (200, 201, 202, 203, 204).

## Prevention

- When using GitHub's org membership endpoints with `fetch`, always set `redirect: "manual"` to prevent automatic redirect following that can produce false positives
- When testing functions that interact with module-level caches, use unique cache keys per test to ensure predictable mock sequences
- In worktrees, use `node_modules/.bin/<tool>` instead of `npx <tool>` to avoid version mismatches from global npx cache

## Related Issues

- Original security fix: PR #1387 (commit `58bcad2f`)
- GitHub issue: #1392
- vitest-bun-test cross-runner compat learning: `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md`
