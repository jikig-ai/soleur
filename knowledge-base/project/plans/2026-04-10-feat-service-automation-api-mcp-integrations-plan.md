---
title: "feat: service automation (API + MCP integrations + guided fallback)"
type: feat
date: 2026-04-10
---

# Service Automation: API + MCP Integrations + Guided Fallback

## Overview

Implement Tiers 1 and 3 of the 3-tier service automation architecture decided in the [2026-03-23 brainstorm](../brainstorms/2026-03-23-browser-automation-cloud-platform-brainstorm.md). The agent gains the ability to provision and configure third-party services (Cloudflare, Stripe, Plausible) on behalf of founders via deterministic API calls and MCP server integrations, falling back to guided step-by-step instructions for services without API/MCP coverage.

**Scope:** Phase 3 (Make it Sticky), roadmap items 3.4 and 3.8. Secure token storage (3.5, [#1076](https://github.com/jikig-ai/soleur/issues/1076)) is already complete and provides the foundation.

**Tier 2 (Local Playwright via desktop app) is Phase 5 scope and explicitly excluded.**

## Problem Statement

Founders validated service automation as a high-value feature -- agents that both know what to configure AND do the configuration. The infrastructure exists:

- **Token storage:** 14 providers with AES-256-GCM encrypted storage, per-user HKDF key derivation, token validators, Connected Services UI (`apps/web-platform/server/byok.ts`, `server/providers.ts`, `server/token-validators.ts`)
- **Token injection:** Agent subprocess receives decrypted service tokens via `buildAgentEnv()` (`server/agent-env.ts`) with defense-in-depth allowlist
- **MCP infrastructure:** In-process MCP server pattern via `createSdkMcpServer` (`server/agent-runner.ts:493`), Cloudflare MCP bundled in `plugin.json`

What is missing is the automation layer itself: the agent cannot create a Cloudflare zone, set up a Stripe product, or configure a Plausible site. It has the tokens but no tools.

## Proposed Solution

### Architecture

Three integration tiers, implemented in two layers:

```text
                            +-------------------+
                            |  Agent Session    |
                            |  (Claude Agent    |
                            |   SDK query)      |
                            +--------+----------+
                                     |
              +----------------------+---------------------+
              |                      |                     |
    +---------v--------+   +---------v--------+  +---------v--------+
    | Tier 1a: MCP     |   | Tier 1b: API     |  | Tier 3: Guided   |
    | (Cloudflare,     |   | (REST wrappers   |  | Instructions     |
    | Stripe via       |   |  via in-process  |  | (deep links +    |
    | plugin.json +    |   |  MCP tools)      |  |  review gates)   |
    | remote servers)  |   |                  |  |                  |
    +------------------+   +------------------+  +------------------+
              |                      |                     |
    +---------v--------+   +---------v--------+  +---------v--------+
    | mcp.cloudflare   |   | Service APIs     |  | Agent generates  |
    | .com/mcp         |   | (Plausible,      |  | markdown steps   |
    | mcp.stripe.com   |   |  other REST-only |  | with deep links  |
    +------------------+   |  services)       |  +------------------+
                           +------------------+
```

**Tier 1a -- Remote MCP servers:** Services with official MCP servers (Cloudflare, Stripe) are accessible through the agent's plugin system. Cloudflare MCP is already bundled. Stripe MCP (`https://mcp.stripe.com`) needs to be added. Authentication flows through OAuth (Cloudflare, Stripe) handled natively by Claude Code.

**Tier 1b -- In-process API tools:** For services with REST APIs but no MCP server (Plausible, and future services), expose service operations as in-process MCP tools via `createSdkMcpServer` -- the same pattern used for `create_pull_request`. The tools make authenticated API calls using the user's stored tokens (decrypted at session start).

**Tier 3 -- Guided instructions:** For services without API or MCP coverage, or when the user lacks a stored token, the agent generates step-by-step instructions with deep links to the service's configuration pages and review gates (using the existing `AskUserQuestion`-style pause pattern from ops-provisioner).

### Key Design Decisions

1. **MCP-first for services that publish MCP servers.** Cloudflare and Stripe both have official MCP servers. Using these is preferred over custom API wrappers because the vendor maintains compatibility, and the agent gets the full API surface without us wrapping every endpoint.

2. **In-process MCP tools for REST-only services.** Plausible has a REST API but no MCP server. Rather than building a custom MCP server, expose a small set of provisioning tools (create site, add goal, get stats) as in-process MCP tools within the existing `soleur_platform` server. This follows the `create_pull_request` pattern.

3. **Token presence drives tier selection.** If the user has a stored token for a service, the agent uses API/MCP automation. If not, it falls back to guided instructions that walk the user through creating an account and generating a token.

4. **No new database tables.** The existing `api_keys` table and provider configuration are sufficient. Service automation metadata (which services are provisioned, what resources were created) lives in the user's knowledge base, not in our database.

5. **Cloudflare MCP authentication is OAuth, not token-based.** The Cloudflare MCP server at `mcp.cloudflare.com/mcp` uses OAuth 2.1 -- Claude Code handles the handshake. The user's stored Cloudflare API token (in `api_keys`) is separate and used for direct API calls when MCP tools are unavailable. Same for Stripe.

## Technical Approach

### Phase 1: Stripe MCP Integration

**Effort:** Small -- configuration only, no code.

Add Stripe's official MCP server to `plugin.json`:

```json
{
  "mcpServers": {
    "stripe": {
      "type": "http",
      "url": "https://mcp.stripe.com"
    }
  }
}
```

This follows the identical pattern used for Cloudflare and Vercel MCP servers already in `plugin.json`. Authentication is OAuth -- Claude Code handles it natively.

**Files changed:**

- `plugins/soleur/.claude-plugin/plugin.json` -- add Stripe MCP entry

### Phase 2: Plausible In-Process MCP Tools

**Effort:** Medium -- new tools in agent-runner.

Add Plausible provisioning tools to the in-process MCP server (`soleur_platform`). Three tools:

1. **`plausible_create_site`** -- Create a new site in Plausible Analytics
   - Input: `domain` (string)
   - Uses: Plausible Sites API (`POST /api/v1/sites`)
   - Auth: User's stored `PLAUSIBLE_API_KEY` from `serviceTokens`

2. **`plausible_add_goal`** -- Add a conversion goal to an existing site
   - Input: `site_id` (string), `goal_type` ("event" | "page"), `value` (string)
   - Uses: Plausible Goals API (`PUT /api/v1/sites/goals`)

3. **`plausible_get_stats`** -- Get current stats for a site (verification tool)
   - Input: `site_id` (string), `period` ("day" | "7d" | "30d")
   - Uses: Plausible Stats API (`GET /api/v1/stats/aggregate`)

**Implementation pattern:** Follow the `create_pull_request` tool pattern in `agent-runner.ts:464-491`. Each tool:

- Validates inputs with zod schemas
- Retrieves the Plausible API key from the service tokens map (passed to `buildAgentEnv`)
- Makes authenticated REST API calls using `fetch`
- Returns structured JSON results
- Handles errors gracefully (API errors, missing token, timeout)

**Files changed:**

- `apps/web-platform/server/agent-runner.ts` -- add Plausible tools to MCP server
- `apps/web-platform/server/service-tools.ts` (new) -- extract service tool definitions for maintainability
- `apps/web-platform/test/service-tools.test.ts` (new) -- unit tests

**Token availability check:** Before registering Plausible tools, check if the user has a valid Plausible API key in their stored tokens. If not, skip tool registration -- the agent falls back to guided instructions naturally.

### Phase 3: Service Automation Agent Prompt

**Effort:** Medium -- new agent + system prompt engineering.

Create a service automation agent that the domain leaders can delegate to. The agent understands:

1. Which services the user has connected (from `api_keys` table, exposed via existing GET `/api/services`)
2. Which tier to use for each service (MCP available? API tool available? Guided fallback?)
3. The ops-provisioner's 3-phase pattern (Setup, Configure, Verify)

**Agent prompt includes:**

- Connected services context (injected from the user's service list at session start)
- Per-service provisioning playbooks (what to create, how to verify)
- Tier selection logic: MCP tools > in-process API tools > guided instructions
- Review gate protocol for manual steps

**Files changed:**

- `plugins/soleur/agents/operations/service-automator.md` (new) -- service automation agent
- `apps/web-platform/server/agent-runner.ts` -- inject connected services context into system prompt

### Phase 4: Guided Instructions Fallback

**Effort:** Medium -- prompt engineering + UX.

For services without API/MCP coverage, or when the user hasn't connected a service token:

1. **Deep link generation:** Agent generates URLs pointing directly to the service's configuration page (e.g., `https://dash.cloudflare.com/?to=/:account/domains/register` for domain registration)

2. **Review gates:** The agent pauses at each manual step and waits for user confirmation before proceeding. This uses the existing WebSocket message flow -- the agent sends a message asking the user to confirm, and the conversation continues when they respond.

3. **Post-completion token capture:** After the user completes manual setup, the agent prompts them to generate an API token and store it via the Connected Services page, enabling future automation.

**Provisioning playbooks for guided mode:**

| Service | Deep Link | Steps |
|---------|-----------|-------|
| Cloudflare | `https://dash.cloudflare.com/sign-up` | Create account, add site, change nameservers, generate API token |
| Stripe | `https://dashboard.stripe.com/register` | Create account, activate payments, generate restricted API key |
| Plausible | `https://plausible.io/register` | Create account, add site, install script tag, generate API key |

**Files changed:**

- `plugins/soleur/agents/operations/service-automator.md` -- add guided instruction playbooks
- Agent prompt references for deep links and step sequences

### Phase 5: Integration Testing

**Effort:** Medium.

1. **Unit tests** for Plausible API tool wrappers (mock API responses)
2. **Integration tests** for token retrieval + tool registration flow
3. **E2E test scenario:** Agent session with connected Cloudflare token verifies MCP tools are available
4. **Guided fallback test:** Agent session without tokens verifies fallback to instructions

**Files changed:**

- `apps/web-platform/test/service-tools.test.ts` (new)
- `apps/web-platform/test/agent-runner-tools.test.ts` -- extend existing tool tests

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| **Custom MCP servers per service** | Over-engineering. Cloudflare and Stripe already publish official MCP servers. For REST-only services, in-process tools are simpler than running a separate server process. |
| **Server-side Playwright** | Permanently rejected (HIGH risk from CTO, CLO, CFO). See brainstorm. |
| **Terraform for all provisioning** | Terraform is for infrastructure (servers, DNS). Service account creation (Stripe accounts, Plausible sites) is not infrastructure -- it is SaaS configuration. Wrong tool. |
| **Agent-browser CLI for web automation** | Desktop-only (Tier 2, Phase 5). Not available on the cloud platform. |
| **Separate microservice for API calls** | Unnecessary complexity. In-process tools via the existing MCP server pattern keep the codebase simple and avoid network hops. |

## Domain Review

**Domains relevant:** Engineering, Legal, Finance, Marketing, Operations

### Engineering (CTO) -- brainstorm carry-forward

**Status:** reviewed
**Assessment:** Server-side Playwright is HIGH risk (RAM, SSRF, sandbox conflicts). API-first eliminates all three concerns. Desktop native app for local Playwright is architecturally sound. The in-process MCP tool pattern (`createSdkMcpServer`) is proven by `create_pull_request` and extends naturally to service tools. No architectural risk in this plan.

### Legal (CLO) -- brainstorm carry-forward

**Status:** reviewed
**Assessment:** API-first with user-provided tokens eliminates undisclosed agency liability. User explicitly authorizes each service connection via the Connected Services page. No third-party ToS violations when using official APIs/MCP servers as intended. Guided instructions are informational only -- no legal exposure. No new PII categories introduced (service tokens already covered by existing privacy policy update in P2).

### Finance (CFO) -- brainstorm carry-forward

**Status:** reviewed
**Assessment:** API-first has near-zero marginal cost. MCP server calls are free (vendor-hosted). Plausible Sites API may require Enterprise plan ($9/month currently tracked in expenses). No infrastructure cost increase. The 2-4x infra cost risk from server-side Playwright remains fully eliminated.

### Marketing (CMO) -- brainstorm carry-forward

**Status:** reviewed
**Assessment:** Service automation as a chat-driven experience is a compelling differentiator. "Your AI organization provisions your infrastructure" is strong messaging for founder recruitment (P4). No immediate marketing action required -- this is infrastructure that enables the value proposition.

### Operations (COO)

**Status:** reviewed
**Assessment:** This feature adds API integrations with three external services (Cloudflare, Stripe, Plausible). All three are already tracked in the expense ledger and have DPAs in place (verified during P1 vendor review, #670). No new vendor onboarding required. The Plausible Sites API may require an Enterprise plan upgrade -- verify current plan tier before implementation. Operational concern: token validation health should be monitored -- a batch of expired tokens could degrade the guided fallback experience for multiple users simultaneously.

## Acceptance Criteria

### Functional Requirements

- [ ] Agent can provision Cloudflare zones via MCP tools (Cloudflare MCP server accessible)
- [ ] Agent can create Stripe products/prices via MCP tools (Stripe MCP server accessible)
- [ ] Agent can create Plausible sites and goals via in-process API tools
- [ ] Agent falls back to guided instructions when no token is stored for a service
- [ ] Guided instructions include deep links to service configuration pages
- [ ] Review gates pause the agent at each manual step in guided mode
- [ ] After guided setup, agent prompts user to store their new API token
- [ ] Service tokens from Connected Services are available to automation tools
- [ ] Plausible API tools validate inputs and handle errors gracefully (timeout, auth failure, API errors)

### Non-Functional Requirements

- [ ] No new database tables or migrations required (uses existing `api_keys`)
- [ ] Plausible API calls timeout after 5 seconds (match existing `VALIDATION_TIMEOUT_MS`)
- [ ] Service tool errors are logged but never expose tokens in logs or error messages
- [ ] In-process MCP tools follow the `create_pull_request` security pattern (input validation, error containment)
- [ ] Agent environment isolation maintained -- service tokens only injected via `buildAgentEnv` allowlist

### Quality Gates

- [ ] Unit tests for all Plausible API tool wrappers
- [ ] Integration test for token retrieval + tool registration flow
- [ ] TypeScript strict mode passes
- [ ] No new `any` types introduced
- [ ] Markdownlint passes on all changed `.md` files

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a user with a stored Cloudflare API token, when the agent is asked to "create a DNS zone for example.com", then the Cloudflare MCP tools are available and the agent can invoke them
- Given a user with a stored Stripe secret key, when the agent is asked to "set up payments", then the Stripe MCP tools are available and the agent can invoke them
- Given a user with a stored Plausible API key, when the agent is asked to "add analytics to my site", then the in-process `plausible_create_site` tool is available and creates a site via the API
- Given a user without any stored Plausible token, when the agent is asked to "set up analytics", then the agent provides step-by-step guided instructions with a deep link to `https://plausible.io/register`
- Given a Plausible API call that returns 401, when `plausible_create_site` is invoked, then the tool returns an error result (not a crash) and the agent suggests re-validating the token

### Edge Cases

- Given a user whose Plausible API key has expired, when the agent tries to create a site, then the tool returns a clear "token invalid" error and the agent suggests reconnecting via the Connected Services page
- Given a Plausible API timeout (>5s), when `plausible_create_site` is invoked, then the tool returns a timeout error without leaving orphaned resources
- Given the Cloudflare MCP server is unreachable, when the agent tries to provision DNS, then the agent falls back to guided instructions rather than failing silently

### Integration Verification (for `/soleur:qa`)

- **API verify:** `curl -s -H "Authorization: Bearer <PLAUSIBLE_KEY>" "https://plausible.io/api/v1/sites" | jq '.data | length'` expects a number >= 0
- **Browser:** Navigate to `https://app.soleur.ai/dashboard/settings/services`, verify Cloudflare and Plausible show as connected
- **Cleanup:** `curl -s -X DELETE -H "Authorization: Bearer <PLAUSIBLE_KEY>" "https://plausible.io/api/v1/sites/test-site.example.com"` to remove test sites

## Success Metrics

- Founders can provision Cloudflare, Stripe, and Plausible services without leaving the chat interface
- Guided fallback successfully walks users through service setup for at least 3 services
- Zero token exposure in logs or error messages (verified by grep audit)

## Dependencies and Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| Secure token storage (#1076) | Done | Connected Services UI, encryption, token validation |
| Agent subprocess token injection | Done | `buildAgentEnv()` in `server/agent-env.ts` |
| In-process MCP server pattern | Done | `create_pull_request` tool in `agent-runner.ts` |
| Cloudflare MCP in plugin.json | Done | `mcp.cloudflare.com/mcp` already bundled |
| Stripe MCP server availability | Available | `https://mcp.stripe.com` with OAuth |
| Plausible Sites API | Available | REST API with bearer token auth |
| Review gate notifications (#1049) | Not started | Enhances guided fallback but not a blocker -- basic WebSocket messages work |

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Plausible Sites API requires Enterprise plan | Medium | High -- tools register but fail for free-tier users | Check plan tier in tool implementation, provide clear error message |
| Cloudflare/Stripe MCP OAuth requires user interaction | Low | Low -- expected behavior | Document in guided instructions that first use requires OAuth consent |
| MCP server rate limiting | Low | Medium | Implement retry with backoff in tool wrappers |
| Token rotation invalidates stored tokens | Medium | Low | Existing token validation catches this; agent suggests reconnecting |
| Plausible API v1 deprecation (#1360) | Low | Medium | Track via existing issue; migration path is straightforward |

## Future Considerations

- **Phase 5:** Desktop native app (Electron/Tauri) adds Tier 2 local Playwright for services without APIs
- **Additional providers:** Resend (email), Buttondown (newsletter), Hetzner (servers) can follow the same in-process tool pattern
- **Service health monitoring:** Periodic token re-validation via scheduled workflow
- **Provisioning history:** Track which resources were created per service (currently lives in KB, could move to a dedicated table)

## References and Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-23-browser-automation-cloud-platform-brainstorm.md`
- Token storage: `apps/web-platform/server/byok.ts` (encryption), `server/providers.ts` (config), `server/token-validators.ts` (validation)
- Agent env isolation: `apps/web-platform/server/agent-env.ts:42` (`buildAgentEnv`)
- MCP tool pattern: `apps/web-platform/server/agent-runner.ts:464-501` (`create_pull_request`)
- Connected Services UI: `apps/web-platform/components/settings/connected-services-content.tsx`
- Cloudflare MCP learning: `knowledge-base/project/learnings/integration-issues/2026-02-22-cloudflare-mcp-plugin-json-integration.md`
- OAuth MCP learning: `knowledge-base/project/learnings/integration-issues/2026-02-22-oauth-mcp-servers-can-bundle-in-plugin-json.md`
- Plausible API learning: `knowledge-base/project/learnings/2026-04-02-plausible-api-response-validation-prevention.md`

### External References

- [Cloudflare MCP Server](https://mcp.cloudflare.com/mcp) -- OAuth 2.1, full API surface via search+execute tools
- [Stripe Agent Toolkit](https://github.com/stripe/agent-toolkit) -- MCP at `https://mcp.stripe.com`, OAuth auth
- [Plausible Sites API](https://plausible.io/docs/sites-api) -- REST, bearer token auth, Enterprise plan required
- [Plausible Stats API](https://plausible.io/docs/stats-api) -- REST, bearer token auth

### Related Issues

- [#1050](https://github.com/jikig-ai/soleur/issues/1050) -- This issue (service automation)
- [#1076](https://github.com/jikig-ai/soleur/issues/1076) -- Secure token storage (CLOSED)
- [#1077](https://github.com/jikig-ai/soleur/issues/1077) -- Guided instructions fallback
- [#1360](https://github.com/jikig-ai/soleur/issues/1360) -- Plausible Stats API v1 to v2 migration (deferred)
