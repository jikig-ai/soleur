# Tasks: fix telegram-bridge health endpoint early start

## Phase 1: Setup

- [ ] 1.1 Read existing source files: `src/index.ts`, `src/health.ts`, `src/types.ts`
- [ ] 1.2 Read existing tests: `test/health.test.ts`, `test/bridge.test.ts`
- [ ] 1.3 Verify `health.ts` has zero external (npm) dependencies

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/telegram-bridge/src/main.ts`
  - [ ] 2.1.1 Import only `createHealthServer` and `HealthState` from `./health`
  - [ ] 2.1.2 Create initial `HealthState` with `cliState: "connecting"` and static values
  - [ ] 2.1.3 Call `createHealthServer(8080, healthState)` immediately
  - [ ] 2.1.4 Log health endpoint URL
  - [ ] 2.1.5 Dynamically `import("./index")` and call `boot(healthState, healthServer)`
- [ ] 2.2 Refactor `apps/telegram-bridge/src/index.ts`
  - [ ] 2.2.1 Remove `createHealthServer` import and health server creation (section 8)
  - [ ] 2.2.2 Remove `HEALTH_PORT` constant
  - [ ] 2.2.3 Remove health endpoint log line
  - [ ] 2.2.4 Export `boot(healthState, healthServer)` function
  - [ ] 2.2.5 Move `spawnCli()` call into `boot()`
  - [ ] 2.2.6 Move `bot.start()` call into `boot()`
  - [ ] 2.2.7 Wire `Object.defineProperty` getters on healthState for `cliProcess`, `cliState`, `messagesProcessed`, `messageQueue`
  - [ ] 2.2.8 Update `shutdown()` to accept and close the health server parameter
  - [ ] 2.2.9 Ensure SIGINT/SIGTERM handlers are registered inside `boot()`
- [ ] 2.3 Update `apps/telegram-bridge/Dockerfile`
  - [ ] 2.3.1 Change CMD from `src/index.ts` to `src/main.ts`
- [ ] 2.4 Update `apps/telegram-bridge/package.json`
  - [ ] 2.4.1 Change `start` script to `bun run src/main.ts`
  - [ ] 2.4.2 Change `dev` script to `bun --watch run src/main.ts`

## Phase 3: CI Workflow (Optional Optimization)

- [ ] 3.1 Reduce health check retries in `.github/workflows/telegram-bridge-release.yml`
  - [ ] 3.1.1 Use `sed` via Bash tool (Edit tool blocked on workflow files)
  - [ ] 3.1.2 Reduce from 24 to 12 attempts (60s window sufficient with early health start)

## Phase 4: Testing

- [ ] 4.1 Run existing health tests: `bun test apps/telegram-bridge/test/health.test.ts`
- [ ] 4.2 Run existing bridge tests: `bun test apps/telegram-bridge/test/bridge.test.ts`
- [ ] 4.3 Run existing helpers tests: `bun test apps/telegram-bridge/test/helpers.test.ts`
- [ ] 4.4 Run full test suite: `cd apps/telegram-bridge && bun test`
- [ ] 4.5 Run typecheck: `cd apps/telegram-bridge && bun x tsc --noEmit`
- [ ] 4.6 Verify `health.ts` still has no npm imports: `grep -c "from ['\"]" apps/telegram-bridge/src/health.ts` (should be 0 external)

## Phase 5: Validation

- [ ] 5.1 Run compound skill before commit
- [ ] 5.2 Commit and push
