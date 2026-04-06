---
title: "chore: production verification of GitHub project setup flow"
type: chore
date: 2026-04-06
issue: "#1489"
source_pr: "#1487"
deepened: 2026-04-06
---

# Production Verification of GitHub Project Setup Flow

Verify the complete GitHub project setup flow works in production after the GoTrue admin API fix deployed via PR #1487. This is a follow-through verification task created by `/ship` Phase 7 Step 3.5 -- no code changes expected.

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 4 (Test Scenarios, Implementation Plan, Context, sharp edges)
**Research sources:** 5 institutional learnings applied

### Key Improvements

1. Added concrete Sentry API query commands with correct org slug and statsPeriod constraints
2. Added Supabase REST API verification commands for `github_installation_id` and `repo_error`
3. Added Playwright auth workaround (OTP flow, not magic link) from prior session learning
4. Added sharp edges section documenting known Sentry SDK gap (#1533) and health endpoint bug

### Learnings Applied

- `sentry-zero-events-production-verification-20260405` -- Sentry server-side SDK has never sent events; cannot rely on zero Sentry errors as evidence of no errors
- `silent-setup-failure-no-error-capture-20260403` -- Sentry org slug is `jikigai`; `repo_error` column exists for error persistence
- `production-observability-sentry-pino-health-web-platform-20260328` -- Health endpoint returns version, uptime, supabase status; Playwright auth requires OTP flow
- `github-app-install-url-404-20260403` -- GitHub App slug is `soleur-ai`, callback URL is `https://app.soleur.ai/connect-repo`
- `github-org-membership-api-redirect-handling-20260402` -- Org installations use membership verification

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

- **API verify (Sentry error audit):** Query Sentry API for unresolved issues in the last 14 days. Use `SENTRY_API_TOKEN` from Doppler `prd` config. Org slug is `jikigai` (not `jikig`). Only `24h` and `14d` are valid `statsPeriod` values.

```bash
SENTRY_TOKEN=$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain)
SENTRY_PROJECT=$(doppler secrets get SENTRY_PROJECT -p soleur -c prd --plain)
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://de.sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/?statsPeriod=14d&query=getUserById+OR+PGRST106+OR+identity" \
  | jq 'length'
```

Expect: 0 matching issues. **Known caveat:** The Sentry server-side SDK may not be sending events at all (see sharp edges). Zero Sentry issues is necessary but not sufficient evidence -- must also verify via database state.

- **API verify (health):**

```bash
curl -s https://app.soleur.ai/health | jq '.'
```

Expect: `{"status":"ok","version":"...","supabase":"connected","uptime":...,"memory":...}`. The `version` field confirms the deployed build. **Known caveat:** The `supabase` field uses `checkSupabase()` which hits `/rest/v1/` (root, no table) and returns 401 -- the field may show `"error"` even when Supabase is reachable. Use the direct table query below as the definitive check.

- **API verify (user records):** Query Supabase directly for users with populated `github_installation_id` to confirm at least one user has completed the flow since deploy.

```bash
SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)
SUPABASE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
curl -s -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
  "$SUPABASE_URL/rest/v1/users?select=id,github_installation_id,repo_status,repo_error&github_installation_id=not.is.null&limit=5" \
  | jq '.'
```

Expect: At least 1 user with `github_installation_id` set and `repo_status` not `"error"`. If `repo_error` is populated, investigate.

- **API verify (no stuck errors):** Check for users with `repo_status = "error"` that may have been caused by the old bug.

```bash
curl -s -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
  "$SUPABASE_URL/rest/v1/users?select=id,repo_status,repo_error&repo_status=eq.error&limit=10" \
  | jq '.'
```

Expect: Zero users stuck in error state from identity resolution failures. If errors exist, check `repo_error` for `PGRST106` or `No GitHub identity` messages.

### Scenario 2: Browser End-to-End Flow (via Playwright)

Navigate through the full GitHub project setup flow as a logged-in user.

**Authentication prerequisite:** Use the OTP flow for Playwright auth. Do NOT use magic links -- the magic link `#access_token=...` fragment is not processed by the app's client-side router. Instead:

1. Navigate to `https://app.soleur.ai/login`
2. Enter email and request OTP
3. Use Supabase `generate_link` admin API to retrieve the OTP code (bypasses email delivery)
4. Enter OTP to complete authentication

**Alternate auth (if GitHub OAuth needed):** If the account requires GitHub OAuth, automate up to the GitHub consent screen and hand off to the user for that single interaction.

**Setup flow verification:**

1. **Navigate** to the connect-repo page at `https://app.soleur.ai/connect-repo`
2. **Take screenshot** of initial state (should show "choose" state with options)
3. **Click** "Connect Existing Repository" to start the GitHub App install flow
4. **Observe** redirect to `https://github.com/apps/soleur-ai/installations/new` -- if the app is already installed, expect redirect back with `?installation_id=...&setup_action=install`
5. **After install callback:** Verify the page transitions to repo selection (not "interrupted" or "failed")
6. **Take screenshot** of repo selection state
7. **Select a repository** and verify the setup flow begins (status transitions through "cloning")
8. **Take screenshot** of final state

**Success criteria:** No "interrupted" or "failed" states reached. If GitHub App is already installed for the org, the callback should skip straight to repo selection.

### Scenario 3: Sentry Error Audit

- Query Sentry API for unresolved issues in the web-platform project from the last 14 days (not 72 hours -- `statsPeriod` only accepts `24h` and `14d`)
- Filter for `auth`, `install`, `identity`, `PGRST`, or `getUserById` keywords
- Expect zero matching unresolved issues
- **Important:** Zero Sentry issues does NOT confirm zero errors (see sharp edges). Cross-reference with database state from Scenario 1.

## Implementation Plan

### Phase 1: Observability Check (Automated)

1. Retrieve `SENTRY_API_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` from Doppler `prd` config
2. Query Sentry API for recent errors using the exact commands from Scenario 1 (use `de.sentry.io` API endpoint, not `sentry.io` -- DSN uses EU region)
3. Check production health endpoint at `https://app.soleur.ai/health`
4. Query Supabase REST API for users with `github_installation_id IS NOT NULL`
5. Query Supabase for users with `repo_status = 'error'` to check for residual failures

### Phase 2: Browser Verification (Playwright MCP)

1. Authenticate via OTP flow (use `generate_link` admin API for OTP retrieval)
2. Navigate to connect-repo page and take screenshot
3. Walk through the GitHub App install flow via Playwright
4. Capture screenshots at each state transition for evidence
5. Verify no error states ("interrupted", "failed") are reached
6. Close browser when verification is complete (`browser_close`)

### Phase 3: Close Issue

1. If all verifications pass: close #1489 with a summary comment listing evidence (Sentry query results, Supabase query results, screenshots)
2. If any verification fails: document the failure, create a follow-up fix issue with the specific failure details, and leave #1489 open

## Context

### Files Involved

| File | Role |
|------|------|
| `apps/web-platform/app/api/repo/install/route.ts` | Install route handler (fixed in #1487) |
| `apps/web-platform/app/api/repo/setup/route.ts` | Setup route handler (reads `github_installation_id`) |
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Client-side connect-repo flow |
| `apps/web-platform/test/install-route-handler.test.ts` | Unit tests for install route |
| `apps/web-platform/server/github-app.ts` | GitHub App JWT auth, installation verification |

### Related Issues

- #1461 -- Original bug: "Project Setup Failed" for all users (closed by #1487)
- #1487 -- Fix PR: use GoTrue admin API for GitHub identity resolution
- #1533 -- Sentry server-side SDK not sending events (may affect Scenario 3 reliability)
- #1534 -- Workspace permission bug (root-owned files cause rm -rf failure)

### Key Learning

- PostgREST does not expose the `auth` schema. Never use `.schema("auth")` via Supabase JS client.
- `auth.admin.getUserById()` uses the GoTrue admin endpoint and reliably returns identity data for all user types including email-first users who later linked GitHub.
- See `knowledge-base/project/learnings/integration-issues/supabase-identities-null-email-first-users-20260403.md`

## Sharp Edges

- **Sentry may not be functional:** The learning from 2026-04-05 documents that the Sentry server-side SDK has NEVER sent events from the production container. The root cause is likely `SENTRY_DSN` not reaching the container runtime (tracked in #1533). Zero Sentry errors is therefore unreliable evidence -- always cross-verify with database state (repo_status, repo_error columns).
- **Health endpoint Supabase check bug:** `checkSupabase()` in `server/index.ts` queries `/rest/v1/` (root, no table), which returns 401. The `supabase` field in the health response may show `"error"` even when Supabase is fully operational. Use direct table queries (Scenario 1 commands) for definitive Supabase connectivity verification.
- **Playwright auth pitfall:** Magic links produce `#access_token=...` fragments that are not processed by the app's client-side router. Always use the OTP flow with `generate_link` admin API for Playwright authentication.
- **GitHub App already installed:** If the GitHub App is already installed for the `jikig-ai` org (installation ID 121112974), the install flow will redirect back immediately with the existing installation ID. The verification should still work -- the `POST /api/repo/install` endpoint accepts any valid installation ID.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- production verification of an existing bug fix.

## MVP

No code changes. Output is a verification report (GitHub issue comment) with evidence from Sentry, Supabase queries, and Playwright screenshots.
