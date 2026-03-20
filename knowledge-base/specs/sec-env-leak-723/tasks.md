# Tasks: fix env leak in agent subprocess (#723)

## Phase 1: Implementation

- [ ] 1.1 Add `AGENT_ENV_ALLOWLIST` constant to `apps/web-platform/server/agent-runner.ts`
- [ ] 1.2 Add `buildAgentEnv(apiKey: string)` function to `apps/web-platform/server/agent-runner.ts`
- [ ] 1.3 Replace `env: { ...process.env, ANTHROPIC_API_KEY: apiKey }` with `env: buildAgentEnv(apiKey)` at line 158

## Phase 2: Testing

- [ ] 2.1 Create `apps/web-platform/test/agent-env.test.ts` with unit tests for `buildAgentEnv`
  - [ ] 2.1.1 Test: output contains `ANTHROPIC_API_KEY` with the provided value
  - [ ] 2.1.2 Test: output contains allowlisted vars (`HOME`, `PATH`, `NODE_ENV`) when present in `process.env`
  - [ ] 2.1.3 Test: output does NOT contain `SUPABASE_SERVICE_ROLE_KEY` even when set in `process.env`
  - [ ] 2.1.4 Test: output does NOT contain `BYOK_ENCRYPTION_KEY` even when set in `process.env`
  - [ ] 2.1.5 Test: output does NOT contain `STRIPE_SECRET_KEY` even when set in `process.env`
  - [ ] 2.1.6 Test: output omits allowlisted vars that are undefined in `process.env`
  - [ ] 2.1.7 Test: output contains no keys beyond allowlist + `ANTHROPIC_API_KEY`
- [ ] 2.2 Run existing test suite to verify no regressions: `cd apps/web-platform && npx vitest run`

## Phase 3: Verification

- [ ] 3.1 Run compound skill before commit
- [ ] 3.2 Commit with message referencing #723
- [ ] 3.3 Push and create PR with `Closes #723` in body
