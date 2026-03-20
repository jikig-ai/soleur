# Tasks: Standardize claude-code-action SHA

Plan: `knowledge-base/plans/2026-03-20-chore-standardize-claude-code-action-sha-plan.md`
Issue: #809

## Phase 1: Verify Target SHA

- [ ] 1.1 Re-verify v1 tag SHA at implementation time: `gh api repos/anthropics/claude-code-action/git/refs/tags/v1` then dereference annotated tag
- [ ] 1.2 Confirm latest release version matches plan (v1.0.75 / `df37d2f0760a4b5683a6e617c9325bc1a36443f6`)
- [ ] 1.3 If SHA has changed, update the sed commands accordingly

## Phase 2: Replace SHAs

- [ ] 2.1 Run Group A sed: replace `64c7a0ef71df67b14cb4471f4d9c8565c61042bf # v1` in 7 files
  - [ ] 2.1.1 `.github/workflows/scheduled-bug-fixer.yml`
  - [ ] 2.1.2 `.github/workflows/scheduled-ship-merge.yml`
  - [ ] 2.1.3 `.github/workflows/scheduled-content-generator.yml`
  - [ ] 2.1.4 `.github/workflows/scheduled-growth-execution.yml`
  - [ ] 2.1.5 `.github/workflows/test-pretooluse-hooks.yml`
  - [ ] 2.1.6 `.github/workflows/scheduled-daily-triage.yml`
  - [ ] 2.1.7 `.github/workflows/scheduled-seo-aeo-audit.yml`
- [ ] 2.2 Run Group B sed: replace `1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63` in 5 files
  - [ ] 2.2.1 `.github/workflows/scheduled-growth-audit.yml`
  - [ ] 2.2.2 `.github/workflows/scheduled-community-monitor.yml`
  - [ ] 2.2.3 `.github/workflows/scheduled-campaign-calendar.yml`
  - [ ] 2.2.4 `.github/workflows/claude-code-review.yml`
  - [ ] 2.2.5 `.github/workflows/scheduled-competitive-analysis.yml`

## Phase 3: Verification

- [ ] 3.1 Grep for old SHAs -- zero matches expected
- [ ] 3.2 Grep for new SHA -- 12 matches expected
- [ ] 3.3 YAML syntax validation on all 12 modified files
- [ ] 3.4 `git diff --stat` to confirm exactly 12 files changed

## Phase 4: Ship

- [ ] 4.1 Run `soleur:compound` before commit
- [ ] 4.2 Commit with `chore(ci): standardize claude-code-action to v1.0.75 SHA`
- [ ] 4.3 Push and create PR with `Closes #809` in body
- [ ] 4.4 Queue auto-merge and poll until merged
