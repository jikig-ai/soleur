# Tasks: Agent Teams in /soleur:work

**Issue:** #26
**Plan:** `knowledge-base/plans/2026-02-10-feat-agent-teams-work-integration-plan.md`

## Phase 1: Implementation

### 1.1 Restructure Phase 2 section 1 as tiered execution mode selection

- [x] Rename "Parallel Execution (optional)" to "Execution Mode Selection"
- [x] Wrap existing subagent block as "Tier B: Subagent Fan-Out"
- [x] Add "Tier A: Agent Teams" block before Tier B (4 steps: check, ask, do, finish)
- [x] Add "Tier C: Sequential" label on the existing fallthrough to task loop
- [x] Include `spawnTeam` failure handling (cleanup stale, retry, fall through)
- [x] Include teammate spawn prompt template with file list and no-commit instructions

## Phase 2: Version Bump

### 2.1 Update plugin versioning triad

- [x] Bump `plugins/soleur/.claude-plugin/plugin.json` to 1.13.0
- [x] Add `[1.13.0]` entry to `plugins/soleur/CHANGELOG.md`
- [x] Verify `plugins/soleur/README.md` counts (no new commands/skills/agents)

## Phase 3: Validation

### 3.1 Manual testing

- [ ] Verify Tier A skipped when env var not set
- [ ] Verify consent prompt appears when env var set + 3+ independent tasks
- [ ] Verify decline falls through to Tier B (subagent block)
- [ ] Verify existing Tier B and Tier C flows unaffected
