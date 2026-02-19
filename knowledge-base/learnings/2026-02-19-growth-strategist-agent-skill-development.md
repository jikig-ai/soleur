# Learning: Growth Strategist Agent & Skill Development

## Problem

Building the `growth-strategist` agent and `/soleur:growth` skill surfaced five non-obvious issues across testing, prompt design, UX, plugin registration, and documentation staleness.

## Solution

### 1. New agents are not loadable in the current session

Agent markdown files are discovered at plugin load time. A file created mid-session in a worktree cannot be invoked via Task tool's `subagent_type` parameter because the plugin registry is stale. **Workaround:** use a `general-purpose` agent type and embed the new agent's full instructions in the task prompt for live testing. This is sufficient for validation without restarting the session.

### 2. Sharp-edges-only prompt design

The initial plan weighed ~370 lines. Three parallel plan reviewers flagged over-specification: the prompts included general SEO knowledge, content strategy principles, and boilerplate error handling that any frontier LLM already knows. After applying feedback, the plan dropped to ~130 lines (65% reduction). **Rule:** agent prompts should contain ONLY the instructions the LLM would get wrong without them. Everything the model already knows reliably is noise that dilutes the critical constraints.

### 3. Sub-command merging for user experience

The original design had 5 sub-commands (audit, research, gaps, plan, aeo). Research, gaps, and planning are sequential steps of one workflow -- users should not have to run 3 commands to get a content plan. Merging them into a single `plan` sub-command (with `audit` and `aeo` remaining separate) reduced the surface to 3 sub-commands. **Rule:** if sub-commands are always run in sequence with no branching decisions between them, merge them.

### 4. Skills need manual SKILL_CATEGORIES registration

Agents are auto-discovered recursively from the `agents/` directory, but skills are NOT. Each skill must be manually added to `plugins/soleur/docs/_data/skills.js` in the `SKILL_CATEGORIES` map. Missing this step means the skill silently disappears from the docs site. There is no build-time error or warning.

### 5. Root README counts drift from plugin README

The root `README.md` had stale agent/skill counts ("30 agents", "38 skills") that were already behind the plugin README before this change. **Rule:** always diff root README counts against plugin README counts before committing. Do not assume they are in sync -- they have diverged multiple times historically.

## Key Insight

Agent/skill development in a plugin system has a gap between authoring and runtime: new files exist on disk but are invisible to the running session's registry. Design for this by keeping live-testability separate from final registration. More broadly, every registration surface (agent discovery, skill categories map, docs site data, root README counts) is a separate manual step -- missing any one of them produces a silent failure, not an error.

## Tags

category: integration-issues
module: plugins/soleur
symptoms: agent-not-found, over-specified-prompts, stale-counts, skill-registration-gap, sub-command-merging
