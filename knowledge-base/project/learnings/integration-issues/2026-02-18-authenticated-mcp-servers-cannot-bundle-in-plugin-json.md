# Learning: Authenticated MCP Servers Cannot Be Bundled in Plugin.json

## Problem

Issue #116 asked whether MCP tools could improve agent interactions with external APIs. Two candidates were investigated: Cloudflare's official MCP servers (for the infra-security agent's DNS management) and GitHub's official MCP server (as a potential replacement for the `gh` CLI). The hypothesis was that official MCP servers could replace fragile curl-based or CLI-based approaches.

## Solution

Audited all 28 agents and 37 skills for external API surfaces, then researched both Cloudflare's MCP catalog (`cloudflare/mcp-server-cloudflare`) and GitHub's MCP server (`github/github-mcp-server` at `https://api.githubcopilot.com/mcp/`).

### Cloudflare MCP: Three blockers

1. **No DNS CRUD tools.** Cloudflare's 15 managed MCP servers cover analytics, observability, builds, browser rendering, and documentation -- but none provide DNS record create/read/update/delete or zone settings management.
2. **OAuth required.** All Cloudflare MCP servers require OAuth authentication. Plugin.json only supports unauthenticated HTTP MCP servers (like Context7).
3. **mcp-remote bridge is stdio.** The `npx mcp-remote <url>` workaround converts remote servers to stdio transport, which also cannot be bundled in plugin.json.

### GitHub MCP: Same auth blocker

1. **PAT required.** The GitHub MCP server requires a Personal Access Token via `Authorization: Bearer <token>` header. Plugin.json's `mcpServers` config supports `"type": "http"` and `"url"` but has no `headers` field for authentication tokens.
2. **Marginal benefit over `gh` CLI.** The `gh` CLI already provides structured JSON output (`--json`), is well-tested, handles auth via `gh auth`, and is universally available. GitHub MCP adds repos, issues, PRs, actions, and code_security tools -- but `gh` already covers all of these with lower complexity.

The infra-security agent's curl approach and other agents' `gh` CLI usage work when they follow the correct sequences. The autonomy gaps are addressed by learning documents, not by MCP tooling.

## Key Insight

Before building or integrating MCP servers, verify three things: (1) the specific tools you need exist in the catalog, (2) the authentication model is compatible with your distribution mechanism, and (3) the transport type can be bundled. Both Cloudflare and GitHub MCP servers fail check (2) -- they require authentication that plugin.json cannot express. The knowledge base pattern (documenting correct sequences in learnings/) is a better solution for agent autonomy gaps than replacing working API calls with MCP wrappers. Revisit when plugin.json gains a `headers` field for authenticated HTTP MCP servers.

## [Updated 2026-02-22] Cloudflare MCP Blockers Resolved

Cloudflare released a unified "Code Mode" MCP server at `https://mcp.cloudflare.com/mcp` (distinct from the older 15 managed servers audited above). This resolves all three Cloudflare blockers:

1. **DNS CRUD now available.** The unified server covers all ~2,500 Cloudflare API endpoints (including DNS record CRUD, zone settings, WAF, Workers, Zero Trust) through two tools: `search` and `execute`.
2. **OAuth works via plugin.json.** The server supports OAuth 2.1 without requiring pre-registered client credentials. Claude Code handles this natively via the `/mcp` command -- users authenticate once in their browser. Plugin.json can bundle the server identically to Context7: `{"type": "http", "url": "https://mcp.cloudflare.com/mcp"}`.
3. **Native HTTP transport.** The unified server is a remote HTTP endpoint. No stdio bridge needed.

The infra-security agent was rewritten in PR #254 to use MCP instead of curl for all Cloudflare API operations. The GitHub MCP conclusion remains unchanged -- `gh` CLI is still preferred.

## Tags
category: integration-issues
module: infra-security-agent
symptoms: MCP server cannot replace curl-based Cloudflare API calls, GitHub MCP requires auth header not supported by plugin.json
