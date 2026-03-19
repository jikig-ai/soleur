# MCP Integration Audit

**Issue:** #116
**Branch:** feat-mcp-audit
**Status:** Complete

## Problem Statement

The Soleur plugin has 28 agents and 37 skills, but only 3 MCP integrations (Context7, Playwright, Pencil). PR #108 exposed that the infra-security agent's curl-based Cloudflare API interactions are fragile and create unnecessary manual round-trips. Issue #116 asks: where else should MCP tools be used?

## Goals

- G1: Produce a prioritized list of all external API surfaces across agents and skills
- G2: Assess each surface for HTTP MCP viability (the only bundleable transport)
- G3: Identify the highest-value MCP server to build first

## Non-Goals

- NG1: Building any MCP servers (that's a follow-up plan)
- NG2: Evaluating stdio MCP opportunities (can't be bundled)
- NG3: Changing existing agent behavior

## Findings

### Functional Requirements (Audit Results)

- FR1: Cloudflare REST API is the only HIGH priority MCP opportunity
- FR2: DNS/SSL verification is MEDIUM priority (nice-to-have structured responses)
- FR3: Discord webhooks and GitHub API are LOW priority (existing tools work well)
- FR4: 20 of 28 agents have no external API dependencies at all

### Technical Requirements

- TR1: Any new MCP server must use HTTP transport (plugin.json constraint)
- TR2: Must follow patterns documented in `agent-native-architecture/references/mcp-tool-design.md`
- TR3: Should investigate existing community Cloudflare MCP servers before building custom

## External Research Findings

Investigation of Cloudflare's official MCP server catalog (`cloudflare/mcp-server-cloudflare`):

### Available Cloudflare MCP Servers

Cloudflare provides 15 managed remote MCP servers covering analytics, observability, builds, browser rendering, and documentation. All use Streamable HTTP transport with OAuth authentication.

| Server | URL | Covers DNS CRUD? |
|---|---|---|
| DNS Analytics | `https://dns-analytics.mcp.cloudflare.com/mcp` | No -- performance debugging only |
| Observability | `https://observability.mcp.cloudflare.com/mcp` | No |
| Workers Builds | `https://builds.mcp.cloudflare.com/mcp` | No |
| GraphQL | `https://graphql.mcp.cloudflare.com/mcp` | No -- analytics queries only |
| 11 others | Various | No |

### Key Blockers

1. **No DNS record management tools.** None of the 15 servers provide CRUD operations for DNS records or zone settings -- the core capability the infra-security agent needs.
2. **OAuth required.** All servers require OAuth authentication. Plugin.json only supports unauthenticated HTTP MCP servers (like Context7). There is no way to bundle OAuth-authenticated servers.
3. **`mcp-remote` bridge is stdio.** The workaround for clients without native remote MCP support (`npx mcp-remote <url>`) uses stdio transport, which also can't be bundled in plugin.json.

### Conclusion

MCP integration for Cloudflare DNS management is **not viable** with current tooling:
- The capability doesn't exist in Cloudflare's official catalog
- Even if it did, the OAuth requirement blocks auto-bundling
- Building a custom MCP server requires hosting for marginal benefit over curl

The infra-security agent's curl-based approach works when the agent follows the correct sequence. The autonomy gap from PR #108 is addressed by the learning document at `knowledge-base/learnings/integration-issues/2026-02-16-github-pages-cloudflare-wiring-workflow.md`.

### Future Triggers to Revisit

- Cloudflare adds a DNS Management MCP server to their catalog
- Claude Code plugin.json adds OAuth support for HTTP MCP servers
- A community Cloudflare DNS MCP server gains traction on npm/GitHub
