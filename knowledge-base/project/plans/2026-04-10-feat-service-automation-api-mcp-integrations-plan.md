---
title: "feat: service automation (API + MCP integrations + guided fallback)"
type: feat
date: 2026-04-10
deepened: 2026-04-10
---

# Service Automation: API + MCP Integrations + Guided Fallback

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 8
**Research sources:** Claude Agent SDK docs (Context7), Stripe Agent Toolkit docs (Context7), Plausible API docs, 6 institutional learnings, MCP tool design reference, canUseTool security audit

### Critical Findings

1. **canUseTool deny-by-default blocks plugin MCP tools.** The current `canUseTool` in `agent-runner.ts:664` denies all unrecognized tools. Plugin MCP tools (Cloudflare, Stripe from `plugin.json`) would be blocked because they are not in `platformToolNames`. A new Phase 0 must add plugin MCP tools to the allowlist before any MCP integration works.
2. **Stripe MCP has two transports with different auth.** The remote server (`mcp.stripe.com`) uses OAuth. The stdio transport (`npx @stripe/mcp --api-key=KEY`) uses the user's API key directly. For the cloud platform where users store API keys, the stdio transport with injected keys is more reliable than requiring separate OAuth consent.
3. **Plausible Sites API may require Enterprise plan.** The site provisioning API (`POST /api/v1/sites`) is documented as "available on Enterprise plans." Must verify current plan tier before implementation.
4. **Plausible API requires JSON response validation.** Learning `2026-04-02` documents that Plausible can return non-JSON responses (HTML/text error pages) with 2xx status codes. All API tools must validate response body structure before parsing.

### New Considerations Discovered

- MCP tool names must follow the `mcp__<server>__<tool>` convention and be explicitly added to `platformToolNames` for `canUseTool` allowlisting
- Service tools should be extracted into a separate module (`service-tools.ts`) for testability -- MCP adapter files with heavy imports cannot be directly imported in tests (learning: `mcp-adapter-pure-function-extraction-testability`)
- Plausible Goals API uses PUT with upsert semantics (find-or-create), making provisioning scripts safely idempotent (learning: `plausible-goals-api-provisioning-hardening`)
- Tools should be primitives, not workflows -- the agent decides orchestration (MCP tool design reference)

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

### Research Insights: Architecture

**canUseTool authorization gap (Critical -- must be Phase 0):**

The current `canUseTool` in `agent-runner.ts` has a deny-by-default policy at line 664. Plugin MCP tools loaded via `plugin.json` (Cloudflare, Stripe, Vercel, Context7) produce tool names like `mcp__plugin_soleur_cloudflare__execute`. These are NOT in `platformToolNames` (which only contains `mcp__soleur_platform__create_pull_request`). They would be **blocked**.

Per the Claude Agent SDK documentation (Context7), the `allowedTools` option must explicitly list MCP tool names or use wildcards (`mcp__servername__*`). The current code only sets `allowedTools` when `platformToolNames` is non-empty (line 529). Plugin MCP tools need either:

1. Wildcard entries in `allowedTools` for each plugin MCP server, OR
2. Plugin MCP tool names added to `platformToolNames`, OR
3. A separate check in `canUseTool` that allows plugin MCP tools by prefix -- BUT the learning `2026-04-06-mcp-tool-canusertool-scope-allowlist.md` explicitly warns against blanket prefix allows. Use an explicit allowlist of plugin server names instead.

**Recommended approach:** Build a `pluginMcpToolNames` array from the plugin's `plugin.json` MCP server names (e.g., `["mcp__plugin_soleur_cloudflare__*", "mcp__plugin_soleur_stripe__*"]`) and merge into `allowedTools`. This is explicit (no blanket `mcp__` prefix) while covering all tools from authorized plugin servers.

**Stripe MCP transport choice:**

The Stripe Agent Toolkit offers two transports:

