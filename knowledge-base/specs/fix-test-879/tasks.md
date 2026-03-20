# Tasks: fix-test-879

## Phase 1: Add jq availability guard to x-community.test.ts

- [ ] 1.1 Add `HAS_JQ` constant at module scope using `Bun.spawnSync(["jq", "--version"])`
- [ ] 1.2 Add `console.warn` when `HAS_JQ` is false with install URL
- [ ] 1.3 Wrap jq transform `describe` block (line 161) with `(HAS_JQ ? describe : describe.skip)`
- [ ] 1.4 Wrap all `handle_response` describe blocks (lines 408, 435, 450, 492) with same pattern -- these source x-community.sh and call jq in pipeline
- [ ] 1.5 For script-based tests (credential/argument validation), either:
  - [ ] 1.5a (Preferred) Also skip these blocks when `!HAS_JQ` since `require_jq` fires before validation, OR
  - [ ] 1.5b Add conditional assertion: if `!HAS_JQ`, assert stderr contains `"jq is required"` instead of the validation message
- [ ] 1.6 Keep rename verification test (line 581) unconditional -- it only uses `grep`
- [ ] 1.7 Run `bun test test/x-community.test.ts` to confirm all 31 tests still pass (jq is available locally)

## Phase 2: Integrate bash tests into scripts/test-all.sh

- [ ] 2.1 Add `run_bash_suite()` helper function after existing `run_suite()` (after line 32)
- [ ] 2.2 Add bash test discovery glob loop after existing bun suites (after line 39): `for f in plugins/soleur/test/*.test.sh`
- [ ] 2.3 Run `bash scripts/test-all.sh` to confirm bash tests are discovered and pass

## Phase 3: Switch CI to scripts/test-all.sh

- [ ] 3.1 Replace `bun test` (line 25 of `.github/workflows/ci.yml`) with `bash scripts/test-all.sh`
- [ ] 3.2 Keep the telegram-bridge coverage step (lines 27-29) unchanged
- [ ] 3.3 Verify workflow syntax is valid

## Phase 4: Verification

- [ ] 4.1 Run full test suite: `bun test` from repo root (confirms no regressions)
- [ ] 4.2 Run sequential runner: `bash scripts/test-all.sh` (confirms bash tests included)
- [ ] 4.3 Push branch to trigger CI and verify workflow passes
