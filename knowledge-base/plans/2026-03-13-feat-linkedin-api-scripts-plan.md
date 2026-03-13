---
title: "feat: LinkedIn API Scripts (linkedin-community.sh, linkedin-setup.sh)"
type: feat
date: 2026-03-13
---

# feat: LinkedIn API Scripts

## Overview

Create `linkedin-community.sh` and `linkedin-setup.sh` in `plugins/soleur/skills/community/scripts/` following the `x-community.sh` pattern. The community script provides a live `post-content` command (using self-service `w_member_social` scope) and stub analytics commands gated on Marketing API approval. The setup script provides token lifecycle management: introspection-based validation, Playwright-assisted OAuth generation, and scheduled expiry monitoring with Discord alerts.

## Problem Statement / Motivation

Issue #589 was filed as "Blocked on LinkedIn API App approval" — but research reveals that the `w_member_social` posting permission is **self-service** and available immediately. Only analytics endpoints require MDP partner approval. This means posting can ship now.

Additionally, LinkedIn's 60-day access token lifecycle without programmatic refresh tokens creates a silent failure risk. When the token expires, posting and monitoring break with no alert. The solo operator needs proactive monitoring to avoid data outages.

## Proposed Solution

### `linkedin-community.sh` — Platform API Wrapper

Follow the x-community.sh 10-section layout, replacing OAuth 1.0a signing with simple Bearer token auth. LinkedIn's auth is the simplest across all platforms.

**Commands:**

| Command | Status | API | Scope |
|---------|--------|-----|-------|
| `post-content --text "<text>" [--visibility public\|connections] [--author person\|organization]` | Live | `POST /rest/posts` | `w_member_social` (person) or `w_organization_social` (org) |
| `fetch-metrics` | Stub | Marketing API | MDP approval required |
| `fetch-activity` | Stub | Marketing API | MDP approval required |

**Critical API details (from live docs, 2026-02-18):**

- **Endpoint:** `POST https://api.linkedin.com/rest/posts` (NOT `/v2/ugcPosts` — deprecated)
- **Required headers:**
  - `Authorization: Bearer {token}`
  - `X-Restli-Protocol-Version: 2.0.0`
  - `Linkedin-Version: 202602` (versioned API — use current YYYYMM)
  - `Content-Type: application/json`
- **Request body:**
  ```json
  {
    "author": "urn:li:person:{id}",
    "commentary": "Post text",
    "visibility": "PUBLIC",
    "distribution": {
      "feedDistribution": "MAIN_FEED",
      "targetEntities": [],
      "thirdPartyDistributionChannels": []
    },
    "lifecycleState": "PUBLISHED",
    "isReshareDisabledByAuthor": false
  }
  ```
- **Response:** 201, post ID in `x-restli-id` response header (not JSON body)
- **Person URN:** Requires resolving the authenticated user's person ID (via `/v2/userinfo` or OpenID Connect profile endpoint)

### `linkedin-setup.sh` — Token Lifecycle Management

**Commands:**

| Command | Description |
|---------|-------------|
| `validate-credentials` | POST to `/oauth/v2/introspectToken` with client_id, client_secret, token. Reports: active/expired, days remaining, granted scopes. |
| `generate-token` | Playwright-assisted OAuth flow. Drives browser to LinkedIn Developer Portal token generator, user handles login + consent click. Captures token from the result page. |
| `check-expiry` | Calls `validate-credentials` internally. If days remaining < threshold (default 14), sends Discord notification via webhook. Designed for GitHub Actions cron scheduling. |
| `write-env` | Persists `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN` to `.env` with `chmod 600`. |
| `verify` | Sources `.env` and runs `validate-credentials` as a round-trip check. |

### SKILL.md Updates

Update `plugins/soleur/skills/community/SKILL.md` in 4 places:
1. **Platform Detection table:** LinkedIn row already exists (just `LINKEDIN_ACCESS_TOKEN`). Add `LINKEDIN_CLIENT_ID` and `LINKEDIN_CLIENT_SECRET` as required for full functionality.
2. **Scripts list:** Add `linkedin-community.sh` and `linkedin-setup.sh` entries.
3. **`platforms` sub-command:** LinkedIn line already present. Update setup instructions to reference `linkedin-setup.sh`.
4. **Setup instructions:** Replace current "Set LINKEDIN_ACCESS_TOKEN" with `linkedin-setup.sh` commands.