| Transport | Auth | Pros | Cons |
|-----------|------|------|------|
| Remote HTTP (`mcp.stripe.com`) | OAuth 2.1 | Zero config in plugin.json | User must OAuth separately from stored API key; double auth confusion |
| Stdio (`npx @stripe/mcp --api-key=KEY`) | API key | Uses stored token directly; no OAuth | Spawns subprocess; needs `npx` in container |

For the cloud platform, the remote HTTP transport via plugin.json is simpler (no subprocess management) and follows the existing Cloudflare pattern. The OAuth consent is a one-time cost. The user's stored Stripe key in Connected Services is separate and serves a different purpose (direct API calls from service tools, not MCP).

**Decision: Use remote HTTP via plugin.json.** If OAuth friction proves too high in user testing, fall back to stdio transport with injected API key as Phase 3+ enhancement.

### Key Design Decisions

1. **MCP-first for services that publish MCP servers.** Cloudflare and Stripe both have official MCP servers. Using these is preferred over custom API wrappers because the vendor maintains compatibility, and the agent gets the full API surface without us wrapping every endpoint.

2. **In-process MCP tools for REST-only services.** Plausible has a REST API but no MCP server. Rather than building a custom MCP server, expose a small set of provisioning tools (create site, add goal, get stats) as in-process MCP tools within the existing `soleur_platform` server. This follows the `create_pull_request` pattern.

3. **Token presence drives tier selection.** If the user has a stored token for a service, the agent uses API/MCP automation. If not, it falls back to guided instructions that walk the user through creating an account and generating a token.

4. **No new database tables.** The existing `api_keys` table and provider configuration are sufficient. Service automation metadata (which services are provisioned, what resources were created) lives in the user's knowledge base, not in our database.

5. **Cloudflare MCP authentication is OAuth, not token-based.** The Cloudflare MCP server at `mcp.cloudflare.com/mcp` uses OAuth 2.1 -- Claude Code handles the handshake. The user's stored Cloudflare API token (in `api_keys`) is separate and used for direct API calls when MCP tools are unavailable. Same for Stripe.

## Technical Approach

### Phase 0: canUseTool Plugin MCP Authorization (Prerequisite)

**Effort:** Small -- but blocks everything else.

The current `canUseTool` deny-by-default policy blocks ALL plugin MCP tools. Before any MCP integration works, the allowlist must be extended.

**Implementation:**

1. Read the plugin's `plugin.json` to extract MCP server names at agent-runner startup
2. Build a `pluginMcpAllowPatterns` set from the server names (e.g., `cloudflare`, `stripe`, `vercel`, `context7`)
3. In `canUseTool`, add a check before the deny-by-default block:

```typescript
// Allow plugin MCP tools from servers registered in plugin.json.
// Uses explicit server-name matching (not blanket mcp__ prefix).
// See learning: 2026-04-06-mcp-tool-canusertool-scope-allowlist.md
if (toolName.startsWith("mcp__plugin_soleur_") && pluginMcpServerNames.some(
  (server) => toolName.startsWith(`mcp__plugin_soleur_${server}__`)
)) {
  log.info({ sec: true, toolName, agentId: options.agentID }, "Plugin MCP tool invoked");
  return { behavior: "allow" as const };
}
```

4. Add the plugin MCP tool patterns to `allowedTools` so the SDK knows to offer them:

```typescript
// Merge plugin MCP tools into allowedTools
const pluginMcpPatterns = pluginMcpServerNames.map(
  (name) => `mcp__plugin_soleur_${name}__*`
);
const allAllowedTools = [...platformToolNames, ...pluginMcpPatterns];
```

**Files changed:**

- `apps/web-platform/server/agent-runner.ts` -- add plugin MCP allowlist
- `apps/web-platform/test/agent-runner-tools.test.ts` -- test plugin MCP tools allowed, unregistered MCP tools denied

**Security note:** The allowlist is derived from the plugin's own `plugin.json`, not from user input. The plugin is a trusted local file installed at deployment time. This maintains the explicit-allowlist principle while avoiding hardcoded tool names.

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

