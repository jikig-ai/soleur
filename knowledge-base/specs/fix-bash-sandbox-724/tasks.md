# Tasks: fix Bash sandbox in canUseTool callback

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/server/agent-runner.ts` to confirm current `canUseTool` implementation
- [ ] 1.2 Read `apps/web-platform/server/workspace.ts` to confirm `DEFAULT_SETTINGS` with `permissions.allow`
- [ ] 1.3 Read `apps/web-platform/test/workspace.test.ts` to understand existing test patterns
- [ ] 1.4 Read `apps/web-platform/Dockerfile` to confirm current `apt-get install` line

## Phase 2: Dockerfile

- [ ] 2.1 Update `apps/web-platform/Dockerfile` to install `bubblewrap socat` alongside `git`
  - [ ] 2.1.1 Change the `apt-get install` line in runner stage to: `apt-get install -y --no-install-recommends git bubblewrap socat`

## Phase 3: Core Implementation

- [ ] 3.1 Create `apps/web-platform/server/bash-sandbox.ts` with `containsSensitiveEnvAccess()` function
  - [ ] 3.1.1 Define `SENSITIVE_ENV_PATTERNS` regex array (`\benv\b`, `\bprintenv\b`, `\bset\b(?!\s+-)`, `$SUPABASE_`, `$ANTHROPIC_`, `$BYOK_`, `/proc/self/environ`)
  - [ ] 3.1.2 Export `containsSensitiveEnvAccess(command: string): boolean` function
- [ ] 3.2 Update `apps/web-platform/server/agent-runner.ts` `query()` options
  - [ ] 3.2.1 Add `sandbox` configuration: `enabled: true`, `autoAllowBashIfSandboxed: true`, `allowUnsandboxedCommands: false`
  - [ ] 3.2.2 Add sandbox `network` config: `allowedDomains: []`, `allowManagedDomainsOnly: true`
  - [ ] 3.2.3 Add sandbox `filesystem` config: `allowWrite: [workspacePath]`, `denyRead` for other workspaces
  - [ ] 3.2.4 Add `disallowedTools: ["WebSearch", "WebFetch"]`
  - [ ] 3.2.5 Narrow `env` option: replace `{ ...process.env, ANTHROPIC_API_KEY: apiKey }` with minimal env vars (`ANTHROPIC_API_KEY`, `HOME`, `PATH`, `GIT_*`)
- [ ] 3.3 Update `apps/web-platform/server/agent-runner.ts` `canUseTool` callback
  - [ ] 3.3.1 Import `containsSensitiveEnvAccess` from `./bash-sandbox`
  - [ ] 3.3.2 Add `"Bash"` handling branch: check `containsSensitiveEnvAccess`, deny if true, allow if false
  - [ ] 3.3.3 Add `"Agent"` handling branch: return allow (subagents inherit sandbox)
  - [ ] 3.3.4 Add deny-by-default fallback: return `{ behavior: "deny", message: "Tool not permitted in this environment" }` for unrecognized tools
- [ ] 3.4 Update `apps/web-platform/server/workspace.ts`
  - [ ] 3.4.1 Change `DEFAULT_SETTINGS.permissions.allow` from `["Read", "Glob", "Grep"]` to `[]`
  - [ ] 3.4.2 Add `sandbox: { enabled: true }` to `DEFAULT_SETTINGS`

## Phase 4: Testing

- [ ] 4.1 Create `apps/web-platform/test/bash-sandbox.test.ts`
  - [ ] 4.1.1 Test: `env` command is detected as sensitive env access
  - [ ] 4.1.2 Test: `printenv` command is detected as sensitive env access
  - [ ] 4.1.3 Test: `echo $SUPABASE_SERVICE_ROLE_KEY` is detected
  - [ ] 4.1.4 Test: `echo ${ANTHROPIC_API_KEY}` is detected
  - [ ] 4.1.5 Test: `cat /proc/self/environ` is detected
  - [ ] 4.1.6 Test: `echo $BYOK_ENCRYPTION_KEY` is detected
  - [ ] 4.1.7 Test: `ls -la` is not flagged (allowed)
  - [ ] 4.1.8 Test: `git status` is not flagged (allowed)
  - [ ] 4.1.9 Test: `set -euo pipefail` is not flagged (allowed -- set with flags)
  - [ ] 4.1.10 Test: `echo hello` is not flagged (allowed)
- [ ] 4.2 Update `apps/web-platform/test/workspace.test.ts`
  - [ ] 4.2.1 Update assertion: `permissions.allow` should be empty array `[]`
  - [ ] 4.2.2 Add assertion: `sandbox.enabled` should be `true`
- [ ] 4.3 Run full test suite: `cd apps/web-platform && npx vitest run`

## Phase 5: Docker Verification

- [ ] 5.1 Build Docker image and verify `bwrap --version` succeeds
- [ ] 5.2 Test sandbox in Docker: verify bubblewrap works (may need `enableWeakerNestedSandbox: true` fallback)
