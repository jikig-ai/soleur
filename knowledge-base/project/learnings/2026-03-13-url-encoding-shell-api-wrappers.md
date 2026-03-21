# Learning: URL-encode special characters in shell API wrapper URLs

## Problem

`hn-community.sh mentions` returned HTTP 400 from the HN Algolia API. The URL was constructed with literal parentheses `(story,comment)` in the `tags` parameter and a literal `>` in the `numericFilters` parameter. These characters are not valid unencoded in URL query strings.

```bash
# Broken — literal special characters
local url="${HN_API}/search_by_date?query=${encoded_query}&tags=(story,comment)&numericFilters=created_at_i>${since}&hitsPerPage=${limit}"
```

## Solution

Replace literal special characters with percent-encoded equivalents in the URL template:

```bash
# Fixed — percent-encoded special characters
local url="${HN_API}/search_by_date?query=${encoded_query}&tags=%28story%2Ccomment%29&numericFilters=created_at_i%3E${since}&hitsPerPage=${limit}"
```

Key mappings: `(` → `%28`, `)` → `%29`, `,` → `%2C`, `>` → `%3E`.

## Key Insight

When constructing API URLs in bash, dynamic values (user input) get URL-encoded via `python3 urllib.parse.quote` or `curl --data-urlencode`, but **static API syntax characters** embedded in query parameters are easy to miss. The `query=` value was correctly encoded, but `tags=` and `numericFilters=` had hardcoded special characters that also needed encoding. A smoke test that exercises every subcommand catches this immediately — the script's own JSON validation layer (`jq empty`) doesn't help when the server returns HTML error pages.

## Session Errors

1. HN Algolia API HTTP 400 from unencoded URL — fixed with percent-encoding
2. Worktree manager failed on bare repo — used `git worktree add` directly
3. Accidental commit on main due to CWD confusion — reset and recommitted in worktree
4. Worktree stuck on main branch after reset — fixed with `git switch`
5. Edit tool "file modified since read" — re-read file before editing
6. String not found in community-manager.md — re-read to find actual content

## Tags

category: integration-issues
module: community-scripts
