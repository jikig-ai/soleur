# Tasks: fix bun test FPE crash (#860)

## Phase 1: Version Pin

- [ ] 1.1 Create `.bun-version` file at repo root with content `1.3.11`
- [ ] 1.2 Verify local Bun upgrades to 1.3.11 (run `bun upgrade` or reinstall)
- [ ] 1.3 Run `bun test` from root 5 times -- confirm 0 FPE crashes

## Phase 2: Sequential Test Runner

- [ ] 2.1 Create `scripts/test-all.sh` with sequential per-directory test execution
  - [ ] 2.1.1 Add `#!/usr/bin/env bash` and `set -euo pipefail`
  - [ ] 2.1.2 Run each test directory/file separately: `test/content-publisher.test.ts`, `test/x-community.test.ts`, `test/pre-merge-rebase.test.ts`, `apps/web-platform/`, `apps/telegram-bridge/`, `plugins/soleur/`
  - [ ] 2.1.3 Print summary of pass/fail counts
- [ ] 2.2 Update `package.json` to add `"test": "bash scripts/test-all.sh"` in scripts
- [ ] 2.3 Run `bun run test` and verify all 14 test files pass

## Phase 3: Documentation

- [ ] 3.1 Update `bunfig.toml` comment to document spawn-count FPE sensitivity
- [ ] 3.2 Create learning: `knowledge-base/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
  - [ ] 3.2.1 Document version sensitivity (1.3.5 crashes, 1.3.11 stable)
  - [ ] 3.2.2 Document spawn-count correlation with crash rate
  - [ ] 3.2.3 Reference prior learnings on Bun crash patterns

## Phase 4: Verification

- [ ] 4.1 Run `bun test` from root 10 times -- 0 failures
- [ ] 4.2 Run `scripts/test-all.sh` -- all tests pass
- [ ] 4.3 Run `bun test apps/telegram-bridge/ --coverage` -- coverage thresholds met
- [ ] 4.4 Verify CI passes on the PR
