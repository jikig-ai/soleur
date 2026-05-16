# Learning: GitHub App installation tokens cannot call `POST /user/repos`

**Date:** 2026-05-07
**PR:** #3399
**Class:** integration-issue (third-party API limitation)
**Supersedes (partially):** [`2026-04-06-github-app-org-repo-creation-endpoint-routing.md`](../2026-04-06-github-app-org-repo-creation-endpoint-routing.md)

## Problem

The Knowledge Base "Set up project" → "Create Project" flow returned
`403 Resource not accessible by integration` for every personal-account
(user-installation) user attempting to create a private repo. The
`apps/web-platform/server/github-app.ts:611-635` `createRepo()` function
routed user installations to `POST /user/repos` with the GitHub App
installation token. That call has never succeeded in production — it was
only test-mocked at 201, and the org-installation traffic that PR #1671
shipped masked the gap.

## Root cause

`POST /user/repos` is a **UAT-only endpoint** in GitHub's REST API. It
does not accept GitHub App installation tokens (IATs / `ghs_...` prefix),
regardless of which permissions the App has.

This is a fundamental authentication-context limitation, not a permissions
issue:

- App-level permissions (`administration:write`, `contents:write`) are
  correct.
- Both org and user installations have *accepted* `administration:write`.
- `/user/repos` returns 403 *because the endpoint requires
  user-to-server (UAT) authentication*, not server-to-server.

Live-reproduced 2026-05-07 against installation `Elvalio` (App ID 3261325):

```text
POST /user/repos with installation token (private:true, auto_init:true)
→ { "message": "Resource not accessible by integration", "status": "403" }
```

## Solution

Route user installations through `POST /repos/{template_owner}/{template_repo}/generate`
(template-generate). This endpoint **does** accept installation tokens
provided:

1. The template repo exists and has `is_template: true`.
2. The template repo is **public**. Cross-account `/generate` calls from
   a user-installation token return 404 against private templates
   (live-verified — same App, different installation context).
3. The calling installation has `administration:write` on the target
   account (which it does for user installations, since the user
   authorized the App on their account).

Implementation (PR #3399):

- New helper `createRepoFromTemplate(installationId, ownerLogin, name, isPrivate)`
  in `apps/web-platform/server/github-app.ts`.
- `createRepo()` branches: `account.type === "Organization"` →
  `createRepoForOrg`; `account.type === "User"` → `createRepoFromTemplate`.
- Template lives at `jikig-ai/kb-template`, public, `is_template:true`,
  seeded with `README.md` only.

## Test-mock-vs-real-API drift

The original `apps/web-platform/test/github-app-create-repo.test.ts:109-147`
test mocked `globalThis.fetch` returning `{ ok: true, status: 201, ... }`
for `POST /user/repos`. The mock made the test green for a year while the
underlying code path **could not work in production**. The implementation
was test-shaped, not API-shaped.

**Generalizable pattern:** any unit test that mocks a third-party API
response for a code path which has never been exercised end-to-end is a
candidate for the same drift class. Mitigations:

- Capture live responses as JSON fixtures (`test/fixtures/github/*.json`)
  and load from disk.
- Run a periodic smoke test (Playwright + real installation in dev) that
  exercises the route against the real API.
- For each new third-party API integration, document the auth-context
  requirements (UAT vs IAT vs PAT) in the helper's JSDoc *before* the
  first mock is written.

## Generalizable mental model

GitHub App **installation tokens have no user identity context, regardless
of whether the installation is on a user or organization account**. The
account-type split (`account.type === "User" | "Organization"`) controls
**routing** (which endpoint to call), not **identity** (the token never
acts as the user; it always acts as the installation).

| Auth class      | `/user/repos` | `/orgs/{org}/repos` | `/repos/{owner}/{template}/generate` |
|-----------------|---------------|---------------------|--------------------------------------|
| Installation token (IAT) | ❌ 403         | ✅ (with admin:write on org) | ✅ (with admin:write on target + public template) |
| User access token (UAT)  | ✅            | ✅ (if member with admin)    | ✅                                    |
| Personal access token (PAT) | ✅         | ✅ (if member with admin)    | ✅                                    |

## Cross-references

- AGENTS.md `cq-write-failing-tests-before` — RED tests must verify the
  endpoint accepts the auth class, not just URL routing.
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` —
  template-generate trades UAT-credential-surface for public-template
  attribution surface; both single-user incident class.
- 2026-04-13 learning on `fetchWithRetry` and undici error codes — the
  new helper reuses the same `githubFetch` pattern.
