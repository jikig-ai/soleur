# Tasks: fix bun test FPE crash -- close #1948

## Phase 1: Verification

- [ ] 1.1 Run `bun test` 5 consecutive times, confirm 0 failures and no SIGFPE crash
- [ ] 1.2 Run `bash scripts/test-all.sh`, confirm all suites pass (exit 0)

## Phase 2: Issue Hygiene

- [ ] 2.1 Close #1948 with resolution comment documenting:
  - [ ] 2.1.1 Three-layer defense (version pin to 1.3.11, sequential runner, dual-runner exclusion)
  - [ ] 2.1.2 Links to prior fix PRs (#860) and prior resolution (#1511)
  - [ ] 2.1.3 Current test stability results (run counts, pass counts)
  - [ ] 2.1.4 Note about optional Bun 1.3.12 upgrade after 2026-04-13

## Phase 3: Follow-up

- [ ] 3.1 Create tracking issue for Bun 1.3.12 upgrade (`chore: bump .bun-version to 1.3.12`)
  - [ ] 3.1.1 Milestone: "Post-MVP / Later"
  - [ ] 3.1.2 Body: bump after 2026-04-13 (3-day release age gate), verify tests pass, update `.bun-version`
