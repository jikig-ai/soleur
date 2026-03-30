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

## Phase 4: Synthetic check runs for bot workflows

- [ ] 4.1 Add synthetic `dependency-review` check run to `scheduled-content-publisher.yml` (alongside existing `test` and `cla-check` synthetics)
- [ ] 4.2 Push and verify content-publisher workflow still passes

## Phase 5: CI enforcement (after Phase 4 merges)

- [ ] 5.1 Push all changes, verify dependency-review workflow detects actual dependency data (no "No snapshots found")
- [ ] 5.2 Add `dependency-review` to CI Required ruleset via `gh api repos/jikig-ai/soleur/rulesets/14145388` (sequencing: must happen AFTER Phase 4 content-publisher update is merged)
