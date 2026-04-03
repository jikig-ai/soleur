# Tasks: fix GitHub App install URL 404

## Phase 1: Verify/Create GitHub App (Configuration)

- [x] 1.1 Check if the GitHub App already exists via Playwright MCP (navigate to `https://github.com/organizations/jikig-ai/settings/apps` or personal account settings)
- [x] 1.2 Created GitHub App "Soleur AI" (slug: `soleur-ai`, App ID: `3261325`) under jikig-ai org with:
  - Permissions: `contents:read+write`, `metadata:read`, `members:read`
  - Setup URL: `https://app.soleur.ai/connect-repo`
  - Callback URL: `https://app.soleur.ai/connect-repo`
  - Webhook: disabled
  - Visibility: **Public**
  - Where can this app be installed: **Any account**
- [x] 1.3 N/A (app was created new, not existing)
- [x] 1.4 Store `GITHUB_APP_ID` in Doppler `prd` config (numeric App ID: 3261325)
- [x] 1.5 Store `GITHUB_APP_PRIVATE_KEY` in Doppler `prd` config (PEM format)
- [x] 1.6 Store `NEXT_PUBLIC_GITHUB_APP_SLUG` in Doppler `prd` config (slug: `soleur-ai`)
- [x] 1.7 Verified app is publicly accessible: `curl -s https://api.github.com/apps/soleur-ai` returns 200 with correct slug

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

- [x] 3.1 Add `ARG NEXT_PUBLIC_GITHUB_APP_SLUG` to `apps/web-platform/Dockerfile` (Stage 2: builder)
- [x] 3.2 Add `NEXT_PUBLIC_GITHUB_APP_SLUG=${{ secrets.NEXT_PUBLIC_GITHUB_APP_SLUG }}` to `.github/workflows/reusable-release.yml` build-args section
- [x] 3.3 Add `NEXT_PUBLIC_GITHUB_APP_SLUG` as a GitHub Actions repository secret (set via `gh secret set`)
- [x] 3.4 Verified `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` in Doppler `prd` (runtime env vars, no Dockerfile changes needed)

## Phase 4: Verification

- [x] 4.1 Visited `https://github.com/apps/soleur-ai/installations/new` via Playwright -- "Install Soleur AI" page loads, no 404
- [ ] 4.2 Run full connect-repo flow (post-deploy verification)
- [x] 4.3 All 16 targeted tests pass (3 new + 13 existing install-route tests)
- [x] 4.4 CSRF coverage test passes (new GET route not flagged)
- [ ] 4.5 Deploy verification (post-merge)
