# Tasks: Server-Side PR Creation Endpoint

Source: [Plan](../../plans/2026-04-06-feat-server-side-pr-creation-endpoint-plan.md)
Issue: [#1648](https://github.com/jikig-ai/soleur/issues/1648)

## Phase 1: Setup

- [x] 1.1 ~~Verify `zod` is available~~ -- confirmed: zod v4.3.6 in `node_modules/zod/`; import via `"zod/v4"` (not `"zod"`)
- [x] 1.2 ~~Verify `tool` and `createSdkMcpServer` exports~~ -- confirmed in `sdk.d.ts`; both are exported and typed
- [x] 1.3 Add `github_installation_id` and `repo_url` to the user select query in `agent-runner.ts`

## Phase 2: Core Implementation

### 2.1 createPullRequest in github-app.ts

- [x] 2.1.1 Add `createPullRequest` function to `apps/web-platform/server/github-app.ts`
- [x] 2.1.2 Add `PullRequestResult` interface to types section

### 2.2 Inline MCP Server Tool in agent-runner.ts

- [x] 2.2.1 Import `tool`, `createSdkMcpServer` from `@anthropic-ai/claude-agent-sdk` and `z` from `zod/v4`
- [x] 2.2.2 After user data query, parse `owner`/`repo` from `repo_url` with validation (non-empty strings)
- [x] 2.2.3 Define `create_pull_request` tool with Zod schema (head, base, title, body)
- [x] 2.2.4 Tool handler: try/catch around `createPullRequest`, return `isError` content on failure
- [x] 2.2.5 Create `soleur_platform` MCP server with the tool
- [x] 2.2.6 Conditionally pass `mcpServers: { soleur_platform: toolServer }` to `query()` when `installationId` exists
- [x] 2.2.7 Add `"mcp__soleur_platform__create_pull_request"` to `allowedTools` in query options

### 2.3 canUseTool Update

- [x] 2.3.1 Add `mcp__` prefix check before deny-by-default fallback in `canUseTool`
- [ ] 2.3.2 Log `mcp__` tool invocations for audit visibility (similar to Agent tool logging)

## Phase 3: Testing

### 3.1 Unit Tests: createPullRequest

- [x] 3.1.1 Create `apps/web-platform/test/github-app-pr.test.ts`
- [x] 3.1.2 Test happy path: mock GitHub API 201, verify returned URL/number
- [x] 3.1.3 Test 422 error: branch not found / no diff
- [x] 3.1.4 Test 422 error: PR already exists for head/base
- [x] 3.1.5 Test 404 error: repo not found
- [x] 3.1.6 Test token generation failure propagation
- [x] 3.1.7 Use unique `installationId` per test (per learning: token cache test isolation)

### 3.2 Integration Tests: Agent Tool Wiring

- [x] 3.2.1 Create `apps/web-platform/test/agent-runner-tools.test.ts`
- [x] 3.2.2 Test `mcpServers` passed to `query()` when `installationId` exists
- [x] 3.2.3 Test `mcpServers` omitted when `installationId` is null
- [ ] 3.2.4 Test tool handler wraps errors in `isError` content
- [x] 3.2.5 Test `canUseTool` allows `mcp__` prefixed tools

## Phase 4: Verification

- [x] 4.1 Run full test suite: 482 tests pass
- [x] 4.2 TypeScript check: `npx tsc --noEmit` passes
- [x] 4.3 Verify no new dependencies need lockfile regeneration (zod already transitive dep)
