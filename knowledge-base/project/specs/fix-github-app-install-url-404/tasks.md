# Tasks: fix GitHub App install URL 404

## Phase 1: Verify/Create GitHub App (Configuration)

- [ ] 1.1 Check if the GitHub App already exists via Playwright MCP (navigate to `https://github.com/organizations/jikig-ai/settings/apps` or personal account settings)
- [ ] 1.2 If not exists: create GitHub App via `https://github.com/settings/apps/new` with:
  - Permissions: `contents:read+write`, `metadata:read`, `members:read`
  - Setup URL: `https://app.soleur.ai/connect-repo`
  - Callback URL: `https://app.soleur.ai/connect-repo`
  - Webhook: disabled
  - Visibility: **Public**
  - Where can this app be installed: **Any account**
- [ ] 1.3 If exists but private: change visibility to public (irreversible once other accounts install)
- [ ] 1.4 Store `GITHUB_APP_ID` in Doppler `prd` config (numeric App ID)
- [ ] 1.5 Store `GITHUB_APP_PRIVATE_KEY` in Doppler `prd` config (PEM format, `\n`-escaped newlines)
- [ ] 1.6 Store `NEXT_PUBLIC_GITHUB_APP_SLUG` in Doppler `prd` config (URL slug, e.g., `soleur`)
- [ ] 1.7 Verify app is publicly accessible: `curl -s https://api.github.com/apps/<slug> | jq '.slug'` returns the slug (not 404)

## Phase 2: Server-Side Slug Resolution (Defense-in-Depth)

### 2.1 Tests First (TDD)

- [ ] 2.1.1 Write test: `getAppSlug()` calls `GET /app` with JWT and returns `slug` field
- [ ] 2.1.2 Write test: `getAppSlug()` returns cached value on second call without API request
- [ ] 2.1.3 Write test: `getAppSlug()` falls back to env var when `GITHUB_APP_ID` is not set (does not throw)
- [ ] 2.1.4 Write test: `GET /api/repo/app-info` returns 401 for unauthenticated users
- [ ] 2.1.5 Write test: `GET /api/repo/app-info` returns `{ slug }` for authenticated users

### 2.2 Implementation

- [ ] 2.2.1 Add `getAppSlug()` function to `apps/web-platform/server/github-app.ts`
  - Call `GET https://api.github.com/app` with App JWT
  - Return `slug` field from response
  - Cache result in module-level variable (slug never changes at runtime)
  - If `GITHUB_APP_ID` is not set, fall back to `process.env.NEXT_PUBLIC_GITHUB_APP_SLUG` (do not throw)
- [ ] 2.2.2 Create `apps/web-platform/app/api/repo/app-info/route.ts`
  - `GET /api/repo/app-info` endpoint
  - Requires authenticated user (`createClient()` + `supabase.auth.getUser()` pattern from `repos/route.ts`)
  - Returns `{ slug: string }`
  - Falls back to `NEXT_PUBLIC_GITHUB_APP_SLUG` env var if `getAppSlug()` fails
  - No CSRF protection needed (GET route -- CSRF test only checks POST)
- [ ] 2.2.3 Update `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - Replace hardcoded `GITHUB_APP_SLUG` constant (line 54) with state
  - Initialize state from `NEXT_PUBLIC_GITHUB_APP_SLUG` env var (available at build time)
  - Fetch slug from `/api/repo/app-info` on mount and update state
  - All three redirect URLs (lines 1185, 1202, 1210) use the stateful slug value
  - Fall back to env var value if fetch fails

## Phase 3: Deployment Configuration

- [ ] 3.1 Add `ARG NEXT_PUBLIC_GITHUB_APP_SLUG` to `apps/web-platform/Dockerfile` (Stage 2: builder, alongside existing `NEXT_PUBLIC_*` ARGs on lines 13-15)
- [ ] 3.2 Add `NEXT_PUBLIC_GITHUB_APP_SLUG=${{ secrets.NEXT_PUBLIC_GITHUB_APP_SLUG }}` to `.github/workflows/reusable-release.yml` build-args section (lines 289-292)
- [ ] 3.3 Add `NEXT_PUBLIC_GITHUB_APP_SLUG` as a GitHub Actions repository secret: `gh secret set NEXT_PUBLIC_GITHUB_APP_SLUG`
- [ ] 3.4 Verify `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are available at runtime via Doppler `prd` download (no Dockerfile changes needed for runtime env vars)

## Phase 4: Verification

- [ ] 4.1 Visit `https://github.com/apps/<slug>/installations/new` in incognito browser (Playwright) -- confirm no 404, Install button visible
- [ ] 4.2 Run full connect-repo flow: sign up, reach connect-repo page, click Connect -- confirm redirect works
- [ ] 4.3 Run existing tests: `cd apps/web-platform && npx vitest run` -- confirm no regressions
- [ ] 4.4 Verify CSRF coverage test passes (new GET route should not trigger it)
- [ ] 4.5 Trigger a deploy and verify the canary health check passes with the new env vars
