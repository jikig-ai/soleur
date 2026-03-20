# Tasks: fix bun test FPE crash (#860)

## Phase 1: Version Pin

- [ ] 1.1 Create `.bun-version` file at repo root with content `1.3.11`
- [ ] 1.2 Add `"packageManager": "bun@1.3.11"` field to `package.json`
- [ ] 1.3 Upgrade local Bun: run `bun upgrade` and verify `bun --version` shows 1.3.11+
- [ ] 1.4 Run `bun test` from root 5 times -- confirm 0 FPE crashes

## Phase 2: CI DRY Improvement

- [ ] 2.1 Update `.github/workflows/ci.yml`: replace `bun-version: "1.3.11"` with `bun-version-file: ".bun-version"`
- [ ] 2.2 Update `.github/workflows/scheduled-bug-fixer.yml`: same change
- [ ] 2.3 Update `.github/workflows/scheduled-ship-merge.yml`: same change

## Phase 3: Sequential Test Runner

- [ ] 3.1 Create `scripts/test-all.sh` with:
  - [ ] 3.1.1 `#!/usr/bin/env bash` and `set -euo pipefail`
  - [ ] 3.1.2 Version check guard: compare `bun --version` against `.bun-version`, warn on mismatch
  - [ ] 3.1.3 `run_suite()` function running each directory/file separately with pass/fail tracking
  - [ ] 3.1.4 Six suites: `test/content-publisher.test.ts`, `test/x-community.test.ts`, `test/pre-merge-rebase.test.ts`, `apps/web-platform/`, `apps/telegram-bridge/`, `plugins/soleur/`
  - [ ] 3.1.5 Summary line: `N/6 suites passed`
- [ ] 3.2 Update `package.json` to add `"test": "bash scripts/test-all.sh"` in scripts
- [ ] 3.3 Run `bun run test` and verify all 14 test files pass across 6 suites

## Phase 4: Documentation

- [ ] 4.1 Update `bunfig.toml` comment to document FPE spawn-count sensitivity
- [ ] 4.2 Create learning: `knowledge-base/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
  - [ ] 4.2.1 Document the 3-crash-class taxonomy (missing deps, timer leaks, spawn count FPE)
  - [ ] 4.2.2 Document version sensitivity (1.3.5 crashes, 1.3.11 stable)
  - [ ] 4.2.3 Document spawn-count correlation with crash rate table
  - [ ] 4.2.4 Reference prior learnings and upstream issue oven-sh/bun#20429

## Phase 5: Verification

- [ ] 5.1 Run `bun test` from root 10 times -- 0 failures
- [ ] 5.2 Run `scripts/test-all.sh` -- all 6 suites pass
- [ ] 5.3 Run `bun test apps/telegram-bridge/ --coverage` -- coverage thresholds met
- [ ] 5.4 Verify CI passes on the PR (confirm `bun-version-file` reads `.bun-version` correctly)
