# Tasks: sec: verify canUseTool callback caching behavior

## Phase 1: Setup and SDK Version Bump

- [ ] 1.1 Install dependencies in `apps/web-platform/` (`npm install`)
- [ ] 1.2 Bump `@anthropic-ai/claude-agent-sdk` from `^0.2.76` to `^0.2.80` in `apps/web-platform/package.json`
- [ ] 1.3 Run `npm install` again to pull new SDK version
- [ ] 1.4 Verify existing tests pass: `./node_modules/.bin/vitest run canusertool-sandbox`

## Phase 2: Write Caching Verification Test

- [ ] 2.1 Create `apps/web-platform/test/canusertool-caching.test.ts`
  - [ ] 2.1.1 Test: callback fires for each tool invocation with different `file_path` values (same tool name)
  - [ ] 2.1.2 Test: callback fires for same tool name + same path (no deduplication)
  - [ ] 2.1.3 Test: callback fires for different tool names
  - [ ] 2.1.4 Add env-var gate (`AGENT_SDK_API_KEY`) to skip tests when no API key is available
- [ ] 2.2 Run the caching verification test with API key: `ANTHROPIC_API_KEY=<key> ./node_modules/.bin/vitest run canusertool-caching`
- [ ] 2.3 Record results: callback invocation count vs tool use count

## Phase 3: Evaluate and Implement Based on Findings

### If NOT cached (expected):

- [ ] 3.1 Update `spike/FINDINGS.md` section "canUseTool caching" to clarify the observation was caused by pre-approved tool bypass, not SDK caching
- [ ] 3.2 Update `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md` to correct the "may cache" claim
- [ ] 3.3 Update Known Limitations item 3 in `knowledge-base/plans/2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md`
- [ ] 3.4 Update `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` if it references caching

### If cached (requires mitigation):

- [ ] 3.5 Create `apps/web-platform/server/sandbox-hook.ts` with `PreToolUse` hook using `isPathInWorkspace`
- [ ] 3.6 Update `apps/web-platform/server/agent-runner.ts` to register the `PreToolUse` hook in `query()` options
- [ ] 3.7 Write tests for hook-based sandbox in `apps/web-platform/test/sandbox-hook.test.ts`
- [ ] 3.8 Create institutional learning documenting caching behavior and hook mitigation

## Phase 4: Finalize

- [ ] 4.1 Create institutional learning documenting findings (`knowledge-base/learnings/2026-03-20-canusertool-caching-verification.md`)
- [ ] 4.2 Run compound (`skill: soleur:compound`)
- [ ] 4.3 Commit and push
