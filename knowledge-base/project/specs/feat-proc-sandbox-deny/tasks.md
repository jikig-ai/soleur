# Tasks: sec: add /proc to sandbox deny list

## Phase 1: Core Implementation

- [ ] 1.1 Add `/proc` to `denyRead` array in `apps/web-platform/server/agent-runner.ts:346`

## Phase 2: Testing

- [ ] 2.1 Add test case in `apps/web-platform/test/sandbox-hook.test.ts` verifying Read of `/proc/1/environ` is denied (defense-in-depth layer)
- [ ] 2.2 Run existing test suite to verify no regressions (`npx vitest run` in `apps/web-platform/`)

## Phase 3: Validation

- [ ] 3.1 Verify `denyRead` array contains both `/workspaces` and `/proc`
- [ ] 3.2 Run markdownlint on changed `.md` files
