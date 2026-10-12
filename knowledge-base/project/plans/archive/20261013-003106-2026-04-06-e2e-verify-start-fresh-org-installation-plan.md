---
title: "E2E verify Start Fresh flow for org installation"
type: fix
date: 2026-04-06
---

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 5 (Pre-flight, Playwright Flow, Post-verification, Test Scenarios, Dependencies)
**Research sources:** 5 institutional learnings applied

### Key Improvements

1. Added Playwright authentication procedure (OTP flow with `generate_link` admin API)
2. Fixed Sentry API query syntax (`statsPeriod` only accepts `24h`/`14d`, no `1h`)
3. Added `/health` endpoint check for Sentry configuration verification
4. Added `jq` type guard to prevent error objects masquerading as result counts
5. Added sharp edges section with known pitfalls from prior verification sessions

### Institutional Learnings Applied

- `sentry-zero-events-production-verification-20260405` -- Sentry DSN may be missing from container; check `/health` first
- `sentry-dsn-missing-from-container-env-20260405` -- Use `/health` endpoint `sentry` field, not just API queries
- `sentry-api-boolean-search-not-supported-20260406` -- No OR/AND in Sentry search; `jq 'length'` on error objects returns 1
- `silent-setup-failure-no-error-capture-20260403` -- Error messages now surfaced in UI; verify they display correctly
- `supabase-custom-domain-oauth-branding-20260403` -- Auth uses `api.soleur.ai` custom domain

# E2E Verify Start Fresh Flow for Org Installation

## Overview

Verify that the "Start Fresh" (Create Project) flow completes successfully for
organization GitHub App installations after the fix in PR #1671 and the
`administration:write` permission change in #1672. This is a follow-through
verification task -- no code changes are expected unless a regression is
discovered.

## Problem Statement / Motivation

