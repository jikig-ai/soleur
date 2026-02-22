# Spec: Cloudflare MCP Integration

**Issue:** #254
**Date:** 2026-02-22
**Brainstorm:** `knowledge-base/brainstorms/2026-02-22-cloudflare-mcp-integration-brainstorm.md`

## Problem Statement

The `infra-security` agent uses manual curl commands to interact with the Cloudflare REST API, requiring users to set `CF_API_TOKEN` and `CF_ZONE_ID` environment variables. This approach is verbose, requires zone ID lookup, and limits the agent to hand-coded API endpoints (DNS CRUD, SSL settings). Cloudflare's new unified MCP server resolves all three blockers identified in our February 18 audit (PR #125) and can be bundled in plugin.json.

## Goals

- G1: Bundle Cloudflare MCP server in plugin.json for automatic availability
- G2: Replace all curl-based Cloudflare API calls with MCP search()/execute() tools
- G3: Expand agent capabilities to the full Cloudflare API surface (WAF, Workers, Zero Trust, DDoS, etc.)
- G4: Eliminate CF_API_TOKEN and CF_ZONE_ID environment variable requirements
- G5: Maintain CLI verification tools (dig, openssl, curl -sI) unchanged

## Non-Goals

- NG1: Dual-path implementation (MCP + curl fallback)
- NG2: Renaming the infra-security agent (deferred -- address in follow-up if needed)
- NG3: Significant changes to terraform-architect beyond disambiguation sentence (deferred)

## Functional Requirements

- FR1: Plugin.json mcpServers section includes Cloudflare MCP server configuration
- FR2: infra-security agent prompt uses MCP search()/execute() instead of curl for all Cloudflare API operations
- FR3: Agent describes expanded capabilities: DNS, SSL/TLS, WAF, Workers, Zero Trust, DDoS, rate limiting
- FR4: Agent gracefully handles unauthenticated state -- directs user to `/mcp` for OAuth setup
- FR5: Agent discovers zones dynamically via MCP (no pre-set CF_ZONE_ID)
- FR6: GitHub Pages wiring recipe updated to use MCP tools
- FR7: Agent retains all CLI verification tools (dig, openssl, curl -sI for headers)

## Technical Requirements

- TR1: plugin.json mcpServers entry: `{"type": "http", "url": "https://mcp.cloudflare.com/mcp"}`
- TR2: Remove references to CF_API_TOKEN and CF_ZONE_ID from agent prompt
- TR3: Update learning document `authenticated-mcp-servers-cannot-bundle-in-plugin-json.md` to reflect new viability
- TR4: Version bump (MINOR -- new capability expansion)
- TR5: Update plugin.json description to reflect Cloudflare MCP integration
