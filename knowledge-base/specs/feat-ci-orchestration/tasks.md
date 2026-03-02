# Tasks: CI Orchestration

## Phase 1: Core Implementation

- [ ] 1.1 Read current `competitive-intelligence.md` agent body to understand Phase 1 structure
- [ ] 1.2 Add Phase 2: Cascade section after Phase 1 in the agent body
  - [ ] 1.2.1 Cross-domain acknowledgment note
  - [ ] 1.2.2 Cascade delegation table (4 specialists)
  - [ ] 1.2.3 Task prompt template with scoped instructions
  - [ ] 1.2.4 Failure handling instructions
  - [ ] 1.2.5 Cascade Results section format and replace-on-rerun logic

## Phase 2: Workflow Update

- [ ] 2.1 Update `scheduled-competitive-analysis.yml` timeout-minutes from 30 to 45
- [ ] 2.2 Update `scheduled-competitive-analysis.yml` max-turns from 30 to 45

## Phase 3: Version Bump

- [ ] 3.1 Bump PATCH version in `plugin.json`
- [ ] 3.2 Update `CHANGELOG.md` with cascade feature
- [ ] 3.3 Verify `README.md` counts (no new components)
- [ ] 3.4 Sync `marketplace.json` version
- [ ] 3.5 Sync root `README.md` badge
- [ ] 3.6 Sync `bug_report.yml` placeholder
