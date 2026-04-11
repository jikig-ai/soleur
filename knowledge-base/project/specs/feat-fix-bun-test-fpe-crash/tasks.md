# Tasks: fix bun test FPE crash -- close #1948

## Phase 1: Verification

- [ ] 1.1 Run `bash scripts/test-all.sh`, confirm all suites pass (exit 0)

## Phase 2: Issue Hygiene

- [ ] 2.1 Close #1948 with resolution comment documenting:
  - [ ] 2.1.1 Explicitly state this is the same crash class as #1511 (duplicate)
  - [ ] 2.1.2 Three-layer defense (version pin to 1.3.11, sequential runner, dual-runner exclusion)
  - [ ] 2.1.3 Links to prior fix PRs (#860) and prior resolution (#1511)
  - [ ] 2.1.4 Current test stability results
