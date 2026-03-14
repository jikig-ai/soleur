# Spec: LinkedIn API Scripts

**Issue:** #589
**Branch:** feat/linkedin-api-scripts
**Brainstorm:** [2026-03-13-linkedin-api-scripts-brainstorm.md](../../brainstorms/2026-03-13-linkedin-api-scripts-brainstorm.md)

## Problem Statement

LinkedIn API automation is blocked on a false premise — the issue states "Blocked on LinkedIn API App approval" but the `w_member_social` posting permission is self-service. Analytics endpoints require Marketing Developer Platform (MDP) approval, but posting does not. Additionally, LinkedIn's 60-day access token lifecycle (without programmatic refresh) creates a silent failure risk for a solo operator with no monitoring.

## Goals

1. Ship functional LinkedIn posting capability (`post-content`) using the self-service `w_member_social` permission
2. Provide analytics command stubs (`fetch-metrics`, `fetch-activity`) that activate when Marketing API credentials are available
3. Provide standard OAuth authorization code exchange for token generation
4. Monitor token expiry proactively via `validate-credentials --warn-days N` (CI cron compatible)
5. Follow the established `x-community.sh` pattern for consistency

## Non-Goals

- Marketing API analytics implementation (requires MDP approval — separate PR)
- Programmatic refresh token flow (requires MDP approval)
- LinkedIn Company Page creation (manual browser action)
- Organization-level posting (`w_organization_social` — separate scope, separate PR)
- `--visibility connections` flag (hardcode PUBLIC — defer until needed)
- Community adapter interface refactor (#470)
- Support runbooks directory creation (pre-existing gap)
- LinkedIn in `engage` sub-command (no reply/mention support in this PR)

## Functional Requirements

- **FR1:** `linkedin-community.sh post-content --text "<content>"` posts to LinkedIn using the Posts API (`POST /rest/posts`) with Bearer token auth. Visibility hardcoded to PUBLIC.
- **FR2:** `linkedin-community.sh fetch-metrics` exits with code 1 and a message indicating Marketing API credentials are required
- **FR3:** `linkedin-community.sh fetch-activity` exits with code 1 and a message indicating Marketing API credentials are required
- **FR4:** `linkedin-setup.sh validate-credentials` calls `/oauth/v2/introspectToken` and reports: active/expired, days remaining, granted scopes. Supports `--warn-days N` flag that exits non-zero when TTL is below threshold.
- **FR5:** `linkedin-setup.sh generate-token` prints OAuth authorization URL, accepts authorization code from user, exchanges for token via `/oauth/v2/accessToken`, resolves person URN, writes to `.env`
- **FR6:** `linkedin-setup.sh write-env` persists `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN` to `.env` with `chmod 600`
- **FR7:** `community-router.sh` PLATFORMS array includes LinkedIn entry

## Technical Requirements

- **TR1:** Shell hardening: `set -euo pipefail`, input validation, curl stderr suppression, JSON response parsing, jq error extraction fallback chain, printf-safe retry arithmetic
- **TR2:** Depth-limited retries (max 3) for GET requests; 429-only retry for POST (non-idempotent endpoint)
- **TR3:** Exit codes: 0 (success), 1 (general error), 2 (retryable/rate-limit)
- **TR4:** JSON output to stdout, errors to stderr
- **TR5:** Source guard on `linkedin-community.sh` only (consistent with existing convention — setup scripts do not have source guards)
- **TR6:** `require_jq()` startup check
- **TR7:** Never leak tokens — suppress curl stderr (`2>/dev/null`), no tokens in CLI args, `chmod 600` before writing secrets
- **TR8:** Community SKILL.md updated with LinkedIn in platform detection table, scripts list, `platforms` sub-command, and setup instructions
- **TR9:** `community-router.sh` PLATFORMS array updated with LinkedIn entry
- **TR10:** Post URN extracted from `x-restli-id` response header via curl header dump (structural deviation from standard pattern — document in code)
- **TR11:** Input validation: reject empty `--text`, reject text > 3000 characters (LinkedIn post limit)

## Environment Variables

| Variable | Required For | Description |
|----------|-------------|-------------|
| `LINKEDIN_ACCESS_TOKEN` | Both scripts | OAuth 2.0 Bearer token (60-day TTL) |
| `LINKEDIN_PERSON_URN` | linkedin-community.sh | Person URN for posting (`urn:li:person:{id}`) |
| `LINKEDIN_CLIENT_ID` | linkedin-setup.sh | LinkedIn Developer App client ID (needed for introspection + token exchange) |
| `LINKEDIN_CLIENT_SECRET` | linkedin-setup.sh | LinkedIn Developer App client secret (needed for introspection + token exchange) |

## API Endpoints

| Endpoint | Method | Purpose | Auth |
|----------|--------|---------|------|
| `https://api.linkedin.com/rest/posts` | POST | Create posts | Bearer token + `w_member_social` |
| `https://api.linkedin.com/v2/userinfo` | GET | Resolve person URN | Bearer token + `openid profile` |
| `https://www.linkedin.com/oauth/v2/introspectToken` | POST | Token validation | Client credentials (POST body) |
| `https://www.linkedin.com/oauth/v2/accessToken` | POST | Token exchange | Client credentials (POST body) |
| `https://www.linkedin.com/oauth/v2/authorization` | GET | OAuth authorization | N/A (browser redirect) |
