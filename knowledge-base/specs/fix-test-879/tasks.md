# Tasks: fix-test-879

## Phase 1: Fix jq dependency guard in x-community.test.ts

- [ ] 1.1 Add `HAS_JQ` check at module scope using `Bun.spawnSync(["jq", "--version"])`
- [ ] 1.2 Wrap jq transform `describe` block with conditional skip: `(HAS_JQ ? describe : describe.skip)`
- [ ] 1.3 Add console warning when jq tests are skipped (e.g., `console.warn("jq not found, skipping jq transform tests")`)
- [ ] 1.4 Verify all other test blocks (credential validation, argument validation, handle_response, rename verification) still expect exit 1 correctly
- [ ] 1.5 Run `bun test test/x-community.test.ts` locally to confirm all tests pass

## Phase 2: Integrate bash tests into scripts/test-all.sh

- [ ] 2.1 Add `run_bash_suite` helper function to `scripts/test-all.sh`
- [ ] 2.2 Add bash test discovery loop after existing Bun test suites (find `plugins/soleur/test/*.test.sh`)
- [ ] 2.3 Run `bash scripts/test-all.sh` locally to confirm bash tests are discovered and pass

## Phase 3: Add bash tests to CI

- [ ] 3.1 Update `.github/workflows/ci.yml` to run bash tests (either via separate step or switching to `scripts/test-all.sh`)
- [ ] 3.2 Verify CI workflow syntax with `gh workflow view ci.yml`

## Phase 4: Verification

- [ ] 4.1 Run full test suite: `bun test` from repo root
- [ ] 4.2 Run sequential runner: `bash scripts/test-all.sh`
- [ ] 4.3 Simulate pre-push hook for affected test files
- [ ] 4.4 Confirm no regressions in existing tests
