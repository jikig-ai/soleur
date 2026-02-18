# Learning: Cloudflare Official MCP Servers Do Not Cover DNS Management

## Problem

Issue #116 asked whether MCP tools could improve the infra-security agent's Cloudflare API interactions. The agent uses curl via Bash to manage DNS records and zone settings -- this was fragile during PR #108's GitHub Pages wiring. The hypothesis was that Cloudflare's official MCP server catalog could replace the curl-based approach.

## Solution

Audited all 28 agents and 37 skills for external API surfaces, then researched Cloudflare's MCP server catalog at `cloudflare/mcp-server-cloudflare`.

Three blockers prevent MCP adoption for DNS management:

1. **No DNS CRUD tools.** Cloudflare's 15 managed MCP servers cover analytics, observability, builds, browser rendering, and documentation -- but none provide DNS record create/read/update/delete or zone settings management.
2. **OAuth required.** All Cloudflare MCP servers require OAuth authentication. Plugin.json only supports unauthenticated HTTP MCP servers (like Context7).
3. **mcp-remote bridge is stdio.** The `npx mcp-remote <url>` workaround converts remote servers to stdio transport, which also cannot be bundled in plugin.json.

The infra-security agent's curl approach works when it follows the correct sequence. The autonomy gap from PR #108 is addressed by the existing learning document, not by MCP tooling.

## Key Insight

Before building or integrating MCP servers, verify three things: (1) the specific tools you need exist in the catalog, (2) the authentication model is compatible with your distribution mechanism, and (3) the transport type can be bundled. For Cloudflare, all three checks fail for DNS management. The knowledge base pattern (documenting correct sequences in learnings/) is a better solution for agent autonomy gaps than replacing working API calls with MCP wrappers.

## Tags
category: integration-issues
module: infra-security-agent
symptoms: MCP server cannot replace curl-based Cloudflare API calls
