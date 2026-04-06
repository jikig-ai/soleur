# Learning: GitHub App org repo creation requires endpoint routing and administration permission

## Problem

"Create Project" (Start Fresh flow) failed with a generic "Project Setup Failed" error for users who installed the GitHub App on an organization account. The root cause was threefold:

1. **Wrong API endpoint for orgs:** `createRepo()` always called `POST /user/repos`, which creates a repo under the authenticated user. For GitHub App installation tokens, there is no "user" identity -- the token is scoped to an installation. When the installation belongs to an organization, `/user/repos` fails because the token cannot create repos on behalf of a non-existent user.
2. **Error swallowing:** The create route's catch handler returned a generic "Failed to create repository" string instead of the actual GitHub API error message. No `Sentry.captureException()` call existed, so the failure was invisible in observability.
3. **Fragile error dispatch:** Reviewers identified that string-matching on `err.message` for control flow (e.g., checking for "not found" substrings) is brittle and breaks when error messages change.

## Solution

1. **Extracted `getInstallationAccount()` helper** from `verifyInstallationOwnership()` -- a reusable function that calls `GET /app/installations/{id}` and returns the installation's `account` metadata (login, type, id).
2. **Endpoint routing in `createRepo()`:** Call `getInstallationAccount()` first, then route to `POST /orgs/{org}/repos` for `account.type === "Organization"` or `POST /user/repos` for `account.type === "User"`.
3. **Typed error class:** Introduced `InstallationError` with a `code` property (e.g., `INSTALLATION_NOT_FOUND`) to replace fragile string-matching in error dispatch. Catch blocks use `instanceof InstallationError` and `err.code` instead of `err.message.includes(...)`.
4. **Error surfacing:** Added `Sentry.captureException()` to the create route handler. Return actual GitHub API error messages to the client instead of generic strings. Client displays error details for both create and setup POST failures.

## Key Insight

GitHub App installation tokens have fundamentally different identity semantics for user vs organization installations:

- **User installation token:** Acts on behalf of the user's account. `/user/repos` works because the token has a user identity context.
- **Organization installation token:** Acts on behalf of the org. `/user/repos` fails because there is no user identity -- the token only has permission to act within the org's scope. You must use `/orgs/{org}/repos` instead.

This is not documented prominently in GitHub's API docs. The error message from GitHub (`Resource not accessible by integration` or similar) does not hint at the endpoint mismatch. The fix requires proactively detecting the account type and routing to the correct endpoint.

Additionally, the GitHub App needs the `administration:write` permission to create repositories in an organization. This is a Phase 0 prerequisite that must be applied to the GitHub App configuration before the org repo creation code path will succeed end-to-end.

**Generalizable pattern:** When a GitHub App feature works for user installations but fails for org installations, check whether the code assumes a user identity context (user-scoped API endpoints, user-specific permissions). Org installations require org-scoped endpoints and may need additional App permissions.

## Session Errors

**One-shot script path:** `setup-ralph-loop.sh` was called from `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` on the first attempt, which does not exist. The correct path is `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Prevention:** The one-shot skill should use the canonical path `./plugins/soleur/scripts/` not skill-relative paths. Always verify script paths exist before executing.

## Related Learnings

- `knowledge-base/project/learnings/integration-issues/silent-setup-failure-no-error-capture-20260403.md` -- Covers the broader error-swallowing pattern in setup routes (RC3 of this fix was a continuation of that work)
- `knowledge-base/project/learnings/integration-issues/github-org-membership-api-redirect-handling-20260402.md` -- Covers the org membership verification that was a prerequisite for org support
- `knowledge-base/project/learnings/integration-issues/2026-04-03-github-app-install-url-404.md` -- Covers the GitHub App creation and credential provisioning

## Tags

category: integration-issues
module: web-platform/server/github-app
