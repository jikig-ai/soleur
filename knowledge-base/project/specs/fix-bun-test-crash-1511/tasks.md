# Tasks: fix bun test FPE crash verification (#1511)

## Phase 1: Verification and Documentation

- [ ] 1.1 Run `bun test` 5+ times from repo root, confirm 0 crashes and 0 failures
- [ ] 1.2 Run `bash scripts/test-all.sh`, confirm all suites pass
- [ ] 1.3 Check if Bun version newer than 1.3.11 is available
- [ ] 1.4 Update `bunfig.toml` FPE comment if version range is inaccurate (<=1.3.5 vs <=1.3.6)
- [ ] 1.5 Update learning doc version references if inconsistent with #1511

## Phase 2: Version Update (Conditional)

- [ ] 2.1 If newer stable Bun exists: update `.bun-version`
- [ ] 2.2 Re-run full test suite after version change
- [ ] 2.3 Commit version update

## Phase 3: Issue Closure

- [ ] 3.1 Add resolution comment to issue #1511 documenting the fix path
- [ ] 3.2 Close issue #1511
- [ ] 3.3 Update or close draft PR #1527
