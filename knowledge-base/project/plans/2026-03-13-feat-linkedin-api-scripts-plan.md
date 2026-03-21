---
title: "feat: LinkedIn API Scripts (linkedin-community.sh, linkedin-setup.sh)"
type: feat
date: 2026-03-13
---

# feat: LinkedIn API Scripts

## Overview

Create `linkedin-community.sh` and `linkedin-setup.sh` in `plugins/soleur/skills/community/scripts/` following the `x-community.sh` pattern. The community script provides a live `post-content` command (using self-service `w_member_social` scope) and stub analytics commands gated on Marketing API approval. The setup script provides token lifecycle management: introspection-based validation with expiry warnings, standard OAuth authorization code exchange, and credential persistence.

## Problem Statement / Motivation

Issue #589 was filed as "Blocked on LinkedIn API App approval" — but research reveals that the `w_member_social` posting permission is **self-service** and available immediately. Only analytics endpoints require MDP partner approval. This means posting can ship now.

Additionally, LinkedIn's 60-day access token lifecycle without programmatic refresh tokens creates a silent failure risk. When the token expires, posting and monitoring break with no alert. The solo operator needs proactive monitoring to avoid data outages.

## Proposed Solution

### `linkedin-community.sh` — Platform API Wrapper

Follow the x-community.sh 10-section layout, replacing OAuth 1.0a signing with simple Bearer token auth. LinkedIn's auth is the simplest across all platforms.

**Commands:**

| Command | Status | API | Scope |
|---------|--------|-----|-------|
| `post-content --text "<text>"` | Live | `POST /rest/posts` | `w_member_social` |
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
- **Response header capture:** The standard `curl -s -w "\n%{http_code}"` pattern cannot capture response headers. Use `curl -s -D -` to dump headers to stdout, then parse `x-restli-id` from the header block. This is a structural deviation from `x-community.sh` that must be handled in the `post_request` helper.
- **Person URN:** Resolved from `LINKEDIN_PERSON_URN` env var (required). Set once via `/v2/userinfo` `sub` field during setup; cached as env var to avoid an extra API call per post.

### `linkedin-setup.sh` — Token Lifecycle Management

**Commands:**

| Command | Description |
|---------|-------------|
| `validate-credentials` | POST to `/oauth/v2/introspectToken` with client_id, client_secret, token. Reports: active/expired, days remaining, granted scopes. Supports `--warn-days N` flag — exits non-zero when token TTL is below threshold (default: 14). Designed for CI cron: `linkedin-setup.sh validate-credentials --warn-days 14`. |
| `generate-token` | Prints the OAuth authorization URL (optionally opens with `xdg-open`/`open`). Prompts user to paste the authorization code. Exchanges code for token via `curl` to `/oauth/v2/accessToken`. Writes token via `write-env`. |
| `write-env` | Persists `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN` to `.env` with `chmod 600`. |
| `verify` | Sources `.env` and runs `validate-credentials` as a round-trip check. |

**Credential requirements differ per script:**

- `linkedin-community.sh` needs: `LINKEDIN_ACCESS_TOKEN` (Bearer auth) + `LINKEDIN_PERSON_URN` (author URN)
- `linkedin-setup.sh` needs: `LINKEDIN_CLIENT_ID` + `LINKEDIN_CLIENT_SECRET` + `LINKEDIN_ACCESS_TOKEN` (introspection uses client credentials as POST body params, not Bearer)

### `community-router.sh` Update

Add LinkedIn to the `PLATFORMS` array:

```bash
"linkedin|linkedin-community.sh|LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN|"
```

### SKILL.md Updates

Update `plugins/soleur/skills/community/SKILL.md` in 4 places:

1. **Platform Detection table:** LinkedIn row already exists (just `LINKEDIN_ACCESS_TOKEN`). Add `LINKEDIN_PERSON_URN` as required. Note `LINKEDIN_CLIENT_ID` and `LINKEDIN_CLIENT_SECRET` required for setup/introspection only.
2. **Scripts list:** Add `linkedin-community.sh` and `linkedin-setup.sh` entries.
3. **`platforms` sub-command:** LinkedIn line already present. Update setup instructions to reference `linkedin-setup.sh`.
4. **Setup instructions:** Replace current "Set LINKEDIN_ACCESS_TOKEN" with `linkedin-setup.sh` commands.

**Out of scope:** LinkedIn is not added to the `engage` sub-command (no reply/mention support in this PR — person posting only).

## Technical Considerations

### Auth Simplification

LinkedIn Bearer token auth eliminates all complexity from x-community.sh:

