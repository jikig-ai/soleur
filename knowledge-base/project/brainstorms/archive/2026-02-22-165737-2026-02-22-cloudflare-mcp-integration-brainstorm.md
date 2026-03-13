# Brainstorm: Cloudflare MCP Integration

**Date:** 2026-02-22
**Issue:** #254
**Status:** Complete

## What We're Building

Replace the curl-based Cloudflare REST API calls in the `infra-security` agent with Cloudflare's new unified MCP server (`https://mcp.cloudflare.com/mcp`), and expand the agent's capabilities to cover the full Cloudflare API surface.

The new Cloudflare "Code Mode" MCP server exposes ~2,500 API endpoints through just two tools (`search()` and `execute()`) in ~1,000 tokens. This resolves all three blockers identified in our February 18 MCP audit (PR #125):

1. **No DNS CRUD** -- Resolved. The unified server covers all endpoints including DNS.
2. **OAuth-only auth** -- Resolved. API token auth via Bearer header is now supported, and Claude Code supports OAuth via `/mcp`.
3. **stdio bridge needed** -- Irrelevant. The server is native HTTP.

## Why This Approach

**Full MCP replacement over dual-path:** The Cloudflare MCP server can be bundled in `plugin.json` the same way as Context7 (HTTP transport, no special config). Users authenticate once via `/mcp` (OAuth 2.1). This eliminates the need for `CF_API_TOKEN` and `CF_ZONE_ID` environment variables.

The alternative (dual-path: prefer MCP, fall back to curl) was considered but rejected because:
- It doubles the agent's complexity for a graceful degradation path
- The MCP setup is a one-time OAuth flow, not a hard gate
- The curl-based code is the main maintenance burden

**Full API surface over selective expansion:** Instead of hand-coding specific API endpoints, the 2-tool pattern (`search()` to discover endpoints, `execute()` to call them) naturally adapts to any Cloudflare service. The agent's prompt describes capabilities and when to use them; MCP handles the actual API discovery.

## Key Decisions

1. **Bundle MCP in plugin.json** -- Same pattern as Context7: `{"type": "http", "url": "https://mcp.cloudflare.com/mcp"}`
2. **Full replacement** -- Remove all curl-based Cloudflare API calls from infra-security agent
3. **OAuth authentication** -- Users run `/mcp` once to authenticate. No env vars needed.
4. **CLI tools stay** -- `dig`, `openssl`, `curl -sI` for DNS resolution, SSL inspection, and HTTP headers. These are verification tools, not Cloudflare API calls.
5. **Full Cloudflare API surface** -- The agent can use any Cloudflare API through MCP's search+execute pattern:
   - DNS record CRUD and zone management (existing)
   - SSL/TLS configuration (existing)
   - WAF and security rules (new)
   - Workers deployment (new -- previously excluded)
   - Zero Trust / Access policies (new)
   - DDoS protection and rate limiting (new)
   - Any other Cloudflare service discoverable via `search()`
6. **No CF_ZONE_ID required** -- MCP can discover zones dynamically via `search()` + `execute()`
7. **Graceful degradation** -- If MCP is not authenticated, agent reports which operations are unavailable and directs user to `/mcp`

## CTO Assessment Summary

The CTO assessed three options:
- **Option A (full replacement):** Selected. Simplest agent code, requires MCP setup.
- **Option B (dual-path):** Rejected. Preserves backward compat but doubles complexity.
- **Option C (documentation only):** Rejected. The ability to bundle MCP changes the calculus.

Key risk identified: `execute()` requires writing JavaScript to call `cloudflare.request()`, which is functionally similar to writing curl commands. The autonomy gain for simple operations is modest, but zone discovery and full API surface access are genuine improvements.

## Open Questions

1. **Agent naming:** Should `infra-security` be renamed given the expanded scope? It now covers more than infrastructure security. Possible: `cloudflare-platform`, `cloudflare-infra`, or keep existing name.
2. **terraform-architect interaction:** The terraform-architect agent covers "Hetzner and AWS." Should it be updated to reference the Cloudflare MCP for IaC scenarios?
3. **Learning docs update:** The February 18 learning (`authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`) needs updating to reflect that bundling is now viable via OAuth.

## Prior Art

- **Issue #116:** Original MCP investigation, closed by PR #125
- **PR #125:** MCP audit that identified the three blockers
- **PR #108:** GitHub Pages + Cloudflare wiring learnings (the "agent autonomy gap")
- **PR #103:** Original infra-security agent creation
- **Learning:** `knowledge-base/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`
- **Learning:** `knowledge-base/learnings/integration-issues/2026-02-16-github-pages-cloudflare-wiring-workflow.md`

## Sources

- [Cloudflare Code Mode MCP Blog Post](https://blog.cloudflare.com/code-mode-mcp/)
- [Claude Code MCP Documentation](https://code.claude.com/docs/en/mcp)
- [Cloudflare MCP GitHub Repository](https://github.com/cloudflare/mcp)
