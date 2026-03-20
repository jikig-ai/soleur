# Tasks: sec-env-allowlist-723

## Phase 1: Core Fix

- [ ] 1.1 Read `apps/web-platform/server/agent-runner.ts`
- [ ] 1.2 Replace `env: { ...process.env, ANTHROPIC_API_KEY: apiKey }` (line 158) with allowlist: `env: { ANTHROPIC_API_KEY: apiKey, HOME: process.env.HOME, PATH: process.env.PATH }`

## Phase 2: Testing

- [ ] 2.1 Run existing test suite (`bun test` or `vitest`) to verify no regressions
- [ ] 2.2 Verify the change compiles (`bun run build:server` or `tsc --noEmit`)

## Phase 3: Validation

- [ ] 3.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2 Commit and push
