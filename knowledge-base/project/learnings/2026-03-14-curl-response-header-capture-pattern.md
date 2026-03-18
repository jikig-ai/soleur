# Learning: curl response header capture for APIs returning data in headers

## Problem

LinkedIn's Posts API returns the created post ID in the `x-restli-id` response header, not in the JSON body. The standard `curl -s -w "\n%{http_code}"` pattern used across all community platform scripts only captures the HTTP status code and response body — it cannot access response headers.

## Solution

Use `curl -D "$tmpfile"` to dump response headers to a temp file while still capturing the body and status code via `-w`:

```bash
local header_file
header_file=$(mktemp)
trap "rm -f '$header_file'" EXIT

response=$(curl -s -w "\n%{http_code}" \
  -D "$header_file" \
  -H "Authorization: Bearer ${TOKEN}" \
  -X POST -d "$json_body" \
  "$url" 2>/dev/null)

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

# Extract specific header
restli_id=$(grep -i '^x-restli-id:' "$header_file" | sed 's/^[^:]*: *//' | tr -d '\r')
rm -f "$header_file"
```

## Key Insight

When an API returns important data in response headers (post IDs, rate limit info, pagination cursors), the standard curl body+status pattern is insufficient. Use `-D <file>` for header capture. This is a structural deviation from the existing community script pattern — document it in the function so future maintainers understand why this request helper differs.

Also relevant: LinkedIn rate limit headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) are in headers, not body. The same `-D` pattern enables reading them if needed later.

## Tags

category: integration-issues
module: community/scripts
