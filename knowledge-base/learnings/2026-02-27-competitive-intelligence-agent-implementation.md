# Learning: Competitive Intelligence Agent + Skill Implementation

## Problem

Competitive intelligence was fragmented across four existing agents (`business-validator`, `growth-strategist`, `pricing-strategist`, `deal-architect`) with no dedicated owner for recurring monitoring. The Cowork Plugins platform threat was discovered 22 days late because `business-validation.md` is a point-in-time snapshot.

Needed: a `competitive-intelligence` agent for recurring scans and a `competitive-analysis` skill as both interactive and scheduled entry point.

## Solution

### Agent+Skill Split Pattern

The skill handles mode detection (interactive vs scheduled) and user prompts. The agent does all research and writing. This matches the established Soleur pattern: agents can be invoked headlessly via Task tool, skills handle the interactive layer.

### Token Budget Management (2,500-word ceiling)

Starting headroom: 52 words (2,448/2,500). New agent description needed ~28 words. Trimmed three verbose descriptions to create additional space:

- `code-simplicity-reviewer`: collapsed explanatory middle clause (49 -> ~30 words)
- `pr-comment-resolver`: removed redundant workflow explanation (49 -> ~25 words)
- `ticket-triage`: consolidated routing detail (57 -> ~45 words)

Final count: 2,433 words (67 words of headroom). **Trimming rule**: the first sentence must preserve routing signal. Secondary sentences describing the agent's own internal process are expendable because they consume budget without helping the model decide whether to route to this agent.

### Non-Interactive Invocation via `--tiers` Flag

The skill detects `$ARGUMENTS` presence. If non-empty, it checks for `--tiers` and extracts the comma-separated list, or uses defaults (0,3). This lets `soleur:schedule` cron jobs pass `--tiers 0,1,2,3` without triggering `AskUserQuestion`.

### Version Collision During Rebase

Branch was cut before main merged v3.6.0 (pencil-setup skill). During rebase, conflicts appeared in README.md, plugin.json, and CHANGELOG.md. Resolution: bumped to v3.7.0, kept main's 3.6.0 CHANGELOG entry, added ours as 3.7.0 above it.

**Key rule**: Always `git fetch origin main` and check `plugin.json` version on main before bumping. Even with this, parallel merges can still collide -- the rebase is the true resolution point.

### Multi-Agent Review Findings

Four review agents (pattern-recognition, architecture, code-simplicity, agent-native) found four P2 issues:

1. **AGENTS.md table stale** -- CPO row didn't include `competitive-intelligence`. Fix: added to the orchestrated agents list.
2. **`--tiers` flag ignored** -- Non-interactive callers silently got default tiers. Fix: added explicit flag parsing in skill Step 1.
3. **"marketingskills" opaque reference** -- Parenthetical referenced an internal learning doc that other agents have no context for. Fix: removed.
4. **AskUserQuestion sharp edge ambiguous** -- "runs autonomously in CI" was misleading since the agent also runs autonomously when invoked with arguments. Fix: clarified that interactive tier selection is the skill's responsibility.

## Key Insight

**Agent+skill pairs have a clear responsibility boundary**: the skill owns all interactive/mode-detection logic, the agent owns all domain work. This means sharp edges about `AskUserQuestion` belong on the agent (prohibition) and the skill (obligation). When review agents flag ambiguity in this boundary, it's almost always a sign that responsibility is leaking across the layer.

**Token budget trimming is a graph operation**: adding one agent requires auditing N sibling descriptions. The first sentence is sacred (routing signal), everything after is expendable. Budget violations compound -- each verbose description reduces headroom for future agents.

## Session Errors

1. **Rebase failed due to unstaged changes** -- Version bump files were modified but not committed before `git rebase origin/main`. The rebase aborted with "cannot rebase: you have unstaged changes." Fix: commit version bump files first, then rebase.
2. **Version 3.6.0 collision** -- Branch bumped to 3.6.0 but main had already merged 3.6.0 (pencil-setup). Caused merge conflicts in 3 files. Fix: bumped to 3.7.0 during conflict resolution.
3. **Skill count drift** -- After rebase, all count references said 53 skills but `find` showed 54 (main added pencil-setup). Fix: updated all 5 count locations from 53 to 54.

## Related Learnings

- [Agent Description Token Budget Optimization](./performance-issues/2026-02-20-agent-description-token-budget-optimization.md) -- 15k token ceiling, disambiguation pattern
- [Three-Way Agent Disambiguation](./2026-02-22-three-way-agent-disambiguation.md) -- disambiguation is a graph property
- [Growth Strategist Agent and Skill Development](./2026-02-19-growth-strategist-agent-skill-development.md) -- closest structural precedent for combined agent+skill
- [CI Plugin Discovery and Version Hygiene](./2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md) -- version quad, fetch main before bumping
- [Truncated CHANGELOG During Rebase](./integration-issues/2026-02-17-truncated-changelog-during-rebase-conflict-resolution.md) -- Write tool truncates large files during rebase

## Tags

category: implementation-patterns
module: product-agents
