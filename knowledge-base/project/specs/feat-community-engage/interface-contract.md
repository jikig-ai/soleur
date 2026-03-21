# Interface Contract: feat-community-engage

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `plugins/soleur/skills/community/scripts/x-community.sh`, `plugins/soleur/skills/community/SKILL.md`, `plugins/soleur/agents/support/community-manager.md`, `.gitignore` |
| Agent 2 (Tests) | `test/x-community.test.ts` |

## Public Interfaces

### x-community.sh fetch-mentions

**Command:** `x-community.sh fetch-mentions [--max-results N] [--since-id ID]`

**Arguments:**

- `--max-results N` -- Optional. Number of mentions to fetch. Default: 10. Valid range: 5-100. Must be numeric.
- `--since-id ID` -- Optional. Only return mentions newer than this tweet ID. Must be numeric.

**Exit codes:**

- `0` -- Success, JSON output on stdout
- `1` -- Error (missing credentials, invalid arguments, API error, malformed JSON)
- `2` -- Rate limit exceeded after 3 retries

**Error behavior:**

- Missing credentials (`X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`): exits 1 with "Missing X API credentials" on stderr
- `--max-results` non-numeric: exits 1 with usage error on stderr
- `--max-results` out of range (< 5 or > 100): exits 1 with range error on stderr
- `--since-id` non-numeric: exits 1 with usage error on stderr
- API returns empty data (`[]`): outputs `{"mentions":[],"meta":{"result_count":0}}` on stdout, exits 0
- API returns malformed JSON: exits 1 with "malformed JSON" on stderr

**Stdout JSON schema (success):**

```json
{
  "mentions": [
    {
      "id": "string",
      "text": "string",
      "author_username": "string",
      "author_name": "string",
      "created_at": "ISO8601 string",
      "conversation_id": "string"
    }
  ],
  "meta": {
    "newest_id": "string or null",
    "result_count": "number"
  }
}
```

**Implementation notes:**

- Uses `get_authenticated_user_id` internal helper (calls `GET /2/users/me`, returns `.data.id` to stdout)
- Calls `GET /2/users/{id}/mentions` with query params: `max_results`, `since_id` (if provided), `tweet.fields=author_id,created_at,conversation_id`, `expansions=author_id`, `user.fields=username,name`
- Query params included in OAuth signature base string (same pattern as `cmd_fetch_metrics`)
- Transforms response: joins `includes.users` to `data` by `author_id` field (not array index)
- Registered in `main()` case dispatch as `fetch-mentions`
- Usage text updated to include `fetch-mentions [--max-results N] [--since-id ID]`

### x-community.sh (existing commands, unchanged)

- `fetch-metrics` -- unchanged
- `post-tweet <text> [--reply-to ID]` -- unchanged

### Script conventions

- `set -euo pipefail` at top
- `${N:-}` guards for optional positional args
- `require_jq`, `require_openssl`, `require_credentials` already called in `main()` before dispatch
- Error messages to stderr (`>&2`)
- All variables declared `local`
- `[[ ]]` double-bracket tests
- `urlencode()` and `oauth_sign()` reused from existing code
