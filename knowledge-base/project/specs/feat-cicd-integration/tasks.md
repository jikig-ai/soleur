# Tasks: CI/CD Integration

## Phase 1: Tiered Gating Infrastructure (#1926)

- [x] 1.1 Add tiered gate logic to `canUseTool` via switch on tool name: `auto-approve` | `gated` | `blocked`
- [x] 1.2 For `gated` tools: trigger `AskUserQuestion` with tool name, parameters, and human-readable description
- [x] 1.3 For `blocked` patterns: reject with clear error message
- [x] 1.4 Add inline structured audit logging in `canUseTool` (JSON to stdout)
- [ ] 1.5 Update GitHub App manifest to add `actions:write` and `checks:read` permissions
- [ ] 1.6 Add graceful degradation for 403s from unapproved permission upgrades
- [x] 1.7 Write tests for tiered gating logic

## Phase 2: Read CI Status (#1927)

- [ ] 2.1 Create `github-api.ts`: thin fetch wrapper using `generateInstallationToken()`
- [ ] 2.2 Add `github_read_ci_status` tool (auto-approve) — includes workflow names/IDs in results
- [ ] 2.3 Add `github_read_workflow_logs` tool (auto-approve) — annotations first, fallback to last 100 lines of failed step
- [ ] 2.4 Register tools with `auto-approve` gate tier
- [ ] 2.5 Add `allowedTools` entries in agent-runner.ts
- [ ] 2.6 Write tests: mock GitHub API, verify annotation extraction

## Phase 3: Trigger Workflows (#1928)

- [ ] 3.1 Add `github_trigger_workflow` tool (gated)
- [ ] 3.2 Register with `gated` tier in canUseTool
- [ ] 3.3 Implement review gate message: "Agent wants to trigger workflow **{name}** on branch **{ref}**"
- [ ] 3.4 After dispatch, auto-poll status and return run ID
- [ ] 3.5 Add simple rate limit counter: max 10 workflow triggers per session
- [ ] 3.6 Write tests: verify gate fires, verify dispatch, verify rate limiting

## Phase 4: Open PRs (#1929)

- [ ] 4.1 Extract credential helper from workspace.ts into reusable `withCredentialHelper()`
- [ ] 4.2 Add `github_push_branch` MCP tool (gated) — schema: `branch` (string), `force` (boolean, default false)
- [ ] 4.3 Validate branch name in handler: reject main, master, stored default branch
- [ ] 4.4 Register `github_push_branch` with `gated` tier
- [ ] 4.5 Add review gate to existing `create_pull_request` tool
- [ ] 4.6 Implement review gate messages for push and PR creation
- [ ] 4.7 Set git commit author to `Soleur Agent <agent@soleur.ai>` (hardcoded)
- [ ] 4.8 Write tests: branch validation, credential cleanup, gate verification

## Phase 5: Integration Testing

- [ ] 5.1 End-to-end test: read CI -> trigger workflow -> read results
- [ ] 5.2 End-to-end test: push branch -> open PR -> read CI on PR
- [ ] 5.3 Security test: verify agent cannot access token, bypass gate, or reach GitHub directly
- [ ] 5.4 Update GitHub App manifest (manual: requires App settings page)
