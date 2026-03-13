# Learning: Cloudflare MCP Integration via Plugin.json

## Problem

The infra-security agent used raw `curl` commands with environment variables (`$CF_API_TOKEN`, `$CF_ZONE_ID`) for all Cloudflare API operations (DNS CRUD, WAF rules, zone settings). A prior audit (PR #125, Feb 18) identified three blockers that prevented replacing curl with Cloudflare's official MCP server: (1) no DNS CRUD tools in the catalog, (2) OAuth-only auth assumed incompatible with plugin.json, and (3) the `mcp-remote` stdio bridge cannot be bundled in plugin.json. These blockers caused the integration to be deferred with a "revisit later" note.

## Solution

Cloudflare released a unified "Code Mode" MCP server at `https://mcp.cloudflare.com/mcp` that resolves all three blockers. The integration proceeded in three steps:

1. **Add the MCP server to plugin.json.** Bundle the server identically to Context7 using the HTTP transport type:

   ```json
   {
     "mcpServers": {
       "cloudflare": {
         "type": "http",
         "url": "https://mcp.cloudflare.com/mcp"
       }
     }
   }
   ```

   Claude Code handles OAuth 2.1 natively via the `/mcp` command -- users authenticate once in their browser. No pre-registered client credentials are required.

2. **Rewrite the infra-security agent.** Replace all curl-based Cloudflare API calls with MCP tool calls using two tools the unified server exposes: `search` (to find the correct API endpoint) and `execute` (to call it). The agent's `curl` command sequences become `mcp__cloudflare__search` + `mcp__cloudflare__execute` pairs.

3. **Update the stale prior learning.** The Feb 18 document (`2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`) recorded the blockers as permanent. An `[Updated 2026-02-22]` section was appended documenting that all three Cloudflare blockers are resolved and the GitHub MCP conclusion remains unchanged.

### Validation note

OAuth flows cannot be tested in-worktree because plugin changes are not live until installed. Validation relied on documentation evidence (Cloudflare's MCP server announcement and Claude Code's OAuth 2.1 support docs) rather than end-to-end execution.

## Key Insight

When a prior audit records blockers against an integration, attach a "revisit trigger" -- the specific capability gap that would unblock it. In this case, the blocker was "OAuth not supported by plugin.json," and the revisit trigger was "Cloudflare releases a server compatible with plugin.json's HTTP transport." Without a trigger, stale blockers accumulate in the knowledge base and the integration never gets retried.

For OAuth-authenticated HTTP MCP servers specifically: plugin.json's `{"type": "http", "url": "..."}` entry is sufficient. Claude Code handles the OAuth 2.1 handshake at activation time via `/mcp`. The auth burden falls on the user (one browser authentication), not on the plugin config. Any server that supports OAuth 2.1 without pre-registered client credentials can be bundled this way.

The general pattern for HTTP MCP server bundling in plugin.json is: if Context7 works, any OAuth 2.1-compatible HTTP MCP server will also work with the same config shape.

## Tags

category: integration-issues
module: infra-security-agent
symptoms: curl-based Cloudflare API calls in agent, MCP server previously blocked by OAuth incompatibility, stale learning document records blockers as permanent