### Research Insights: Stripe MCP

**Available tools (from Stripe Agent Toolkit docs):**

The Stripe MCP server exposes tools scoped by Stripe resource, with fine-grained control. Common tools include:

- `customers.create`, `customers.read` -- customer management
- `products.create`, `prices.create` -- product catalog
- `paymentLinks.create` -- payment link generation
- `invoices.create` -- invoice management

The remote server at `mcp.stripe.com` uses OAuth 2.1. The user authenticates once in their browser and the session persists. Claude Code handles the handshake natively -- no token headers needed in plugin.json.

**Edge case: OAuth vs stored API key separation.** The user may have a Stripe secret key stored in Connected Services AND an OAuth session with `mcp.stripe.com`. These are independent auth channels. The stored key is used by in-process tools (if any future Stripe-specific tools are added). The OAuth session is used by the remote MCP server. Document this in the agent prompt to avoid confusion.

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

### Research Insights: Plausible API

**Exact API endpoints (verified from Plausible docs):**

| Tool | Method | Endpoint | Request Body |
|------|--------|----------|-------------|
| `plausible_create_site` | `POST` | `/api/v1/sites` | `{ "domain": "example.com", "timezone": "UTC" }` |
| `plausible_list_sites` | `GET` | `/api/v1/sites` | -- |
| `plausible_delete_site` | `DELETE` | `/api/v1/sites/:site_id` | -- |
| `plausible_add_goal` | `PUT` | `/api/v1/sites/goals` | `{ "site_id": "example.com", "goal_type": "event", "event_name": "Signup" }` |
| `plausible_get_stats` | `GET` | `/api/v1/stats/aggregate` | query params: `site_id`, `period`, `metrics` |

**Headers:** All endpoints require `Authorization: Bearer <TOKEN>` and `Content-Type: application/json`.

**Institutional learnings that apply:**

1. **JSON response validation (learning: 2026-04-02).** Plausible can return non-JSON responses (plain-text "402 Payment Required") with 2xx status codes. All tools must validate response body with `JSON.parse()` in a try/catch before processing. Never assume `res.ok` means valid JSON.

2. **Goals API uses PUT with upsert semantics (learning: 2026-03-13).** The PUT endpoint is safely idempotent (find-or-create). Running `plausible_add_goal` twice with the same parameters does not create duplicates. This simplifies error recovery -- if a goal creation times out, retrying is safe.

3. **HTTPS validation (learning: 2026-03-13).** Validate that the base URL uses HTTPS before transmitting the bearer token. Reject non-HTTPS URLs to prevent token leakage.

4. **Site ID format validation (learning: 2026-03-13).** Restrict `site_id` to `[a-zA-Z0-9._-]+` to prevent injection in URL construction. This is especially important since `site_id` is user-provided and interpolated into the URL path.

5. **Pure function extraction (learning: mcp-adapter-pure-function-extraction).** Extract API call logic into standalone pure functions in `service-tools.ts` with zero SDK dependencies. The MCP tool handler in `agent-runner.ts` delegates to these functions. This enables unit testing without importing the MCP SDK.

**Implementation code pattern:**

```typescript
// service-tools.ts -- pure functions, zero SDK dependencies
const PLAUSIBLE_BASE = "https://plausible.io";
const PLAUSIBLE_TIMEOUT_MS = 5_000;

export interface PlausibleResult {
  success: boolean;
  data?: unknown;
  error?: string;
}

export async function plausibleCreateSite(
  apiKey: string,
  domain: string,
  timezone = "UTC",
): Promise<PlausibleResult> {
  // Validate domain format
  if (!/^[a-zA-Z0-9._-]+$/.test(domain)) {
    return { success: false, error: "Invalid domain format" };
  }

  const res = await fetch(`${PLAUSIBLE_BASE}/api/v1/sites`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ domain, timezone }),
    signal: AbortSignal.timeout(PLAUSIBLE_TIMEOUT_MS),
  });

  // Validate JSON response body (learning: 2026-04-02)
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { success: false, error: `Non-JSON response (HTTP ${res.status})` };
  }

  if (!res.ok) {
    return { success: false, error: `API error (HTTP ${res.status})` };
  }

  return { success: true, data: body };
}
```

