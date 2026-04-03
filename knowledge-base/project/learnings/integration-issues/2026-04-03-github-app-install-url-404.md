---
module: Web Platform
date: 2026-04-03
problem_type: integration_issue
component: authentication
symptoms:
  - "GitHub App install URL https://github.com/apps/soleur-ai/installations/new returns 404"
  - "New users cannot complete onboarding connect-repo step"
  - "GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY missing from all Doppler configs"
root_cause: incomplete_setup
resolution_type: environment_setup
severity: high
tags: [github-app, oauth, onboarding, env-vars, docker-build-args]
---

# Troubleshooting: GitHub App Install URL Returns 404 During Onboarding

## Problem

New users completing GitHub OAuth and reaching the connect-repo onboarding step were redirected to `https://github.com/apps/soleur-ai/installations/new`, which returned a 404 page. The GitHub App had never been created, and no credentials were provisioned to any environment.

## Environment

- Module: Web Platform (connect-repo page)
- Affected Component: `apps/web-platform/app/(auth)/connect-repo/page.tsx`, `apps/web-platform/server/github-app.ts`
- Date: 2026-04-03

## Symptoms

- Visiting `https://github.com/apps/soleur-ai/installations/new` returned GitHub 404 page
- `gh api /apps/soleur-ai` returned 404
- `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `NEXT_PUBLIC_GITHUB_APP_SLUG` absent from all Doppler configs (dev, prd, ci, prd_terraform)
- `server/github-app.ts` throws `Error("GITHUB_APP_ID is not set")` on any call

## What Didn't Work

**Direct solution:** The root cause was identified immediately via API probe and Doppler secret inventory. No incorrect approaches were tried.

## Session Errors

**Ralph loop setup script not found**

- **Recovery:** Skipped and continued with the pipeline
- **Prevention:** Verify script paths exist before referencing them in skill definitions

**GitHub App name "Soleur" rejected — reserved by @soleur account**

- **Recovery:** Used "Soleur AI" instead, which generated the slug `soleur-ai`
- **Prevention:** When creating GitHub Apps, check name availability first via the API or be prepared with alternative names

**"Any account" radio reset after form validation error**

- **Recovery:** Re-selected "Any account" before resubmitting
- **Prevention:** After fixing a form validation error, re-verify all previously set fields before resubmitting — GitHub's form can reset non-errored fields

## Solution

Three-part fix:

**1. Create the GitHub App (configuration)**

Created "Soleur AI" GitHub App under the jikig-ai org via Playwright MCP:

- Slug: `soleur-ai` (App ID: 3261325)
- Permissions: `contents:read+write`, `metadata:read`, `members:read`
- Visibility: Public (any account can install)
- Webhook: disabled
- Setup/Callback URL: `https://app.soleur.ai/connect-repo`

Stored credentials in Doppler `prd`: `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `NEXT_PUBLIC_GITHUB_APP_SLUG`.

**2. Add server-side slug resolution (defense-in-depth)**

```typescript
// server/github-app.ts — new getAppSlug() function
export async function getAppSlug(): Promise<string> {
  if (cachedSlug) return cachedSlug;
  // Falls back to env var if GITHUB_APP_ID not set
  // Fetches from GET /app with JWT if credentials available
  // Validates slug format against /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
  // Caches result in module-level variable
}
```

New `GET /api/repo/app-info` route returns `{ slug }` for authenticated users. Frontend fetches on mount with env var fallback.

**3. Wire build-time env var through Docker**

```dockerfile
# Dockerfile Stage 2 (builder)
ARG NEXT_PUBLIC_GITHUB_APP_SLUG
```

```yaml
# reusable-release.yml build-args
NEXT_PUBLIC_GITHUB_APP_SLUG=${{ secrets.NEXT_PUBLIC_GITHUB_APP_SLUG }}
```

## Why This Works

The root cause was twofold: (1) the GitHub App never existed — the repo-connection feature was implemented in a prior session but credentials were never provisioned, and (2) `NEXT_PUBLIC_GITHUB_APP_SLUG` was not wired as a Docker build ARG, so even if set, Next.js would not inline it at build time.

The fix creates the app, provisions all credentials, and ensures the slug reaches the client bundle via the Docker build pipeline. The server-side `getAppSlug()` adds defense-in-depth: if the app is ever renamed but the env var is not updated, the JWT-authenticated API call will return the correct slug.

## Prevention

- When implementing a feature that depends on external service credentials (GitHub App, OAuth provider, API keys), verify credentials are provisioned in ALL target environments before marking the feature complete
- `NEXT_PUBLIC_*` env vars must be passed as Docker `ARG` at build time — they are NOT available at runtime in client components. Check the Dockerfile when adding new `NEXT_PUBLIC_*` vars
- After creating external resources (GitHub Apps, scheduled tasks, Doppler configs), validate they are accessible from outside the owner account before shipping

## Related Issues

No related issues documented yet.
