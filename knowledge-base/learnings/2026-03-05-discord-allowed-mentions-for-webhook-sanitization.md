# Learning: Use allowed_mentions to sanitize Discord webhook content

## Problem
Discord webhook payloads that include user-generated content (e.g., PR bodies, release notes) can trigger real @mentions if the content contains `@everyone`, `@here`, `<@USER_ID>`, or `<@&ROLE_ID>`. The naive fix is sed stripping (`sed 's/@everyone//g'`), but this is incomplete (misses user/role mentions), destructive (alters content), and bypassable (Unicode lookalikes).

## Solution
Add `allowed_mentions: {parse: []}` to the webhook JSON payload. This tells Discord to render all mention syntax as plain text without resolving or pinging anyone. The three valid `parse` values are `"users"`, `"roles"`, and `"everyone"` -- an empty array suppresses all of them.

```bash
PAYLOAD=$(jq -n \
  --arg content "$MESSAGE" \
  --arg username "Bot Name" \
  --arg avatar_url "https://example.com/avatar.png" \
  '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
```

## Key Insight
Discord webhooks parse user mentions by default (not `@everyone`/`@here`, but `<@USER_ID>` resolves). Always set `allowed_mentions: {parse: []}` when forwarding untrusted content. This is API-level enforcement that cannot be bypassed by content manipulation, unlike regex stripping.

## Tags
category: security-issues
module: github-actions
