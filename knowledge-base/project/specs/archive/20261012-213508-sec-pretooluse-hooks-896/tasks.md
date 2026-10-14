# Tasks: sec: migrate sandbox enforcement from canUseTool to PreToolUse hooks

## Phase 1: Setup

- [ ] 1.1 Run `npm install` in worktree to ensure SDK types are available
- [ ] 1.2 Verify `HookCallback` and `PreToolUseHookInput` are exported from `@anthropic-ai/claude-agent-sdk` (SDK ^0.2.80)
- [ ] 1.3 If types not exported (unlikely per Context7), define local interfaces matching documented shape

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/server/sandbox-hook.ts`
  - [ ] 2.1.1 Import `HookCallback`, `PreToolUseHookInput` from SDK
  - [ ] 2.1.2 Import `isPathInWorkspace` from `./sandbox`
  - [ ] 2.1.3 Import `containsSensitiveEnvAccess` from `./bash-sandbox`
  - [ ] 2.1.4 Define `FILE_TOOLS` as `Set` for O(1) lookup: `["Read", "Write", "Edit", "Glob", "Grep"]`
  - [ ] 2.1.5 Implement `createSandboxHook(workspacePath)` factory returning `HookCallback`
  - [ ] 2.1.6 File-tool branch: check `file_path` or `path` field via `isPathInWorkspace`
  - [ ] 2.1.7 Bash branch: check command via `containsSensitiveEnvAccess`
  - [ ] 2.1.8 Return `{ systemMessage, hookSpecificOutput: { hookEventName, permissionDecision: "deny", permissionDecisionReason } }` on deny
  - [ ] 2.1.9 Return `{}` on allow (empty = continue to next permission step)

- [ ] 2.2 Modify `apps/web-platform/server/agent-runner.ts`
  - [ ] 2.2.1 Import `createSandboxHook` from `./sandbox-hook`
  - [ ] 2.2.2 Add `hooks.PreToolUse` array to `query()` options with matcher `"Read|Write|Edit|Glob|Grep|Bash"`
  - [ ] 2.2.3 Remove file-tool sandbox block from `canUseTool` (lines 209-222: the `["Read", "Write", "Edit", "Glob", "Grep"].includes(toolName)` block)
  - [ ] 2.2.4 Remove Bash env-access check from `canUseTool` (lines 225-234: the `toolName === "Bash"` block)
  - [ ] 2.2.5 Remove `NotebookRead` from `SAFE_TOOLS` (stale reference -- SDK reads notebooks via Read tool)
  - [ ] 2.2.6 Retain AskUserQuestion review gate in `canUseTool` (unchanged)
  - [ ] 2.2.7 Retain safe-tool allowlist in `canUseTool`: `["Agent", "Skill", "TodoRead", "TodoWrite", "LS"]`
  - [ ] 2.2.8 Retain deny-by-default in `canUseTool` (unchanged)

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/sandbox-hook.test.ts`
  - [ ] 3.1.1 Test: allow Read with file_path inside workspace (returns `{}`)
  - [ ] 3.1.2 Test: deny Read with file_path outside workspace (`/etc/passwd`) -- check `permissionDecision === "deny"` and `systemMessage` contains "workspace"
  - [ ] 3.1.3 Test: deny Read with `../` traversal escaping workspace
  - [ ] 3.1.4 Test: deny Write with file_path outside workspace
  - [ ] 3.1.5 Test: deny Glob with `path` outside workspace
  - [ ] 3.1.6 Test: deny Grep with `path` outside workspace
  - [ ] 3.1.7 Test: deny Bash with `env` command -- check `systemMessage` contains "environment variables"
  - [ ] 3.1.8 Test: allow Bash with clean command (`ls -la`) -- returns `{}`
  - [ ] 3.1.9 Test: allow Read with empty `file_path` -- returns `{}` (not outside workspace)
  - [ ] 3.1.10 Test: verify `hookSpecificOutput.hookEventName` equals `"PreToolUse"` on deny
  - [ ] 3.1.11 Test: negative-space -- all file-accessing tools covered by hook or documented as exempt

- [ ] 3.2 Rename `canusertool-sandbox.test.ts` to `sandbox.test.ts` (tests `isPathInWorkspace`, not canUseTool)
- [ ] 3.3 Run full test suite: `bun test apps/web-platform/test/`
- [ ] 3.4 Verify no regressions in existing sandbox and caching tests

## Phase 4: Cleanup

- [ ] 4.1 Run compound (`skill: soleur:compound`)
- [ ] 4.2 Commit and push
