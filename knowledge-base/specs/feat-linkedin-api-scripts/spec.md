# Spec: LinkedIn API Scripts

**Issue:** #589
**Branch:** feat/linkedin-api-scripts
**Brainstorm:** [2026-03-13-linkedin-api-scripts-brainstorm.md](../../brainstorms/2026-03-13-linkedin-api-scripts-brainstorm.md)

## Problem Statement

LinkedIn API automation is blocked on a false premise — the issue states "Blocked on LinkedIn API App approval" but the `w_member_social` posting permission is self-service. Analytics endpoints require Marketing Developer Platform (MDP) approval, but posting does not. Additionally, LinkedIn's 60-day access token lifecycle (without programmatic refresh) creates a silent failure risk for a solo operator with no monitoring.

## Goals

1. Ship functional LinkedIn posting capability (`post-content`) using the self-service `w_member_social` permission
2. Provide analytics command stubs (`fetch-metrics`, `fetch-activity`) that activate when Marketing API credentials are available
3. Automate token generation via Playwright-assisted OAuth flow
4. Monitor token expiry proactively with schedulable health checks and Discord notifications
5. Follow the established `x-community.sh` pattern for consistency

## Non-Goals

- Marketing API analytics implementation (requires MDP approval — separate PR)
- Programmatic refresh token flow (requires MDP approval)
- LinkedIn Company Page creation (manual browser action)
- Community adapter interface refactor (#470)
- Support runbooks directory creation (pre-existing gap)

## Functional Requirements

- **FR1:** `linkedin-community.sh post-content --text "<content>" [--visibility public|connections]` posts to LinkedIn using the Share API with Bearer token auth
- **FR2:** `linkedin-community.sh fetch-metrics` exits with code 1 and a message indicating Marketing API credentials are required
- **FR3:** `linkedin-community.sh fetch-activity` exits with code 1 and a message indicating Marketing API credentials are required
- **FR4:** `linkedin-setup.sh validate-credentials` calls `/oauth/v2/introspectToken` and reports: active/expired, days remaining, granted scopes
- **FR5:** `linkedin-setup.sh generate-token` invokes Playwright to drive the OAuth flow, captures the token, and writes it to `.env`
- **FR6:** `linkedin-setup.sh check-expiry` checks token TTL and sends Discord notification at configurable thresholds (default: 14 days, 7 days)
- **FR7:** `linkedin-setup.sh write-env` persists `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN` to `.env` with `chmod 600`

## Technical Requirements

- **TR1:** Shell hardening: `set -euo pipefail`, 5-layer defense pattern (input, transport, response parsing, error extraction, retry arithmetic)
- **TR2:** Depth-limited retries (max 3) for transient failures and rate limiting
- **TR3:** Exit codes: 0 (success), 1 (general error), 2 (retryable/rate-limit)
- **TR4:** JSON output to stdout, errors to stderr
- **TR5:** Source guard (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`) for test harness compatibility
- **TR6:** `require_jq()` startup check
- **TR7:** Never leak tokens — suppress curl stderr (`2>/dev/null`), no tokens in CLI args, `chmod 600` before writing secrets
- **TR8:** Community SKILL.md updated with LinkedIn in platform detection table, scripts list, `platforms` sub-command, and setup instructions

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `LINKEDIN_CLIENT_ID` | Yes | LinkedIn Developer App client ID |
| `LINKEDIN_CLIENT_SECRET` | Yes | LinkedIn Developer App client secret |
| `LINKEDIN_ACCESS_TOKEN` | Yes | OAuth 2.0 Bearer token (60-day TTL) |
| `LINKEDIN_REFRESH_TOKEN` | No | Programmatic refresh token (MDP partners only, 365-day TTL) |
| `LINKEDIN_ORGANIZATION_ID` | No | Company page URN for organization-level posting |

## API Endpoints

| Endpoint | Method | Purpose | Auth |
|----------|--------|---------|------|
| `https://api.linkedin.com/v2/ugcPosts` | POST | Create posts | Bearer token + `w_member_social` |
| `https://www.linkedin.com/oauth/v2/introspectToken` | POST | Token validation | Client credentials |
| `https://www.linkedin.com/oauth/v2/accessToken` | POST | Token exchange/refresh | Client credentials |
| `https://www.linkedin.com/oauth/v2/authorization` | GET | OAuth authorization | N/A (browser redirect) |