- No `urlencode()` function (not needed for Bearer)
- No `oauth_sign()` function (not needed)
- No `require_openssl()` (not needed)
- Auth is a single header: `Authorization: Bearer ${LINKEDIN_ACCESS_TOKEN}`

This means `linkedin-community.sh` will be ~200 lines (vs. x-community.sh at 642 lines).

### LinkedIn-Specific Headers

The `Linkedin-Version` header requires a YYYYMM format value. This should be a constant at the top of the script (e.g., `LINKEDIN_API_VERSION="202602"`). When LinkedIn deprecates a version, updating the constant is the only change needed.

### Person URN Resolution

To post as a person, we need the authenticated user's LinkedIn person URN (`urn:li:person:{id}`). The `profile` scope (self-service, via "Sign in with LinkedIn using OpenID Connect") provides access to `/v2/userinfo` which returns the user's `sub` field. This `sub` value is the person ID.

**Decision:** Accept person URN as a required env var (`LINKEDIN_PERSON_URN`). This avoids an extra API call on every post and is consistent with the platform pattern (env var for identity). The `generate-token` command should resolve and persist the person URN during token setup.

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

### Response Header Capture

LinkedIn returns the post ID in the `x-restli-id` response header, not in the JSON body. The standard `curl -s -w "\n%{http_code}"` pattern used across all community scripts only captures status code and body.

**Solution:** For `post_request`, use `curl -s -D "$tmpfile"` to dump response headers to a temp file, then extract `x-restli-id` with grep. This is a LinkedIn-specific deviation — document it in the function.

### Rate Limit Handling

LinkedIn returns rate limit info via `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` response headers — not in the response body. Since the standard curl pattern does not capture headers (except via the approach above), use a hardcoded retry delay (5 seconds) on 429, consistent with `bsky-community.sh`.

**POST retry policy:** Only retry POST requests on 429 (rate limit — returned before the post is created). For any other transient error on POST, fail immediately. LinkedIn's Posts API is not idempotent — retrying a POST that may have succeeded risks duplicate posts. GET requests may retry on any transient error.

### Token Introspection Response

`/oauth/v2/introspectToken` returns:

```json
{
  "active": true,
  "client_id": "xxxx",
  "created_at": 1493055596,
  "expires_at": 1497497620,
  "scope": "openid,profile,w_member_social",
  "auth_type": "3L"
}
```

Days remaining: `((expires_at - $(date +%s)) / 86400)`.

Note: `r_liteprofile` scope is deprecated. Current scopes use OpenID Connect equivalents (`openid`, `profile`, `email`).

### Token Generation Flow

The `generate-token` command uses the standard OAuth 2.0 authorization code flow:

1. Print the authorization URL: `https://www.linkedin.com/oauth/v2/authorization?response_type=code&client_id=${LINKEDIN_CLIENT_ID}&redirect_uri=...&scope=openid%20profile%20w_member_social`
2. Optionally open URL with `xdg-open` (Linux) or `open` (macOS)
3. Prompt user to paste the authorization code from the redirect
4. Exchange code for token via `curl -s -X POST https://www.linkedin.com/oauth/v2/accessToken` with `grant_type=authorization_code`, `code`, `client_id`, `client_secret`, `redirect_uri`
5. Parse access token from JSON response
6. Resolve person URN via `curl -s -H "Authorization: Bearer $token" https://api.linkedin.com/v2/userinfo` and extract `sub` field
7. Write token + person URN via `write-env`

No Playwright dependency. No browser automation. Works in any terminal.

## Acceptance Criteria

### linkedin-community.sh

- [ ] `post-content --text "Hello"` creates a LinkedIn post and outputs the post URN
- [ ] Post URN extracted from `x-restli-id` response header
- [ ] `fetch-metrics` exits with code 1 and message: "Marketing API credentials required"
- [ ] `fetch-activity` exits with code 1 and message: "Marketing API credentials required"
- [ ] Response handler correctly extracts LinkedIn error messages (`.message // .code`)
- [ ] Rate limiting (429) triggers retry (max 3, hardcoded 5s delay)
- [ ] POST requests only retry on 429, not on other transient errors
- [ ] Missing credentials prints setup instructions referencing `linkedin-setup.sh`
- [ ] All output follows contract: JSON to stdout, errors to stderr
- [ ] Source guard allows sourcing without execution
- [ ] Empty `--text` is rejected with error
- [ ] Text exceeding 3000 characters is rejected with error (LinkedIn post limit)

### linkedin-setup.sh