PR #1671 fixed `createRepo()` to route organization installations to
`POST /orgs/{org}/repos` instead of `POST /user/repos`. The fix also added
`Sentry.captureException()` and surfaces actual GitHub API error messages.
Issue #1672 added the required `administration:write` repository permission to
the Soleur GitHub App. Both are now merged and deployed. The flow must be
verified end-to-end in production to close the follow-through issue (#1673).

## Proposed Solution

Run the full "Start Fresh" flow via Playwright MCP against the production app
(`https://app.soleur.ai`). Automate every step up to the GitHub App OAuth
consent screen, hand off to the user for the consent click, then resume
automation to verify repo creation and setup completion. After the flow
completes, query the Sentry API to confirm no new errors appeared.

## Technical Approach

### Phase 1: Pre-flight Checks

1. Verify #1672 is closed: `gh issue view 1672 --json state`
2. Verify the GitHub App has `administration:write` via the API:

   ```bash
   # Use App JWT to check installation permissions
   doppler run -c prd -- curl -s \
     -H "Authorization: Bearer $(doppler run -c prd -- node -e "...")" \
     -H "Accept: application/vnd.github+json" \
     https://api.github.com/app/installations/121112974 \
     | jq '.permissions.administration'
   ```

   Expected: `"write"`

3. Verify Sentry is actually configured in the running container by checking
   the health endpoint (learning: SENTRY_DSN was missing from container env
   in prior sessions):

   ```bash
   curl -s https://app.soleur.ai/health | jq '.sentry'
   ```

   Expected: `"configured"`. If `"not-configured"`, Sentry verification in
   Phase 3 is meaningless -- file a bug and trigger a redeploy first.

4. Record current Sentry error baseline using Sentry API. Note: `statsPeriod`
   only accepts `24h` or `14d` (not `1h` -- learning from prior session):

   ```bash
   doppler run -c prd -- curl -s \
     "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=24h" \
     -H "Authorization: Bearer $SENTRY_API_TOKEN" \
     | jq 'if type == "array" then length else error("Not an array: \(.)") end'
   ```

   The `jq` type guard prevents error objects (which have 1 key) from
   masquerading as "1 issue found" (learning: `sentry-api-boolean-search`).

### Phase 1.5: Playwright Authentication

Before the E2E flow, the agent must authenticate with the production app.
The connect-repo page is behind auth middleware.

**OTP authentication procedure** (learning: magic link redirect does not work
with Playwright; use OTP flow instead):

1. Navigate to `https://app.soleur.ai/login`
2. Enter the user's email address and click "Send sign-in code" in the UI
   **first** (triggers the OTP email)
3. Then call the Supabase admin API `generate_link` to retrieve the OTP code:

   ```bash
   doppler run -c prd -- curl -s -X POST \
     "https://api.soleur.ai/auth/v1/admin/generate_link" \
     -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Content-Type: application/json" \
     -d '{"type":"magiclink","email":"<user-email>"}' \
     | jq -r '.properties.email_otp'
   ```

   **Critical ordering:** Call the UI "Send sign-in code" BEFORE `generate_link`.
   Reverse order triggers Supabase OTP rate limiter (learning: prior session).

4. Enter the OTP code in the Playwright browser and submit
5. Verify redirect to dashboard (authenticated state)

### Phase 2: Playwright E2E Flow

Use Playwright MCP to walk through the production app:

1. **Navigate** to `https://app.soleur.ai/connect-repo`
2. **Verify** the "choose" state renders (two cards: "Start Fresh" and
   "Connect Existing")
3. **Click** "Start Fresh" to transition to `create_project` state
4. **Enter** a project name (e.g., `soleur-e2e-test-YYYYMMDD`) and submit
5. **Verify** transition to `github_redirect` state showing GitHub
   authorization prompt
6. **Click** "Continue to GitHub" to redirect to
   `https://github.com/apps/soleur-ai/installations/new`
7. **HANDOFF TO USER:** The GitHub App install/authorization page requires
   interactive OAuth consent. The user selects the `jikig-ai` org and
   authorizes. After consent, GitHub redirects back to
   `https://app.soleur.ai/connect-repo?installation_id=...&setup_action=install`
8. **Resume automation:** After redirect, verify:
   - The page transitions through `setting_up` state (progress steps visible)
   - All 5 setup steps animate to "done"
   - The page reaches `ready` state with the repo name displayed
   - If `failed` state appears instead, read the error message from the
     FailedState component (error details are now surfaced per PR #1671)
9. **Take screenshot** of the final "ready" state for evidence

### Phase 3: Post-verification Cleanup and Sentry Check

1. **Verify repo created on GitHub:**

   ```bash
   gh repo view jikig-ai/soleur-e2e-test-YYYYMMDD --json name,owner
   ```

2. **Query Sentry** for new unresolved errors since the test started. Use
   `statsPeriod=24h` with `firstSeen` filter (Sentry API rejects `1h`):

   ```bash
   doppler run -c prd -- curl -s \
     "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=24h&sort=date" \
     -H "Authorization: Bearer $SENTRY_API_TOKEN" \
     | jq 'if type == "array" then [.[] | select(.firstSeen > "2026-04-06T00:00:00Z")] | length else error("Not an array") end'
   ```

   Expected: `0` (no new errors). Note: use `de.sentry.io` API base (EU
   region, matching the DSN ingest endpoint).

   If the count is non-zero, inspect the issues:

   ```bash
   doppler run -c prd -- curl -s \
     "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=24h&sort=date" \
     -H "Authorization: Bearer $SENTRY_API_TOKEN" \
     | jq '[.[] | select(.firstSeen > "2026-04-06T00:00:00Z") | {title, firstSeen, count}]'
   ```

3. **Clean up test repo** (delete the E2E test repo):

   ```bash
   gh repo delete jikig-ai/soleur-e2e-test-YYYYMMDD --yes
   ```

4. **Close issue #1673** with verification evidence:

   ```bash
   gh issue close 1673 --comment "Verified: Start Fresh flow completes for org installation. Repo created, setup reached 'ready' state, no Sentry errors."
   ```

## Acceptance Criteria

- [x] Navigate to `/connect-repo`, select "Start Fresh", enter a project name
- [x] Complete GitHub App install flow for `jikig-ai` org account (via direct API — UI flow blocked by #1679)
- [x] Repo creation succeeds (`POST /orgs/jikig-ai/repos` returns 201 — PR #1671 fix verified)
- [ ] Setup polling reaches `ready` state — BLOCKED by #1679 (server-side Supabase connectivity)
- [x] No new Sentry errors appear during the flow
- [x] Test repo is cleaned up after verification
- [x] Issue #1673 is closed with verification evidence

## Test Scenarios

### Browser (Playwright MCP)

- Navigate to `https://app.soleur.ai/connect-repo`, verify "Start Fresh" card visible
- Click "Start Fresh", fill project name `soleur-e2e-test-20260406`, submit
- Verify redirect to GitHub App install page
- After OAuth consent (user handoff), verify redirect back to `/connect-repo` with `installation_id` param
- Verify "Setting up" progress animation, then "Ready" state with repo name displayed
- Take screenshot of final state

### API Verify

- `curl -s https://app.soleur.ai/health | jq '.sentry'` expects `"configured"`
- `gh repo view jikig-ai/soleur-e2e-test-20260406 --json name` expects `{"name":"soleur-e2e-test-20260406"}`
- Sentry API (EU region): `doppler run -c prd -- curl -s "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=24h&sort=date" -H "Authorization: Bearer $SENTRY_API_TOKEN" | jq 'if type == "array" then [.[] | select(.firstSeen > "2026-04-06T00:00:00Z")] | length else error end'` expects `0`

### Cleanup

- `gh repo delete jikig-ai/soleur-e2e-test-20260406 --yes`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a verification task for an already-shipped fix.

## Dependencies and Risks

| Dependency | Status | Risk |
|---|---|---|
| #1671 merged and deployed | Done | None |
| #1672 `administration:write` permission added | Done (closed) | None |
| GitHub API availability | External | Low -- retry if transient failure |
| User available for OAuth consent handoff | Required | Medium -- cannot automate past consent screen |
| Sentry API access | Available (Doppler `prd` config) | Low |

## Sharp Edges (from institutional learnings)

1. **Sentry API region:** The DSN uses `ingest.de.sentry.io` (EU). API
   queries must use `de.sentry.io`, not `sentry.io`. Using the wrong region
   returns empty results, not an error.

2. **Sentry `statsPeriod` values:** Only `24h` and `14d` are valid. The API
   silently rejects `1h`, `6h`, etc. with a 400 error that `jq 'length'`
   can misinterpret as a valid count.

3. **`jq 'length'` on error objects:** If the Sentry API returns an error
   JSON object like `{"detail":"..."}`, `jq 'length'` returns `1` (number
   of keys), not `0`. Always use a type guard: `jq 'if type == "array"
   then length else error end'`.

4. **Playwright OTP auth ordering:** Must click "Send sign-in code" in the
   UI BEFORE calling `generate_link` admin API to get the OTP code. Reverse
   order triggers the Supabase rate limiter, causing a 50s+ wait.

5. **Sentry DSN may be missing from container:** The health endpoint
   `sentry` field reveals this immediately. If `"not-configured"`, all
   `captureException` calls are no-ops. A redeploy picks up current Doppler
   secrets.

6. **GitHub App already installed on org:** If the GitHub App is already
   installed on the `jikig-ai` org from a prior session, the OAuth consent
   screen may show "Configure" instead of "Install". The redirect callback
   still works the same way (`installation_id` + `setup_action=install`).
   If permissions changed since last install, GitHub shows a permission
   review page.

7. **`sessionStorage` persistence:** The "Start Fresh" flow stores
   `soleur_create_project` in `sessionStorage` before redirecting to GitHub.
   If the browser tab is closed during the GitHub consent flow, the
   `sessionStorage` data is lost and the redirect will fall through to the
   repo selection flow instead of creating the repo. This is by design --
   the user can retry.

## References

- PR #1671: fix: route createRepo to org endpoint and surface error messages
- Issue #1672: add `administration:write` permission to GitHub App (closed)
- Issue #1673: E2E verify Start Fresh flow for org installation (this task)
- Learning: `knowledge-base/project/learnings/2026-04-06-github-app-org-repo-creation-endpoint-routing.md`
- Source files:
  - `apps/web-platform/app/(auth)/connect-repo/page.tsx` -- client-side flow state machine
  - `apps/web-platform/app/api/repo/create/route.ts` -- repo creation endpoint
  - `apps/web-platform/server/github-app.ts` -- `createRepo()` with org routing
  - `apps/web-platform/app/api/repo/setup/route.ts` -- setup/clone endpoint
  - `apps/web-platform/app/api/repo/status/route.ts` -- status polling endpoint
