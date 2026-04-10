# Tasks: Service Automation (API + MCP Integrations + Guided Fallback)

**Plan:** `knowledge-base/project/plans/2026-04-10-feat-service-automation-api-mcp-integrations-plan.md`
**Issue:** [#1050](https://github.com/jikig-ai/soleur/issues/1050)
**Branch:** `feat-service-automation`

## Phase 1: Stripe MCP Integration

- [ ] 1.1 Add Stripe MCP server entry to `plugins/soleur/.claude-plugin/plugin.json`
  - URL: `https://mcp.stripe.com`, type: `http`
  - Follow existing Cloudflare/Vercel MCP pattern
- [ ] 1.2 Verify Stripe MCP entry is syntactically correct (JSON parse check)
- [ ] 1.3 Run component tests to confirm plugin.json changes pass validation

## Phase 2: Plausible In-Process MCP Tools

- [ ] 2.1 Create `apps/web-platform/server/service-tools.ts`
  - [ ] 2.1.1 Define `plausible_create_site` tool (POST `/api/v1/sites`)
  - [ ] 2.1.2 Define `plausible_add_goal` tool (PUT `/api/v1/sites/goals`)
  - [ ] 2.1.3 Define `plausible_get_stats` tool (GET `/api/v1/stats/aggregate`)
  - [ ] 2.1.4 Add 5-second timeout to all Plausible API calls
  - [ ] 2.1.5 Add token sanitization -- never log or expose tokens in error messages
- [ ] 2.2 Integrate service tools into agent-runner.ts MCP server
  - [ ] 2.2.1 Import service tool definitions from `service-tools.ts`
  - [ ] 2.2.2 Register tools in `soleur_platform` MCP server alongside `create_pull_request`
  - [ ] 2.2.3 Conditionally register Plausible tools based on token availability
  - [ ] 2.2.4 Add Plausible tool names to `platformToolNames` array
- [ ] 2.3 Create `apps/web-platform/test/service-tools.test.ts`
  - [ ] 2.3.1 Test `plausible_create_site` with mocked success response
  - [ ] 2.3.2 Test `plausible_create_site` with 401 response (invalid token)
  - [ ] 2.3.3 Test `plausible_create_site` with timeout
  - [ ] 2.3.4 Test `plausible_add_goal` with mocked success
  - [ ] 2.3.5 Test `plausible_get_stats` with mocked success
  - [ ] 2.3.6 Test input validation (missing domain, invalid goal_type)
  - [ ] 2.3.7 Verify tokens are not present in error outputs

## Phase 3: Service Automation Agent

- [ ] 3.1 Create `plugins/soleur/agents/operations/service-automator.md`
  - [ ] 3.1.1 YAML frontmatter (name, description, model: inherit)
  - [ ] 3.1.2 Disambiguation sentence vs ops-provisioner
  - [ ] 3.1.3 Tier selection logic documentation
  - [ ] 3.1.4 Per-service provisioning playbooks (Cloudflare, Stripe, Plausible)
  - [ ] 3.1.5 Review gate protocol for manual steps
- [ ] 3.2 Update `plugins/soleur/agents/operations/ops-provisioner.md` disambiguation
  - Add cross-reference to service-automator for API/MCP-based provisioning
- [ ] 3.3 Inject connected services context into agent system prompt
  - [ ] 3.3.1 Query user's connected services list at session start
  - [ ] 3.3.2 Include service list in system prompt for automation context

## Phase 4: Guided Instructions Fallback

- [ ] 4.1 Add guided instruction playbooks to service-automator agent
  - [ ] 4.1.1 Cloudflare guided flow (deep links + steps)
  - [ ] 4.1.2 Stripe guided flow (deep links + steps)
  - [ ] 4.1.3 Plausible guided flow (deep links + steps)
- [ ] 4.2 Implement post-completion token capture prompt
  - Agent prompts user to store API token via Connected Services after manual setup
- [ ] 4.3 Verify review gate behavior in guided mode
  - Agent pauses at each manual step, continues on user response

## Phase 5: Integration Testing

- [ ] 5.1 Extend `apps/web-platform/test/agent-runner-tools.test.ts`
  - [ ] 5.1.1 Test token retrieval + Plausible tool registration flow
  - [ ] 5.1.2 Test tool registration skipped when no Plausible token stored
  - [ ] 5.1.3 Test platform tool names include Plausible tools when registered
- [ ] 5.2 Verify agent token description compliance
  - [ ] 5.2.1 Run cumulative word count check on agent descriptions
  - [ ] 5.2.2 Verify no `<example>` blocks in agent descriptions
- [ ] 5.3 Run markdownlint on all changed `.md` files
- [ ] 5.4 Run TypeScript strict mode check
- [ ] 5.5 Verify zero `any` types introduced

## Post-Implementation

- [ ] 6.1 Update ops-provisioner.md disambiguation to cross-reference service-automator
- [ ] 6.2 Update `plugins/soleur/README.md` agent counts if new agent added
- [ ] 6.3 Register service-automator in `docs/_data/skills.js` SKILL_CATEGORIES if applicable
- [ ] 6.4 Run compound (`skill: soleur:compound`)
