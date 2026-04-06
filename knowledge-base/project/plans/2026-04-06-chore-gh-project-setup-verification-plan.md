---
title: "chore: production verification of GitHub project setup flow"
type: chore
date: 2026-04-06
issue: "#1489"
source_pr: "#1487"
---

# Production Verification of GitHub Project Setup Flow

Verify the complete GitHub project setup flow works in production after the GoTrue admin API fix deployed via PR #1487. This is a follow-through verification task created by `/ship` Phase 7 Step 3.5 -- no code changes expected.

## Background

PR #1487 fixed a critical bug where `POST /api/repo/install` returned 403 for all users because PostgREST does not expose the `auth` schema. The fix replaced `.schema("auth").from("identities")` with `auth.admin.getUserById()` which uses the GoTrue admin endpoint. The PR merged on 2026-04-03 and deployed successfully via the Web Platform Release workflow.

### Deploy Verification (Pre-Confirmed)

- PR #1487 merge commit `66b32f7` is an ancestor of the latest successful deploy (`8b1eb098`)
- Web Platform Release workflow succeeded on 2026-04-06 (run ID 24025474937)
- All production Doppler secrets are present: `SUPABASE_SERVICE_ROLE_KEY`, `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`

## Acceptance Criteria

- [ ] `POST /api/repo/install` returns 200 with a valid `installationId` for a user with linked GitHub identity
- [ ] The install route correctly resolves the GitHub username via `auth.admin.getUserById()`
- [ ] The `github_installation_id` is stored on the user record after successful install
- [ ] `POST /api/repo/setup` succeeds with a valid `repoUrl` after installation is stored
- [ ] The full connect-repo page flow completes without hitting "Setup Was Interrupted" or "Project Setup Failed"
- [ ] No Sentry errors related to `auth.admin.getUserById`, `PGRST106`, or identity resolution appear in the last 3 days

## Test Scenarios

### Scenario 1: API-Level Verification

Verify the install route handler returns correct responses using direct API calls.

- **API verify (identity resolution):** Query Sentry for errors matching `getUserById` or `PGRST106` in the last 72 hours. Expect zero errors.
- **API verify (health):** `curl -s https://api.soleur.ai/health` -- expect 200 with `{"status":"ok"}` or equivalent.
- **API verify (user record):** Query Supabase for any user with `github_installation_id IS NOT NULL` to confirm at least one user has completed the flow since deploy.

### Scenario 2: Browser End-to-End Flow (via Playwright)

Navigate through the full GitHub project setup flow as a logged-in user:

1. **Navigate** to the connect-repo page at `https://app.soleur.ai/connect-repo` (or equivalent)
2. **Click** "Connect Existing Repository" to start the GitHub App install flow
3. **Observe** the GitHub App installation redirect -- expect redirect to `github.com/apps/soleur-ai/installations/new`
4. **After install callback:** Verify the page transitions to repo selection (not "interrupted" or "failed")
5. **Select a repository** and verify the setup flow begins (status transitions through "cloning" to "ready")

**Note:** Browser testing requires an authenticated session. If OAuth consent is required, automate up to the consent screen and hand off to the user for that single interaction.

### Scenario 3: Sentry Error Audit

- Query Sentry API for unresolved issues in the web-platform project from the last 72 hours
- Filter for `auth`, `install`, `identity`, `PGRST`, or `getUserById` keywords
- Expect zero matching unresolved issues

## Implementation Plan

### Phase 1: Observability Check (Automated)

1. Query Sentry API using `SENTRY_API_TOKEN` from Doppler `prd` config for recent errors
2. Check production health endpoint
3. Query Supabase for users with populated `github_installation_id`

### Phase 2: Browser Verification (Playwright MCP)

1. Navigate to the web platform and authenticate
2. Walk through the connect-repo flow via Playwright
3. Capture screenshots at each step for evidence
4. Verify no error states are reached

### Phase 3: Close Issue

1. If all verifications pass: close #1489 with a summary comment listing evidence
2. If any verification fails: document the failure, create a follow-up fix issue, and leave #1489 open

## Context

### Files Involved

| File | Role |
|------|------|
| `apps/web-platform/app/api/repo/install/route.ts` | Install route handler (fixed in #1487) |
| `apps/web-platform/app/api/repo/setup/route.ts` | Setup route handler (reads `github_installation_id`) |
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Client-side connect-repo flow |
| `apps/web-platform/test/install-route-handler.test.ts` | Unit tests for install route |

### Related Issues

- #1461 -- Original bug: "Project Setup Failed" for all users (closed by #1487)
- #1487 -- Fix PR: use GoTrue admin API for GitHub identity resolution

### Key Learning

- PostgREST does not expose the `auth` schema. Never use `.schema("auth")` via Supabase JS client.
- `auth.admin.getUserById()` uses the GoTrue admin endpoint and reliably returns identity data for all user types including email-first users who later linked GitHub.
- See `knowledge-base/project/learnings/integration-issues/supabase-identities-null-email-first-users-20260403.md`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- production verification of an existing bug fix.

## MVP

No code changes. Output is a verification report (GitHub issue comment) with evidence from Sentry, Supabase queries, and Playwright screenshots.