- [ ] `validate-credentials` reports token status (active/expired), days remaining, scopes
- [ ] `validate-credentials` with expired token prints renewal instructions
- [ ] `validate-credentials --warn-days 14` exits non-zero when TTL < 14 days
- [ ] `generate-token` prints OAuth URL, accepts auth code, exchanges for token, resolves person URN, writes via `write-env`
- [ ] `write-env` writes 4 vars to `.env` with `chmod 600`
- [ ] `verify` sources `.env` and validates via API
- [ ] No source guard (consistent with `x-setup.sh` and `bsky-setup.sh` convention)

### community-router.sh

- [ ] LinkedIn entry in PLATFORMS array with correct env vars and script name

### SKILL.md

- [ ] Platform detection table lists LinkedIn with required vars
- [ ] Scripts list includes `linkedin-community.sh` and `linkedin-setup.sh`
- [ ] `platforms` sub-command references `linkedin-setup.sh` for setup
- [ ] Setup instructions updated
- [ ] `engage` sub-command explicitly does NOT include LinkedIn (out of scope)

### Shell Hardening

- [ ] `set -euo pipefail` at top
- [ ] Input validation, curl stderr suppression, JSON response parsing, jq error extraction fallback chain, printf-safe retry arithmetic
- [ ] Depth-limited retries (max 3) for GET requests; 429-only retry for POST
- [ ] Exit codes: 0 (success), 1 (general error), 2 (retryable/rate-limit exhaustion)
- [ ] `require_jq()` startup check
- [ ] Token never appears in CLI args, ps output, or curl stderr
- [ ] `chmod 600` before writing secrets to `.env`

## Test Scenarios

- Given valid credentials, when `post-content --text "test"`, then post is created and URN returned as JSON
- Given expired token, when `post-content --text "test"`, then 401 error with renewal instructions
- Given no credentials set, when any command runs, then missing vars listed with setup instructions
- Given rate limit (429), when posting, then retry up to 3 times with 5s delay
- Given valid token with 10 days remaining, when `validate-credentials --warn-days 14`, then exit non-zero with warning
- Given valid token with 30 days remaining, when `validate-credentials --warn-days 14`, then exit 0
- Given empty `--text ""`, then error with message about required text
- Given text > 3000 chars, then error with character limit message
- Given `.env` with existing Discord vars, when `write-env`, then LinkedIn vars added without removing Discord vars

## Success Metrics

- `post-content` successfully creates a LinkedIn post via API
- `validate-credentials` correctly reports token TTL within 1-day accuracy
- `validate-credentials --warn-days 14` exits non-zero for tokens expiring within 14 days (testable in CI cron)
- All scripts pass `shellcheck` with zero warnings
- Pattern consistency: structure matches x-community.sh sections 1-10

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| LinkedIn API version deprecation | Post endpoint breaks | `LINKEDIN_API_VERSION` constant — single update point |
| `w_member_social` scope changes | Posting blocked | Monitor LinkedIn API changelog |
| Person URN resolution adds setup step | Extra env var to configure | `generate-token` auto-resolves and persists person URN |
| LinkedIn revokes token early | Silent failure | `validate-credentials --warn-days 14` in CI cron catches within 24h |
| Posts API request body format changes | 400 errors on post | Version pin (`Linkedin-Version` header) |

## References & Research

### Internal References

- Pattern: `plugins/soleur/skills/community/scripts/x-community.sh` (642 lines, 10-section layout)
- Setup pattern: `plugins/soleur/skills/community/scripts/x-setup.sh` (327 lines)
- Router: `plugins/soleur/skills/community/scripts/community-router.sh` (PLATFORMS array)
- Hardening: `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Retry pattern: `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Token security: `knowledge-base/project/learnings/2026-02-18-token-env-var-not-cli-arg.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-13-linkedin-api-scripts-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-linkedin-api-scripts/spec.md`

### External References

- LinkedIn Posts API: <https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api>
- LinkedIn OAuth 2.0: <https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow>
- Token Introspection: <https://learn.microsoft.com/en-us/linkedin/shared/authentication/token-introspection>
- Programmatic Refresh Tokens: <https://learn.microsoft.com/en-us/linkedin/shared/authentication/programmatic-refresh-tokens>
- Getting API Access: <https://learn.microsoft.com/en-us/linkedin/shared/authentication/getting-access>

### Related Work

- Parent issue: #138 (LinkedIn Presence)
- This issue: #589
- Downstream: #590 (content-publisher), #592 (workflow secrets)
- Draft PR: #608
