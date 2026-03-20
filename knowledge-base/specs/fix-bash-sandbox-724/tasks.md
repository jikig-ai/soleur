# Tasks: fix Bash sandbox in canUseTool callback

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/server/agent-runner.ts` to confirm current `canUseTool` implementation
- [ ] 1.2 Read `apps/web-platform/server/workspace.ts` to confirm `DEFAULT_SETTINGS` with `permissions.allow`
- [ ] 1.3 Read `apps/web-platform/test/workspace.test.ts` to understand existing test patterns

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/server/bash-sandbox.ts` with `validateBashCommand()` function
  - [ ] 2.1.1 Define `BashSandboxResult` interface (`allowed`, `reason?`, `rewrittenCommand?`)
  - [ ] 2.1.2 Implement absolute path validation (deny paths outside `workspacePath`)
  - [ ] 2.1.3 Implement path traversal detection (deny `../` that escapes workspace)
  - [ ] 2.1.4 Implement sensitive env var blocking (`env`, `printenv`, `$SUPABASE_*`, `$ANTHROPIC_*`)
  - [ ] 2.1.5 Implement network exfiltration blocking (`curl`, `wget`, `nc`, `ncat`, `socat`)
  - [ ] 2.1.6 Implement command rewriting (prepend `cd <workspacePath> &&`)
  - [ ] 2.1.7 Implement process inspection blocking (`ps`, `/proc`)
- [ ] 2.2 Update `apps/web-platform/server/agent-runner.ts` `canUseTool` callback
  - [ ] 2.2.1 Import `validateBashCommand` from `./bash-sandbox`
  - [ ] 2.2.2 Add `"Bash"` handling branch that calls `validateBashCommand`
  - [ ] 2.2.3 Return `{ behavior: "deny", message }` for denied commands
  - [ ] 2.2.4 Return `{ behavior: "allow", updatedInput: { ...toolInput, command: rewrittenCommand } }` for allowed commands
  - [ ] 2.2.5 Add `disallowedTools: ["WebSearch", "WebFetch"]` to `query()` options
- [ ] 2.3 Update `apps/web-platform/server/workspace.ts`
  - [ ] 2.3.1 Change `DEFAULT_SETTINGS.permissions.allow` from `["Read", "Glob", "Grep"]` to `[]`

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/bash-sandbox.test.ts`
  - [ ] 3.1.1 Test: relative commands are allowed and rewritten with `cd` prefix
  - [ ] 3.1.2 Test: absolute paths outside workspace are denied
  - [ ] 3.1.3 Test: absolute paths inside workspace are allowed
  - [ ] 3.1.4 Test: path traversal escaping workspace is denied
  - [ ] 3.1.5 Test: `env`/`printenv`/`set` commands are denied
  - [ ] 3.1.6 Test: `$SUPABASE_*` and `$ANTHROPIC_*` variable references are denied
  - [ ] 3.1.7 Test: `curl`/`wget`/`nc` commands are denied
  - [ ] 3.1.8 Test: safe piped commands (`git log | head -5`) are allowed
  - [ ] 3.1.9 Test: `rm -rf /` is denied but `rm file.txt` (relative) is allowed
  - [ ] 3.1.10 Test: `git` commands are allowed
  - [ ] 3.1.11 Test: commands with paths to other users' workspaces are denied
- [ ] 3.2 Update `apps/web-platform/test/workspace.test.ts`
  - [ ] 3.2.1 Update assertion: `permissions.allow` should be empty array `[]`
- [ ] 3.3 Run full test suite: `cd apps/web-platform && npx vitest run`
