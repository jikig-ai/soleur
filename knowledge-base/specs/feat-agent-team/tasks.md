# Tasks: Agent Teams in /soleur:work

**Issue:** #26
**Plan:** `knowledge-base/plans/2026-02-10-feat-agent-teams-work-integration-plan.md`

## Phase 1: Implementation

### 1.1 Add Agent Teams block to work.md

- [ ] Insert Agent Teams block (Step 0) before existing subagent block (Step 1) in Phase 2
- [ ] Step 0.1: Environment gate (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) + independence analysis
- [ ] Step 0.2: Consent prompt via AskUserQuestion (teammate count, assignments, ~7x cost note)
- [ ] Step 0.3: ATDD -- lead writes acceptance tests before spawning teammates
- [ ] Step 0.4: Team initialization (`spawnTeam`) + teammate spawning (Task tool with `team_name`)
- [ ] Step 0.5: Monitor (`TaskList`), coordinate (`write`/`broadcast`), retry on failure, test before shutdown, incremental commits, `requestShutdown` + `cleanup`
- [ ] Renumber existing steps (current Step 1 becomes Step 1, current Step 2 becomes Step 2, etc.)

### 1.2 Write teammate spawn prompt template

- [ ] Include CLAUDE.md/constitution context reference
- [ ] Include explicit file list (FILES YOU MAY MODIFY)
- [ ] Include no-commit instructions
- [ ] Include TaskUpdate instructions for marking tasks complete
- [ ] Include messaging instructions for coordination/blocking

## Phase 2: Version Bump

### 2.1 Update plugin versioning triad

- [ ] Bump `plugins/soleur/.claude-plugin/plugin.json` version to 1.12.0
- [ ] Add entry to `plugins/soleur/CHANGELOG.md` under `[1.12.0] - 2026-02-10`
- [ ] Verify `plugins/soleur/README.md` component counts (no new commands/skills/agents)

## Phase 3: Validation

### 3.1 Manual testing

- [ ] Verify Agent Teams block is skipped when env var is not set
- [ ] Verify consent prompt appears when env var is set and 3+ independent tasks exist
- [ ] Verify decline falls through to existing subagent block
- [ ] Verify existing subagent and sequential flows are unaffected