**Tool design principle (from MCP tool design reference):** Tools should be primitives, not workflows. Each tool does one thing (create site, add goal, get stats). The agent decides the orchestration sequence based on the user's request. Do not bundle "create site + add goals + verify" into a single workflow tool.

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

### Research Insights: Agent Design

**Agent description budget:** The agent description must stay under ~30 words for routing (constitution rule). The body contains the full provisioning playbooks. Disambiguation sentence: "Use ops-provisioner for manual SaaS setup via browser; use service-automator for API/MCP-driven service provisioning."

**Connected services context injection:** The agent system prompt should include a structured list of which services the user has connected. This enables tier selection without an API call during the conversation:

```text
## Connected Services
- cloudflare: connected (validated 2026-04-08)
- stripe: connected (validated 2026-04-05)
- plausible: not connected
- hetzner: connected (validated 2026-04-01)
```

This context is constructed from the `getUserServiceTokens()` return value (already called at session start in `agent-runner.ts:370`).

**Agent vs ops-provisioner boundary:** The service-automator handles API/MCP-driven provisioning (deterministic, repeatable). The ops-provisioner handles browser-based SaaS setup (interactive, Playwright-driven). When the service-automator hits a service without API coverage, it provides guided instructions rather than delegating to ops-provisioner (which requires Playwright and is desktop-only).

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

### Research Insights: Guided Instructions

**Deep link accuracy:** Service dashboard URLs change. Do not hardcode deep links in the agent prompt directly -- place them in a reference file (`plugins/soleur/agents/operations/references/service-deep-links.md`) that can be updated without modifying the agent definition. The agent reads the reference at invocation time.

**Expanded provisioning playbooks:**

| Service | Signup URL | Token Generation URL | Token Type | Required Permissions |
|---------|-----------|---------------------|------------|---------------------|
| Cloudflare | `https://dash.cloudflare.com/sign-up` | `https://dash.cloudflare.com/profile/api-tokens` | API Token | Zone:Read, DNS:Edit, Zone Settings:Edit |
| Stripe | `https://dashboard.stripe.com/register` | `https://dashboard.stripe.com/apikeys` | Restricted Key | Products:Write, Prices:Write, Customers:Write |
| Plausible | `https://plausible.io/register` | `https://plausible.io/settings/api-keys` | API Key | Sites API scope |
| Hetzner | `https://console.hetzner.cloud/` | `https://console.hetzner.cloud/manage/<project>/security/api-tokens` | API Token | Read/Write |
| Resend | `https://resend.com/signup` | `https://resend.com/api-keys` | API Key | Full access |

**Review gate UX:** The existing `AskUserQuestion` interceptor in `canUseTool` (agent-runner.ts line 601) handles review gates. The agent sends a question like "I've generated the steps. Have you completed step 1 (create your Cloudflare account)?" and the user clicks a button to confirm. The conversation pauses until the WebSocket receives the user's response. This is the same pattern used for the ops-provisioner's "Complete this step manually" flow.

**Post-completion token capture flow:**

1. Agent detects service setup is complete (user confirmed final step)
2. Agent instructs: "Now generate an API token at [deep link]. Copy the token."
3. Agent instructs: "Go to Settings > Connected Services and paste your [Service] API token."
4. Agent waits for confirmation, then verifies the token is stored by checking the service list

This creates a virtuous cycle: the first time is guided, subsequent interactions use the stored token for full automation.

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

