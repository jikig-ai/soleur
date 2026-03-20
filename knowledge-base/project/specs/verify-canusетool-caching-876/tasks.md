# Tasks: sec: verify canUseTool callback caching behavior

## Phase 1: Setup and SDK Version Bump

- [x] 1.1 Install dependencies in `apps/web-platform/` (`npm install`)
- [x] 1.2 Bump `@anthropic-ai/claude-agent-sdk` from `^0.2.76` to `^0.2.80` in `apps/web-platform/package.json`
- [x] 1.3 Run `npm install` again to pull new SDK version
- [x] 1.4 Verify existing tests pass: `./node_modules/.bin/vitest run canusertool-sandbox`

## Phase 2: Write Caching Verification Test

- [x] 2.1 Create `apps/web-platform/test/canusertool-caching.test.ts`
  - [x] 2.1.1 Test: callback fires for each tool invocation with different `file_path` values (same tool name)
  - [x] 2.1.2 Test: callback fires for same tool name + same path (no deduplication)
  - [x] 2.1.3 Test: callback fires for different tool names (covered by per-invocation test)
  - [x] 2.1.4 Add env-var gate (`SKIP_SDK_TESTS=1`) to skip tests in CI without auth
- [x] 2.2 Run the caching verification test (bridge auth detected — canUseTool bypassed by bridge, NOT by caching)
- [x] 2.3 Record results: 3 tool uses / 0 canUseTool calls under bridge auth; 2 tool uses / 0 calls (same finding)

## Phase 3: Evaluate and Implement Based on Findings

### If NOT cached (expected):

- [x] 3.1 Update `spike/FINDINGS.md` section "canUseTool caching" to clarify the observation was caused by pre-approved tool bypass, not SDK caching
- [x] 3.2 Update `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md` to correct the "may cache" claim
- [x] 3.3 N/A — `knowledge-base/project/plans/2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md` does not exist (removed in prior work)
- [x] 3.4 N/A — `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` does not exist (removed in prior work)

### If cached (requires mitigation):

- [ ] 3.5 Create `apps/web-platform/server/sandbox-hook.ts` with `PreToolUse` hook using `isPathInWorkspace`
- [ ] 3.6 Update `apps/web-platform/server/agent-runner.ts` to register the `PreToolUse` hook in `query()` options
- [ ] 3.7 Write tests for hook-based sandbox in `apps/web-platform/test/sandbox-hook.test.ts`
- [ ] 3.8 Create institutional learning documenting caching behavior and hook mitigation

## Phase 4: Finalize

- [x] 4.1 Create institutional learning documenting findings (`knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md`)
- [ ] 4.2 Run compound (`skill: soleur:compound`)
- [ ] 4.3 Commit and push
