# Tasks: fix(ci): pin bun-version in scheduled workflows

## Phase 1: Core Implementation

- [ ] 1.1 Edit `.github/workflows/scheduled-ship-merge.yml`
  - [ ] 1.1.1 Update version comment from `# v2` to `# v2.1.2` on line 43
  - [ ] 1.1.2 Add `with:` block with `bun-version: "1.3.11"` after the `uses:` line
- [ ] 1.2 Edit `.github/workflows/scheduled-bug-fixer.yml`
  - [ ] 1.2.1 Add `with:` block with `bun-version: "1.3.11"` after the `uses:` line on line 48

## Phase 2: Verification

- [ ] 2.1 Run `grep -A2 'setup-bun' .github/workflows/*.yml` to confirm all three files now pin `bun-version: "1.3.11"`
- [ ] 2.2 Validate YAML syntax with `bun run --help 2>/dev/null` or basic parse check
- [ ] 2.3 Run `bun test` to ensure no regressions in the test suite
