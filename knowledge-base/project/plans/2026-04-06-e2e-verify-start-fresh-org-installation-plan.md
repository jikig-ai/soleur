---
title: "E2E verify Start Fresh flow for org installation"
type: fix
date: 2026-04-06
---

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

3. Record current Sentry error count (baseline) using Sentry API:

   ```bash
   doppler run -c prd -- curl -s \
     "https://sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=1h" \
     -H "Authorization: Bearer $SENTRY_API_TOKEN" | jq 'length'
   ```

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
9. **Take screenshot** of the final "ready" state for evidence

### Phase 3: Post-verification Cleanup and Sentry Check

1. **Verify repo created on GitHub:**

   ```bash
   gh repo view jikig-ai/soleur-e2e-test-YYYYMMDD --json name,owner
   ```

2. **Query Sentry** for new unresolved errors in the last 15 minutes:

   ```bash
   doppler run -c prd -- curl -s \
     "https://sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved+firstSeen:>-15m" \
     -H "Authorization: Bearer $SENTRY_API_TOKEN" | jq 'length'
   ```

   Expected: `0` (no new errors)

3. **Clean up test repo** (delete the E2E test repo):

   ```bash
   gh repo delete jikig-ai/soleur-e2e-test-YYYYMMDD --yes
   ```

4. **Close issue #1673** with verification evidence:

   ```bash
   gh issue close 1673 --comment "Verified: Start Fresh flow completes for org installation. Repo created, setup reached 'ready' state, no Sentry errors."
   ```

## Acceptance Criteria

- [ ] Navigate to `/connect-repo`, select "Start Fresh", enter a project name
- [ ] Complete GitHub App install flow for `jikig-ai` org account
- [ ] Repo creation succeeds (`POST /api/repo/create` returns 200)
- [ ] Setup polling reaches `ready` state (`GET /api/repo/status` returns `{"status":"ready"}`)
- [ ] No new Sentry errors appear during the flow
- [ ] Test repo is cleaned up after verification
- [ ] Issue #1673 is closed with verification evidence

## Test Scenarios

### Browser (Playwright MCP)

- Navigate to `https://app.soleur.ai/connect-repo`, verify "Start Fresh" card visible
- Click "Start Fresh", fill project name `soleur-e2e-test-20260406`, submit
- Verify redirect to GitHub App install page
- After OAuth consent (user handoff), verify redirect back to `/connect-repo` with `installation_id` param
- Verify "Setting up" progress animation, then "Ready" state with repo name displayed
- Take screenshot of final state

### API Verify

- `gh repo view jikig-ai/soleur-e2e-test-20260406 --json name` expects `{"name":"soleur-e2e-test-20260406"}`
- Sentry API: `doppler run -c prd -- curl -s "https://sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved+firstSeen:>-15m" -H "Authorization: Bearer $SENTRY_API_TOKEN" | jq 'length'` expects `0`

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