- [x] Plugin MCP tools (Cloudflare, Stripe) are authorized by `canUseTool` via explicit allowlist (Phase 0)
- [ ] Agent can provision Cloudflare zones via MCP tools (Cloudflare MCP server accessible)
- [ ] Agent can create Stripe products/prices via MCP tools (Stripe MCP server accessible)
- [ ] Agent can create Plausible sites and goals via in-process API tools
- [ ] Agent falls back to guided instructions when no token is stored for a service
- [ ] Guided instructions include deep links to service configuration pages
- [ ] Review gates pause the agent at each manual step in guided mode
- [ ] After guided setup, agent prompts user to store their new API token
- [ ] Service tokens from Connected Services are available to automation tools
- [ ] Plausible API tools validate inputs and handle errors gracefully (timeout, auth failure, API errors)
- [ ] Plausible API tools validate JSON response body before parsing (non-JSON 2xx protection)

### Non-Functional Requirements

- [ ] No new database tables or migrations required (uses existing `api_keys`)
- [ ] Plausible API calls timeout after 5 seconds (match existing `VALIDATION_TIMEOUT_MS`)
- [ ] Plausible `site_id` inputs validated against `[a-zA-Z0-9._-]+` pattern (URL injection prevention)
- [ ] Service tool errors are logged but never expose tokens in logs or error messages
- [ ] In-process MCP tools follow the `create_pull_request` security pattern (input validation, error containment)
- [ ] Agent environment isolation maintained -- service tokens only injected via `buildAgentEnv` allowlist
- [x] Plugin MCP tool allowlist derived from plugin.json server names, not hardcoded (defense-in-depth)
- [x] Unregistered MCP tools still denied by `canUseTool` (regression test required)

### Quality Gates

- [ ] Unit tests for all Plausible API tool wrappers
- [ ] Integration test for token retrieval + tool registration flow
- [ ] TypeScript strict mode passes
- [ ] No new `any` types introduced
- [ ] Markdownlint passes on all changed `.md` files

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a plugin.json with Cloudflare and Stripe MCP servers, when `canUseTool` receives `mcp__plugin_soleur_cloudflare__execute`, then it returns `{ behavior: "allow" }`
- Given a plugin.json with Cloudflare and Stripe MCP servers, when `canUseTool` receives `mcp__plugin_soleur_unknown__hack`, then it returns `{ behavior: "deny" }` (unregistered server)
- Given a user with a stored Cloudflare API token, when the agent is asked to "create a DNS zone for example.com", then the Cloudflare MCP tools are available and the agent can invoke them
- Given a user with a stored Stripe secret key, when the agent is asked to "set up payments", then the Stripe MCP tools are available and the agent can invoke them
- Given a user with a stored Plausible API key, when the agent is asked to "add analytics to my site", then the in-process `plausible_create_site` tool is available and creates a site via the API
- Given a user without any stored Plausible token, when the agent is asked to "set up analytics", then the agent provides step-by-step guided instructions with a deep link to `https://plausible.io/register`
- Given a Plausible API call that returns 401, when `plausible_create_site` is invoked, then the tool returns an error result (not a crash) and the agent suggests re-validating the token

### Edge Cases

