# Tasks: fix bun test FPE crash verification (#1511)

## Verification

- [ ] 1.1 Run `bun test` 5+ times from repo root, confirm 0 crashes and 0 failures
- [ ] 1.2 Run `bash scripts/test-all.sh`, confirm all suites pass

## Documentation Fixes

- [ ] 2.1 Update `bunfig.toml` FPE comment from "<=1.3.5" to "<=1.3.6"
- [ ] 2.2 Update learning doc `2026-03-20-bun-fpe-spawn-count-sensitivity.md` version references to include 1.3.6

## Issue Closure

- [ ] 3.1 Add resolution comment to issue #1511 documenting the three-layer fix path
- [ ] 3.2 Close issue #1511
- [ ] 3.3 Update or close draft PR #1527
