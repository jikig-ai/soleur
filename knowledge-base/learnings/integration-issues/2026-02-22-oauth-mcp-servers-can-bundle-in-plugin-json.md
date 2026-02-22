# Learning: OAuth MCP Servers Can Bundle in Plugin.json

## Problem

Issue #116 concluded that MCP servers requiring authentication cannot be bundled in `plugin.json` because the configuration only supports unauthenticated HTTP endpoints -- plugin.json has no `headers` field for auth tokens. The implicit assumption was that any authenticated MCP server was ineligible for bundling.

## Solution

The Vercel MCP integration (issue #258) revealed this conclusion was too narrow. Vercel's MCP server requires OAuth authentication, yet it bundles in `plugin.json` using the same `type: http` pattern as unauthenticated servers:

```json
"vercel": {
  "type": "http",
  "url": "https://mcp.vercel.com"
}
```

The key distinction: Vercel MCP uses OAuth flow, not token-based authentication. Claude Code handles the OAuth flow natively on first tool use -- no headers needed in plugin.json.

## Key Insight

The prior audit conflated two authentication patterns:

1. **Header-based auth (token/PAT)** -- Plugin.json cannot express headers, so servers requiring static auth tokens (Cloudflare, GitHub) remain unbundleable.
2. **OAuth-based auth** -- Plugin.json doesn't need to express auth. OAuth orchestration is Claude Code's responsibility. Any MCP server using standard OAuth flow can bundle as `type: http`.

Before concluding an authenticated MCP server cannot bundle, verify its auth model:
- OAuth (browser-based interactive flow) -- bundleable via `type: http`
- Static headers (API keys, PATs, bearer tokens) -- not bundleable until plugin.json adds header support

## Tags

category: integration-issues
module: plugin-architecture
related-issues: #116, #258