## Technical Considerations

### Auth Simplification

LinkedIn Bearer token auth eliminates all complexity from x-community.sh:
- No `urlencode()` function (not needed for Bearer)
- No `oauth_sign()` function (not needed)
- No `require_openssl()` (not needed)
- Auth is a single header: `Authorization: Bearer ${LINKEDIN_ACCESS_TOKEN}`

This means `linkedin-community.sh` will be ~250-300 lines (vs. x-community.sh at 642 lines).

### LinkedIn-Specific Headers

The `Linkedin-Version` header requires a YYYYMM format value. This should be a constant at the top of the script (e.g., `LINKEDIN_API_VERSION="202602"`). When LinkedIn deprecates a version, updating the constant is the only change needed.

### Person URN Resolution

To post as a person, we need the authenticated user's LinkedIn person URN (`urn:li:person:{id}`). The `profile` scope (self-service, via "Sign in with LinkedIn using OpenID Connect") provides access to `/v2/userinfo` which returns the user's `sub` field. This `sub` value is the person ID.

Alternatively, we can accept the person URN as an env var (`LINKEDIN_PERSON_URN`) to avoid an extra API call on every post.

### Response Handler Adaptation

LinkedIn errors use a different format than X/Twitter. LinkedIn returns:
```json
{
  "status": 403,
  "serviceErrorCode": 100,
  "code": "ACCESS_DENIED",
  "message": "Not enough permissions to access: POST /rest/posts"
}
```

The response handler needs to extract `.message` (not `.detail` like X). The jq fallback chain: `.message // .code // "Unknown error"`.

### Token Introspection Response

`/oauth/v2/introspectToken` returns:
```json
{
  "active": true,
  "client_id": "xxxx",
  "created_at": 1493055596,
  "expires_at": 1497497620,
  "scope": "r_liteprofile,w_member_social",
  "auth_type": "3L"
}
```

Days remaining: `((expires_at - $(date +%s)) / 86400)`.

### Playwright Token Generation

The `generate-token` command needs to:
1. Check if `agent-browser` CLI is available
2. Drive browser to `https://www.linkedin.com/developers/tools/oauth/token-generator`
3. Wait for user to log in (manual step)
4. Select scopes (`w_member_social`, `profile`)
5. Click authorize
6. Wait for user to click "Allow" on consent screen (manual step)
7. Capture the generated token from the result page
8. Write to `.env` via `write-env`

Fallback: if Playwright is not available, print the URL and instructions for manual token generation.

### Discord Notification for check-expiry

The `check-expiry` command sends a Discord notification using the existing `DISCORD_WEBHOOK_URL` pattern:
```bash
curl -s -H "Content-Type: application/json" \
  -d '{"content":"⚠️ LinkedIn token expires in N days. Run linkedin-setup.sh generate-token to renew."}' \
  "$DISCORD_WEBHOOK_URL"
```

If `DISCORD_WEBHOOK_URL` is not set, print the warning to stderr only (graceful degradation).

## Acceptance Criteria

### linkedin-community.sh
- [ ] `post-content --text "Hello"` creates a LinkedIn post and outputs the post URN
- [ ] `post-content --text "Hello" --visibility connections` restricts to connections
- [ ] `post-content --text "Hello" --author organization` posts as organization (requires `LINKEDIN_ORGANIZATION_ID`)
- [ ] `fetch-metrics` exits with code 1 and message: "Marketing API credentials required"
- [ ] `fetch-activity` exits with code 1 and message: "Marketing API credentials required"
- [ ] Response handler correctly extracts LinkedIn error messages (`.message // .code`)
- [ ] Rate limiting (429) triggers depth-limited retry (max 3)
- [ ] Missing credentials prints setup instructions referencing `linkedin-setup.sh`
- [ ] All output follows contract: JSON to stdout, errors to stderr
- [ ] Source guard allows sourcing without execution

