---
title: "feat: Integrate Cloudflare MCP Server and Expand infra-security Agent"
type: feat
date: 2026-02-22
issue: 254
---

# feat: Integrate Cloudflare MCP Server and Expand infra-security Agent

## Overview

Bundle Cloudflare's unified MCP server in plugin.json, rewrite the infra-security agent to use MCP tools instead of curl, and expand agent capabilities to the full Cloudflare API surface. Users authenticate once via `/mcp` (OAuth 2.1).

## Problem Statement / Motivation

The infra-security agent uses manual curl commands against the Cloudflare REST API, requiring `CF_API_TOKEN` and `CF_ZONE_ID` environment variables. This approach is verbose, requires zone ID lookup, and limits the agent to hand-coded endpoints. Cloudflare's new "Code Mode" MCP server resolves all three blockers from our February 18 audit (PR #125): it covers all ~2,500 endpoints including DNS CRUD, supports OAuth 2.1 via standard MCP auth flow, and uses native HTTP transport.

## Proposed Solution

### Phase 1: Plugin Configuration and OAuth Validation

1. **Add Cloudflare MCP to plugin.json** -- Add entry to `mcpServers`:

   ```json
   "cloudflare": {
     "type": "http",
     "url": "https://mcp.cloudflare.com/mcp"
   }
   ```

   The server name `cloudflare` determines tool prefixes: `mcp__plugin_soleur_cloudflare__<tool>`.

   **File:** `plugins/soleur/.claude-plugin/plugin.json`

2. **Validate OAuth flow for plugin-bundled MCP** -- Before rewriting the agent, confirm the assumption that Claude Code handles OAuth for plugin-bundled servers:
   - Add the Cloudflare MCP entry to plugin.json
   - Run `/mcp` and verify the Cloudflare server appears and OAuth prompt works
   - Confirm tools become available after authentication
   - If this fails, fall back to documenting `claude mcp add` instructions instead

   This validation gates Phase 2. Do not start the agent rewrite until OAuth is confirmed working.

### Phase 2: Agent Rewrite and Related Updates

3. **Rewrite infra-security agent** -- Replace the entire agent body. Key changes:

   **Description field** (~60 words, projected cumulative total: ~2,495/2,500):

   ```yaml
   description: "Use this agent when you need to audit domain security posture, configure DNS records, manage WAF and security rules, deploy Workers, or configure Zero Trust policies via the Cloudflare MCP server. Uses CLI tools (dig, openssl) for verification. Use terraform-architect for IaC generation; use this agent for live Cloudflare configuration and security auditing."
   ```

   **Environment Setup section** -- Replace:
   - Remove `CF_API_TOKEN` and `CF_ZONE_ID` env var instructions
   - Add MCP authentication check: if Cloudflare MCP tools are unavailable or return auth errors, direct user to `/mcp` to authenticate
   - Add zone discovery protocol: use MCP to list zones, present disambiguation for multi-zone accounts, error on zero matches

   **Auth error handling** -- On any auth or permission error from MCP, direct the user to `/mcp` and surface the raw error message.

   **Audit Protocol section** -- Replace curl-based API checks with MCP `search()` + `execute()` pattern. CLI checks (dig, openssl, curl -sI) remain unchanged.

   **Configure Protocol section** -- Replace curl-based DNS CRUD with MCP pattern. Remove Cloudflare error code mapping (the MCP server handles error codes). Retain confirmation-before-mutation and idempotent-operation patterns.

   **Wire Recipes section** -- Replace curl calls with `execute()` in GitHub Pages recipe. Retain 10-step ordering from the learning doc and CLI-based verification.

   **Scope section** -- Remove Workers and email routing from out-of-scope. Add expanded in-scope: WAF, Workers, Zero Trust, DDoS, rate limiting. Retain inline-only output rule for security findings (extend to new capabilities).

   **File:** `plugins/soleur/agents/engineering/infra/infra-security.md`

4. **Update terraform-architect disambiguation** -- Update existing sentence from "Use infra-security for live domain auditing and DNS configuration" to "Use infra-security for live Cloudflare configuration (DNS, WAF, Workers, Zero Trust) and security auditing."

   **File:** `plugins/soleur/agents/engineering/infra/terraform-architect.md`

5. **Update stale learning** -- Add "[Updated 2026-02-22]" section explaining that Cloudflare's new "Code Mode" MCP server (distinct from the older 15 managed servers) resolves all three blockers via OAuth 2.1 + unified HTTP endpoint. Reference the working plugin.json integration.

   **File:** `knowledge-base/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`

## Technical Considerations

- **Token budget:** Current cumulative agent descriptions: 2,497 words. The rewrite must be net-zero or net-negative. Run `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w` after edits to verify under 2,500.
- **MCP tool names:** Tools appear as `mcp__plugin_soleur_cloudflare__<tool>`. The agent does NOT reference these explicitly -- it uses them naturally when available. The agent prompt describes capabilities, not tool invocation syntax.
- **OAuth scopes:** The Cloudflare MCP server's OAuth flow determines granted scopes. If a scope is insufficient, `execute()` returns a Cloudflare 403. The agent surfaces this and suggests re-authenticating via `/mcp`.
- **Security:** The inline-only output rule extends to all expanded capabilities. WAF rules, Zero Trust policies, and other sensitive config must never be written to files.

## Acceptance Criteria

- [ ] plugin.json contains Cloudflare MCP server entry alongside Context7
- [ ] OAuth validation passed for plugin-bundled Cloudflare MCP
- [ ] infra-security agent uses MCP tools for all Cloudflare API operations
- [ ] infra-security agent describes expanded capabilities in description field and body
- [ ] infra-security agent handles unauthenticated MCP state gracefully (directs to `/mcp`)
- [ ] infra-security agent discovers zones dynamically without CF_ZONE_ID
- [ ] No references to CF_API_TOKEN or CF_ZONE_ID remain in the agent
- [ ] CLI verification tools (dig, openssl, curl -sI) retained and unchanged
- [ ] GitHub Pages wiring recipe uses MCP for Cloudflare API calls
- [ ] Cumulative agent description word count under 2,500 (projected: ~2,495)

## Dependencies and Risks

- **Claude Code OAuth for plugin-bundled MCP:** The critical assumption. Validated in Phase 1 step 2. If it fails, fall back to `claude mcp add` documentation.
- **Token budget proximity:** At ~2,495/2,500 post-change, there is minimal headroom for future description expansions.

## Non-Goals

- Dual-path (MCP + curl fallback) -- full replacement only
- Renaming the agent -- keep `infra-security`
- Significant changes to terraform-architect beyond disambiguation sentence

## Version Bump

MINOR bump -- capability expansion of existing agent + new MCP server entry.

## References

- [Cloudflare Code Mode MCP Blog Post](https://blog.cloudflare.com/code-mode-mcp/)
- [Claude Code MCP Documentation](https://code.claude.com/docs/en/mcp)
- Brainstorm: `knowledge-base/brainstorms/2026-02-22-cloudflare-mcp-integration-brainstorm.md`
- Spec: `knowledge-base/specs/feat-cloudflare-mcp/spec.md`
- Current agent: `plugins/soleur/agents/engineering/infra/infra-security.md`
- Stale learning: `knowledge-base/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`
- Wiring workflow: `knowledge-base/learnings/integration-issues/2026-02-16-github-pages-cloudflare-wiring-workflow.md`
