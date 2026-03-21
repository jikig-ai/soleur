# Learning: X API v2 GET requests require query params in OAuth signature

## Problem

Adding `fetch-mentions` and `fetch-timeline` commands to `x-community.sh` exposed three issues:

1. **OAuth signature mismatch on GET requests** -- `x_request` was built for POST with JSON bodies. OAuth 1.0a requires GET query parameters in the signature base string (sorted with oauth_* params). Signing only the base URL causes 401 errors.
2. **Absent `data` field on zero results** -- X API v2 schema specifies `minItems: 1` on the `data` array. When zero results, the field is absent entirely -- not `null`, not `[]`. Naive `jq '.data'` returns `null`.
3. **Query parameter injection via user flags** -- `--since` and `--max` values interpolated into query strings without validation allow arbitrary parameter injection (e.g., `--max "10&admin=true"`).

## Solution

Extracted `get_request` helper that splits query params on `&`, passes each as a `key=value` vararg to `oauth_sign`, then appends the raw query string to the request URL. Added strict input validation before interpolation:

```bash
# --since: strict ISO 8601 UTC regex
if [[ ! "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then

# --max: positive integer only
if [[ ! "$max_results" =~ ^[0-9]+$ ]]; then
```

Absent-data handling via `jq '.data // []'` normalizes output for both zero-result and populated responses.

## Key Insight

OAuth 1.0a signatures for GET requests MUST include query parameters in the signature base string alongside `oauth_*` params. Signing only the base URL produces a valid-looking Authorization header that the server rejects with 401. For any CLI tool that interpolates user input into URL query strings, validate against strict patterns before interpolation -- even when the "user" is another script.

## Tags

category: integration-issues
module: community
