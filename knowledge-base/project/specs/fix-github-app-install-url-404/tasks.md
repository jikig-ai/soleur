# Tasks: fix GitHub App install URL 404

## Phase 1: Verify/Create GitHub App (Configuration)

- [ ] 1.1 Check if the GitHub App already exists via Playwright MCP (navigate to GitHub App settings)
- [ ] 1.2 If not exists: create GitHub App with correct permissions (contents:read+write, metadata:read, members:read), setup URL, and **public** visibility
- [ ] 1.3 If exists but private: change visibility to public
- [ ] 1.4 Store `GITHUB_APP_ID` in Doppler `prd` config
- [ ] 1.5 Store `GITHUB_APP_PRIVATE_KEY` in Doppler `prd` config
- [ ] 1.6 Store `NEXT_PUBLIC_GITHUB_APP_SLUG` in Doppler `prd` config
- [ ] 1.7 Verify app is accessible: `curl -s https://api.github.com/apps/<slug>` returns 200

## Phase 2: Server-Side Slug Resolution (Defense-in-Depth)

- [ ] 2.1 Add `getAppSlug()` function to `apps/web-platform/server/github-app.ts`
  - Call `GET https://api.github.com/app` with App JWT
  - Return `slug` field from response
  - Cache result in module-level variable (slug never changes at runtime)
- [ ] 2.2 Create `apps/web-platform/app/api/repo/app-info/route.ts`
  - `GET /api/repo/app-info` endpoint
  - Requires authenticated user (same pattern as other repo routes)
  - Returns `{ slug: string }`
  - Falls back to `NEXT_PUBLIC_GITHUB_APP_SLUG` env var if `getAppSlug()` fails
- [ ] 2.3 Update `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - Fetch slug from `/api/repo/app-info` on mount
  - Use fetched slug for all three redirect URLs (lines 1185, 1202, 1210)
  - Fall back to `NEXT_PUBLIC_GITHUB_APP_SLUG` env var if fetch fails
- [ ] 2.4 Write tests for `getAppSlug()` in `apps/web-platform/test/install-route.test.ts`
- [ ] 2.5 Write test for `/api/repo/app-info` route

## Phase 3: Deployment Configuration

- [ ] 3.1 Verify `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are passed to the Docker container at runtime
- [ ] 3.2 Add `NEXT_PUBLIC_GITHUB_APP_SLUG` as a build-time env var in the Docker build / CI pipeline
- [ ] 3.3 Redeploy the web platform to pick up new env vars

## Phase 4: Verification

- [ ] 4.1 Visit `https://github.com/apps/<slug>/installations/new` in incognito browser -- confirm no 404
- [ ] 4.2 Run full connect-repo flow as a non-owner user -- confirm redirect works
- [ ] 4.3 Run existing tests to confirm no regressions
