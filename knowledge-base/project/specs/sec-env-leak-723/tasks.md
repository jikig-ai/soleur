# Tasks: fix env leak in agent subprocess (#723)

## Phase 1: Implementation

- [ ] 1.1 Add `AGENT_ENV_ALLOWLIST` constant to `apps/web-platform/server/agent-runner.ts` (HOME, PATH, NODE_ENV, LANG, LC_ALL, TERM, USER, SHELL, TMPDIR, HTTP_PROXY, HTTPS_PROXY, NO_PROXY)
- [ ] 1.2 Add `AGENT_ENV_OVERRIDES` constant with hardcoded values (DISABLE_AUTOUPDATER=1, DISABLE_TELEMETRY=1, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1)
- [ ] 1.3 Add exported `buildAgentEnv(apiKey: string)` function to `apps/web-platform/server/agent-runner.ts`
- [ ] 1.4 Replace `env: { ...process.env, ANTHROPIC_API_KEY: apiKey }` with `env: buildAgentEnv(apiKey)` at line 158

## Phase 2: Testing

- [ ] 2.1 Create `apps/web-platform/test/agent-env.test.ts` with unit tests for `buildAgentEnv`
  - [ ] 2.1.1 Test: output contains `ANTHROPIC_API_KEY` with the provided value
  - [ ] 2.1.2 Test: output contains allowlisted vars (`HOME`, `PATH`, `NODE_ENV`) when present in `process.env`
  - [ ] 2.1.3 Test: exhaustive deny-list -- iterate `SERVER_SECRETS` array and assert none appear in output
  - [ ] 2.1.4 Test: output omits allowlisted vars that are undefined in `process.env`
  - [ ] 2.1.5 Test: output contains no keys beyond allowlist + overrides + `ANTHROPIC_API_KEY`
  - [ ] 2.1.6 Test: hardcoded overrides are always present (`DISABLE_AUTOUPDATER`, `DISABLE_TELEMETRY`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`)
  - [ ] 2.1.7 Test: proxy vars forwarded when present (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`)
  - [ ] 2.1.8 Test: `CLAUDECODE` not forwarded even when set in `process.env`
- [ ] 2.2 Run existing test suite to verify no regressions: `cd apps/web-platform && npx vitest run`

## Phase 3: Verification

- [ ] 3.1 Run compound skill before commit
- [ ] 3.2 Commit with message referencing #723
- [ ] 3.3 Push and create PR with `Closes #723` in body
