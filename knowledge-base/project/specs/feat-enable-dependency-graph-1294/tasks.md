# Tasks: Enable GitHub Dependency Graph

## Phase 1: Harden dependency-review workflow

- [ ] 1.1 Add `retry-on-snapshot-warnings: true` to `.github/workflows/dependency-review.yml`
- [ ] 1.2 Verify dependency graph SBOM shows >700 packages via API check

## Phase 2: File Dependabot alert triage issue

- [ ] 2.1 Create a GitHub issue to triage the 25 Dependabot alerts surfaced by enabling the graph
- [ ] 2.2 Milestone the triage issue to Phase 2 (security milestone)

## Phase 3: Close bun.lock coverage gap

- [ ] 3.1 Generate `apps/telegram-bridge/package-lock.json` via `npm install` in that directory
- [ ] 3.2 Verify telegram-bridge dependencies appear in SBOM after next push

## Phase 4: Verification and CI enforcement

- [ ] 4.1 Push changes and verify dependency-review workflow detects actual dependency data (no "No snapshots found")
- [ ] 4.2 Add `dependency-review` to CI Required ruleset via `gh api repos/jikig-ai/soleur/rulesets/14145388`
