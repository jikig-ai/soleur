# Tasks: Pin mutable GitHub Actions tags to commit SHAs

Source plan: `knowledge-base/plans/2026-02-27-security-pin-gha-action-shas-plan.md`

## Phase 1: Pin unpinned workflows

- [x] 1.1 Update `.github/workflows/ci.yml` -- replace `actions/checkout@v4` and `oven-sh/setup-bun@v2` with pinned SHAs
- [x] 1.2 Update `.github/workflows/deploy-docs.yml` -- replace all 5 mutable action tags with pinned SHAs
- [x] 1.3 Update `.github/workflows/claude-code-review.yml` -- replace `actions/checkout@v4` and `anthropics/claude-code-action@v1` with pinned SHAs
- [x] 1.4 Update `.github/workflows/auto-release.yml` -- replace `actions/checkout@v4` with pinned SHA (discovered during deepen-plan, not in original issue)

## Phase 2: Update existing pins to latest patch

- [x] 2.1 Update `.github/workflows/scheduled-competitive-analysis.yml` -- update `actions/checkout` SHA from v4.2.2 to v4.3.1
- [x] 2.2 Update `.github/workflows/review-reminder.yml` -- update `actions/checkout` SHA from v4.2.2 to v4.3.1

## Phase 3: Verification

- [x] 3.1 Run `grep -rE '@v[0-9]+' .github/workflows/` -- confirm zero mutable tags remain
- [x] 3.2 Verify all SHAs have trailing `# vX.Y.Z` version comments
- [ ] 3.3 Open PR and confirm CI passes with pinned actions