### linkedin-setup.sh
- [ ] `validate-credentials` reports token status (active/expired), days remaining, scopes
- [ ] `validate-credentials` with expired token prints renewal instructions
- [ ] `generate-token` launches Playwright and captures token (with fallback to manual URL)
- [ ] `check-expiry` sends Discord notification when days remaining < threshold
- [ ] `check-expiry` with no `DISCORD_WEBHOOK_URL` prints warning to stderr only
- [ ] `write-env` writes 3 vars to `.env` with `chmod 600`
- [ ] `write-env` preserves existing non-LinkedIn vars in `.env`
- [ ] `verify` sources `.env` and validates via API

### SKILL.md
- [ ] Platform detection table lists LinkedIn with all required vars
- [ ] Scripts list includes `linkedin-community.sh` and `linkedin-setup.sh`
- [ ] `platforms` sub-command references `linkedin-setup.sh` for setup
- [ ] Setup instructions updated

### Shell Hardening
- [ ] `set -euo pipefail` at top
- [ ] 5-layer defense: input validation, transport (curl stderr suppressed), response parsing (JSON validation), error extraction (jq fallback chain), retry arithmetic (printf '%.0f')
- [ ] Depth-limited retries (max 3) with `depth` parameter
- [ ] Exit codes: 0 (success), 1 (general error), 2 (retryable/rate-limit exhaustion)
- [ ] `require_jq()` startup check
- [ ] Token never appears in CLI args, ps output, or curl stderr
- [ ] `chmod 600` before writing secrets to `.env`

## Test Scenarios

- Given valid credentials, when `post-content --text "test"`, then post is created and URN returned as JSON
- Given expired token, when `post-content --text "test"`, then 401 error with renewal instructions
- Given no credentials set, when any command runs, then missing vars listed with setup instructions
- Given rate limit (429), when posting, then retry up to 3 times with backoff
- Given valid token with 10 days remaining, when `check-expiry --threshold 14`, then Discord notification sent
- Given valid token with 30 days remaining, when `check-expiry --threshold 14`, then no notification, success exit
- Given no DISCORD_WEBHOOK_URL, when `check-expiry` triggers alert, then warning printed to stderr only
- Given .env with existing Discord vars, when `write-env`, then LinkedIn vars added without removing Discord vars
- Given `--author organization` without `LINKEDIN_ORGANIZATION_ID`, then error with instructions

## Success Metrics

- `post-content` successfully creates a LinkedIn post via API
- `validate-credentials` correctly reports token TTL within 1-day accuracy
- `check-expiry` sends Discord notification before token expires (tested via dry run)
- All scripts pass `shellcheck` with zero warnings
- Pattern consistency: structure matches x-community.sh sections 1-10

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| LinkedIn API version deprecation | Post endpoint breaks | `LINKEDIN_API_VERSION` constant — single update point |
| `w_member_social` scope changes | Posting blocked | Monitor LinkedIn API changelog |
| Person URN resolution adds latency | Extra API call per post | Cache person URN in env var (`LINKEDIN_PERSON_URN`) |
| Playwright unavailable in CI | `generate-token` fails | Fallback to manual URL + instructions |
| LinkedIn revokes token early | Silent failure | `check-expiry` cron catches within 24h |
| Posts API request body format changes | 400 errors on post | Version pin (`Linkedin-Version` header) |

## References & Research

### Internal References
- Pattern: `plugins/soleur/skills/community/scripts/x-community.sh` (642 lines, 10-section layout)
- Setup pattern: `plugins/soleur/skills/community/scripts/x-setup.sh` (327 lines)
- Hardening: `knowledge-base/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Retry pattern: `knowledge-base/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Token security: `knowledge-base/learnings/2026-02-18-token-env-var-not-cli-arg.md`
- Brainstorm: `knowledge-base/brainstorms/2026-03-13-linkedin-api-scripts-brainstorm.md`
- Spec: `knowledge-base/specs/feat-linkedin-api-scripts/spec.md`

### External References
- LinkedIn Posts API: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api
- LinkedIn OAuth 2.0: https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow
- Token Introspection: https://learn.microsoft.com/en-us/linkedin/shared/authentication/token-introspection
- Programmatic Refresh Tokens: https://learn.microsoft.com/en-us/linkedin/shared/authentication/programmatic-refresh-tokens
- Getting API Access: https://learn.microsoft.com/en-us/linkedin/shared/authentication/getting-access

### Related Work
- Parent issue: #138 (LinkedIn Presence)
- This issue: #589
- Downstream: #590 (content-publisher), #592 (workflow secrets)
- Draft PR: #608
