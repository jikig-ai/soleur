# Tasks: sec: migrate sandbox enforcement from canUseTool to PreToolUse hooks

## Phase 1: Setup

- [ ] 1.1 Run `npm install` in worktree to ensure SDK types are available
- [ ] 1.2 Verify SDK version is ^0.2.80 with hook type exports (`PreToolUseHookInput`, `HookCallback`)
- [ ] 1.3 If types not exported, define local interfaces in `sandbox-hook.ts`

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/server/sandbox-hook.ts`
  - [ ] 2.1.1 Import `isPathInWorkspace` from `./sandbox`
  - [ ] 2.1.2 Import `containsSensitiveEnvAccess` from `./bash-sandbox`
  - [ ] 2.1.3 Implement `createSandboxHook(workspacePath)` factory
  - [ ] 2.1.4 File-tool branch: check `file_path` or `path` field against workspace
  - [ ] 2.1.5 Bash branch: check command against sensitive env patterns
  - [ ] 2.1.6 Return `systemMessage` on deny for agent feedback
  - [ ] 2.1.7 Return empty object on allow

- [ ] 2.2 Modify `apps/web-platform/server/agent-runner.ts`
  - [ ] 2.2.1 Import `createSandboxHook` from `./sandbox-hook`
  - [ ] 2.2.2 Add `hooks.PreToolUse` array to `query()` options with matcher `"Read|Write|Edit|Glob|Grep|Bash|NotebookRead"`
  - [ ] 2.2.3 Remove file-tool sandbox logic from `canUseTool` (the `["Read", "Write", "Edit", "Glob", "Grep"].includes(toolName)` block)
  - [ ] 2.2.4 Remove Bash env-access check from `canUseTool` (the `toolName === "Bash"` block)
  - [ ] 2.2.5 Retain AskUserQuestion review gate in `canUseTool` (unchanged)
  - [ ] 2.2.6 Retain safe-tool allowlist in `canUseTool` (unchanged)
  - [ ] 2.2.7 Retain deny-by-default in `canUseTool` (unchanged)

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/sandbox-hook.test.ts`
  - [ ] 3.1.1 Test: allow Read with file_path inside workspace
  - [ ] 3.1.2 Test: deny Read with file_path outside workspace (`/etc/passwd`)
  - [ ] 3.1.3 Test: deny Read with `../` traversal escaping workspace
  - [ ] 3.1.4 Test: deny Write with file_path outside workspace
  - [ ] 3.1.5 Test: deny Bash with `env` command (sensitive env access)
  - [ ] 3.1.6 Test: allow Bash with clean command (`ls -la`)
  - [ ] 3.1.7 Test: deny Glob with path outside workspace
  - [ ] 3.1.8 Test: allow Read with empty file_path (not outside workspace)
  - [ ] 3.1.9 Test: verify systemMessage present on deny responses
  - [ ] 3.1.10 Test: verify hookSpecificOutput.permissionDecision is "deny" on denial
  - [ ] 3.1.11 Test: NotebookRead with file_path outside workspace is denied

- [ ] 3.2 Rename `canusertool-sandbox.test.ts` to `sandbox.test.ts` (tests isPathInWorkspace, not canUseTool)
- [ ] 3.3 Run full test suite: `bun test apps/web-platform/test/`
- [ ] 3.4 Verify no regressions in existing sandbox and caching tests

## Phase 4: Cleanup

- [ ] 4.1 Run compound (`skill: soleur:compound`)
- [ ] 4.2 Commit and push
