# Tasks: Read CI Status and Logs via Proxy (#1927)

## Phase 1: Merge and Verify

- [ ] 1.1 Merge `origin/main` into this branch to receive CI/CD implementation from PR #1925
- [ ] 1.2 Run test suite: `cd apps/web-platform && bun test ci-tools github-api tool-tiers canusertool-tiered-gating`
- [ ] 1.3 Verify TypeScript compilation: `cd apps/web-platform && npx tsc --noEmit`

## Phase 2: Acceptance Criteria Verification

- [ ] 2.1 **AC1** Verify `readCiStatus()` returns workflow runs with status, SHA, branch, URL, workflowId
- [ ] 2.2 **AC2** Verify `readWorkflowLogs()` fetches check runs and extracts annotations
- [ ] 2.3 **AC3** Verify `fetchFallbackLog()` returns last 100 lines of first failed step
- [ ] 2.4 **AC4** Verify both tools are mapped to `auto-approve` in `tool-tiers.ts` and pass through `canUseTool`
- [ ] 2.5 **AC5** Verify MCP tools hardcode owner/repo from workspace metadata (no user params)

## Phase 3: Gap Analysis

- [ ] 3.1 Confirm check runs vs check suites is acceptable (check runs provide more granular data)
- [ ] 3.2 Confirm legacy Status API omission is acceptable (GitHub Actions uses Check Runs exclusively)
- [ ] 3.3 Verify GitHub App manifest permissions or confirm graceful degradation (403 handling)
