# Tasks: Service Automation (API + MCP Integrations + Guided Fallback)

**Plan:** `knowledge-base/project/plans/2026-04-10-feat-service-automation-api-mcp-integrations-plan.md`
**Issue:** [#1050](https://github.com/jikig-ai/soleur/issues/1050)
**Branch:** `feat-service-automation`

## Phase 0: canUseTool Plugin MCP Authorization (Prerequisite)

- [x] 0.1 Read plugin.json to extract MCP server names at agent-runner startup
  - Parse `plugins/soleur/.claude-plugin/plugin.json` mcpServers keys
  - Build `pluginMcpServerNames` array (e.g., `["cloudflare", "stripe", "vercel", "context7"]`)
- [x] 0.2 Add plugin MCP allowlist to canUseTool in `agent-runner.ts`
  - [x] 0.2.1 Check `toolName.startsWith("mcp__plugin_soleur_")` AND server name matches
  - [x] 0.2.2 Log plugin MCP tool invocations for audit trail
  - [x] 0.2.3 Place check BEFORE the deny-by-default block (line 664)
- [x] 0.3 Add plugin MCP patterns to `allowedTools` SDK option
  - Build wildcard patterns: `mcp__plugin_soleur_<server>__*`
  - Merge with existing `platformToolNames` into single `allowedTools` array
- [x] 0.4 Add tests to `agent-runner-tools.test.ts`
  - [x] 0.4.1 Test `mcp__plugin_soleur_cloudflare__execute` is allowed
  - [x] 0.4.2 Test `mcp__plugin_soleur_unknown__hack` is denied
  - [x] 0.4.3 Test unregistered `mcp__random_server__tool` is denied
  - [x] 0.4.4 Test `platformToolNames` still works for in-process tools

## Phase 1: Stripe MCP Integration

- [x] 1.1 Add Stripe MCP server entry to `plugins/soleur/.claude-plugin/plugin.json`
  - URL: `https://mcp.stripe.com`, type: `http`
  - Follow existing Cloudflare/Vercel MCP pattern
- [x] 1.2 Verify Stripe MCP entry is syntactically correct (JSON parse check)
- [x] 1.3 Run component tests to confirm plugin.json changes pass validation

## Phase 2: Plausible In-Process MCP Tools

- [x] 2.1 Create `apps/web-platform/server/service-tools.ts`
  - [x] 2.1.1 Define `plausible_create_site` tool (POST `/api/v1/sites`)
  - [x] 2.1.2 Define `plausible_add_goal` tool (PUT `/api/v1/sites/goals`)
  - [x] 2.1.3 Define `plausible_get_stats` tool (GET `/api/v1/stats/aggregate`)
  - [x] 2.1.4 Add 5-second timeout to all Plausible API calls
  - [x] 2.1.5 Add token sanitization -- never log or expose tokens in error messages
  - [x] 2.1.6 Add JSON response body validation before parsing (non-JSON 2xx protection)
  - [x] 2.1.7 Add `site_id` input validation (`[a-zA-Z0-9._-]+` pattern, no path traversal)
  - [x] 2.1.8 Add HTTPS URL validation before transmitting bearer token
- [x] 2.2 Integrate service tools into agent-runner.ts MCP server
  - [x] 2.2.1 Import service tool definitions from `service-tools.ts`
  - [x] 2.2.2 Register tools in `soleur_platform` MCP server alongside `create_pull_request`
  - [x] 2.2.3 Conditionally register Plausible tools based on token availability
  - [x] 2.2.4 Add Plausible tool names to `platformToolNames` array
- [x] 2.3 Create `apps/web-platform/test/service-tools.test.ts`
  - [x] 2.3.1 Test `plausible_create_site` with mocked success response
  - [x] 2.3.2 Test `plausible_create_site` with 401 response (invalid token)
  - [x] 2.3.3 Test `plausible_create_site` with timeout
  - [x] 2.3.4 Test `plausible_add_goal` with mocked success
  - [x] 2.3.5 Test `plausible_get_stats` with mocked success
  - [x] 2.3.6 Test input validation (missing domain, invalid goal_type)
  - [x] 2.3.7 Verify tokens are not present in error outputs
  - [x] 2.3.8 Test non-JSON response handling (HTML error page with 200 status)
  - [x] 2.3.9 Test `site_id` with path traversal characters rejected
  - [x] 2.3.10 Test `plausible_add_goal` idempotency (PUT upsert semantics)

## Phase 3: Service Automation Agent

- [x] 3.1 Create `plugins/soleur/agents/operations/service-automator.md`
  - [x] 3.1.1 YAML frontmatter (name, description, model: inherit)
  - [x] 3.1.2 Disambiguation sentence vs ops-provisioner
  - [x] 3.1.3 Tier selection logic documentation
  - [x] 3.1.4 Per-service provisioning playbooks (Cloudflare, Stripe, Plausible)
  - [x] 3.1.5 Review gate protocol for manual steps
- [x] 3.2 Update `plugins/soleur/agents/operations/ops-provisioner.md` disambiguation
  - Add cross-reference to service-automator for API/MCP-based provisioning
- [x] 3.3 Inject connected services context into agent system prompt
  - [x] 3.3.1 Query user's connected services list at session start
  - [x] 3.3.2 Include service list in system prompt for automation context

## Phase 4: Guided Instructions Fallback

- [x] 4.0 Create `plugins/soleur/agents/operations/references/service-deep-links.md`
  - Deep links for signup, token generation, and dashboard for each service
  - Separate from agent prompt so URLs can be updated independently
- [x] 4.1 Add guided instruction playbooks to service-automator agent
  - [x] 4.1.1 Cloudflare guided flow (deep links + steps)
  - [x] 4.1.2 Stripe guided flow (deep links + steps)
  - [x] 4.1.3 Plausible guided flow (deep links + steps)
  - [x] 4.1.4 Include required token permissions for each service
- [x] 4.2 Implement post-completion token capture prompt
  - Agent prompts user to store API token via Connected Services after manual setup
- [x] 4.3 Verify review gate behavior in guided mode
  - Agent pauses at each manual step, continues on user response

## Phase 5: Integration Testing

- [x] 5.1 Extend `apps/web-platform/test/agent-runner-tools.test.ts`
  - [x] 5.1.1 Test token retrieval + Plausible tool registration flow
  - [x] 5.1.2 Test tool registration skipped when no Plausible token stored
  - [x] 5.1.3 Test platform tool names include Plausible tools when registered
- [x] 5.2 Verify agent token description compliance
  - [x] 5.2.1 Run cumulative word count check on agent descriptions
  - [x] 5.2.2 Verify no `<example>` blocks in agent descriptions
- [x] 5.3 Run markdownlint on all changed `.md` files
- [x] 5.4 Run TypeScript strict mode check
- [x] 5.5 Verify zero `any` types introduced

## Post-Implementation

- [x] 6.1 Update ops-provisioner.md disambiguation to cross-reference service-automator
- [x] 6.2 Update `plugins/soleur/README.md` agent counts if new agent added
- [x] 6.3 Register service-automator in `docs/_data/skills.js` SKILL_CATEGORIES if applicable
- [x] 6.4 Run compound (`skill: soleur:compound`)
