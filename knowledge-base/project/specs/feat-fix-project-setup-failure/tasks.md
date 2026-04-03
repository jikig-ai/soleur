# Tasks: fix project setup failure on redirect

## Phase 1: Fix GitHub identity resolution (RC1)

- [ ] 1.1 Modify `apps/web-platform/app/api/repo/install/route.ts` to query `auth.identities` table via service client instead of using `user.identities` from `getUser()`
  - [ ] 1.1.1 Add service client query: `.schema("auth").from("identities").select("identity_data").eq("user_id", user.id).eq("provider", "github").maybeSingle()`
  - [ ] 1.1.2 Extract `githubLogin` from `identityData?.identity_data?.user_name`
  - [ ] 1.1.3 Update security comment to explain why `auth.identities` table is used instead of `user.identities` or `user_metadata`
  - [ ] 1.1.4 Update error message to: "No GitHub identity linked to this account. Please sign in with GitHub first."
- [ ] 1.2 Add tests in `apps/web-platform/test/install-route.test.ts`
  - [ ] 1.2.1 Test: user with `identities: null` but valid `auth.identities` record succeeds
  - [ ] 1.2.2 Test: user with no GitHub identity in `auth.identities` returns 403
  - [ ] 1.2.3 Verify existing 13 tests pass (regression)

## Phase 2: Check setup response status (RC2)

- [ ] 2.1 Modify `startSetup` in `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - [ ] 2.1.1 Capture the response from `POST /api/repo/setup`
  - [ ] 2.1.2 Check `res.ok` and set `setState("failed")` + return early on non-OK responses

## Phase 3: Eliminate useEffect race condition (RC3)

- [ ] 3.1 Merge the two callback-handling `useEffect` hooks (lines 1021 and 1263) in `apps/web-platform/app/(auth)/connect-repo/page.tsx` into a single atomic effect
  - [ ] 3.1.1 Single effect processes install callback first
  - [ ] 3.1.2 Only then checks sessionStorage for pending create
  - [ ] 3.1.3 Falls through to fetchRepos if no pending create
  - [ ] 3.1.4 Remove the separate useEffect at line 1263

## Phase 4: Verification

- [ ] 4.1 Run full test suite: `node_modules/.bin/vitest run` in `apps/web-platform/`
- [ ] 4.2 TypeScript build: `npx tsc --noEmit`
- [ ] 4.3 Verify production user state: query Supabase for users with `github_installation_id` after deployment