- Given a user whose Plausible API key has expired, when the agent tries to create a site, then the tool returns a clear "token invalid" error and the agent suggests reconnecting via the Connected Services page
- Given a Plausible API timeout (>5s), when `plausible_create_site` is invoked, then the tool returns a timeout error without leaving orphaned resources
- Given the Cloudflare MCP server is unreachable, when the agent tries to provision DNS, then the agent falls back to guided instructions rather than failing silently
- Given a Plausible API that returns HTTP 200 with HTML body (reverse proxy error), when `plausible_create_site` is invoked, then the tool returns a "non-JSON response" error (not a parse crash)
- Given a `site_id` input containing path traversal characters (`../admin`), when `plausible_add_goal` is invoked, then the tool rejects the input with "Invalid site ID format"
- Given both an OAuth session and a stored API key for Stripe, when the agent needs to perform a Stripe operation, then it uses the MCP tools (OAuth) not direct API calls

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
| **canUseTool plugin MCP authorization** | **Blocked** | **Phase 0 -- deny-by-default blocks all plugin MCP tools. Must fix before any MCP integration works.** |
| Stripe MCP server availability | Available | `https://mcp.stripe.com` with OAuth |
| Plausible Sites API | Available | REST API with bearer token auth. May require Enterprise plan -- verify before Phase 2. |
| Review gate notifications (#1049) | Not started | Enhances guided fallback but not a blocker -- basic WebSocket messages work |

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **canUseTool blocks plugin MCP tools** | Certain | Critical -- all MCP integrations fail | Phase 0 adds explicit allowlist. Must be implemented first. |
| Plausible Sites API requires Enterprise plan | Medium | High -- tools register but fail for free-tier users | Check plan tier in tool implementation, provide clear error message. Verify current plan tier before starting Phase 2. |
| Cloudflare/Stripe MCP OAuth requires user interaction | Low | Low -- expected behavior | Document in guided instructions that first use requires OAuth consent |
| Plausible returns non-JSON with 2xx status | Medium | Medium -- tool crashes on JSON parse | Validate response body before parsing (learning: 2026-04-02). Use `try/catch` around `res.json()`. |
| MCP server rate limiting | Low | Medium | Implement retry with backoff in tool wrappers |
| Token rotation invalidates stored tokens | Medium | Low | Existing token validation catches this; agent suggests reconnecting |
| Plausible API v1 deprecation (#1360) | Low | Medium | Track via existing issue; migration path is straightforward |
| `npx` not available in Docker container (if Stripe stdio fallback needed) | Low | Low -- only affects stdio fallback path | Docker image already has Node.js/npm; `npx` is available. Verify in Dockerfile. |
| Plugin MCP tool name format changes across SDK versions | Low | High -- allowlist silently breaks | Pin Agent SDK version (already done, #1045). Add test that verifies expected tool name format. |

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
- canUseTool deny-by-default: `apps/web-platform/server/agent-runner.ts:664` -- plugin MCP tools blocked
- Connected Services UI: `apps/web-platform/components/settings/connected-services-content.tsx`
- Tool path checker: `apps/web-platform/server/tool-path-checker.ts` -- `SAFE_TOOLS`, `FILE_TOOLS`, `isSafeTool()`
- MCP tool design reference: `plugins/soleur/skills/agent-native-architecture/references/mcp-tool-design.md`

### Institutional Learnings Applied

- **canUseTool MCP scope allowlist:** `knowledge-base/project/learnings/security-issues/2026-04-06-mcp-tool-canusertool-scope-allowlist.md` -- use explicit allowlist, not prefix matching
- **canUseTool sandbox defense-in-depth:** `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- deny-by-default, env allowlists, `settingSources: []`
- **Cloudflare MCP integration:** `knowledge-base/project/learnings/integration-issues/2026-02-22-cloudflare-mcp-plugin-json-integration.md` -- HTTP transport, OAuth 2.1
- **OAuth MCP bundling:** `knowledge-base/project/learnings/integration-issues/2026-02-22-oauth-mcp-servers-can-bundle-in-plugin-json.md` -- `type: http` works for OAuth servers
- **Plausible API response validation:** `knowledge-base/project/learnings/2026-04-02-plausible-api-response-validation-prevention.md` -- validate JSON before parsing
- **Plausible goals API hardening:** `knowledge-base/project/learnings/2026-03-13-plausible-goals-api-provisioning-hardening.md` -- PUT upsert semantics, HTTPS validation, site ID format validation
- **MCP adapter testability:** `knowledge-base/project/learnings/integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md` -- extract pure functions for unit tests
- **Check MCP/API before Playwright:** `knowledge-base/project/learnings/2026-03-25-check-mcp-api-before-playwright.md` -- MCP > CLI > API > Playwright priority chain

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
