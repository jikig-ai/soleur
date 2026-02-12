# Learning: Plugin Loader Recurses for Agents but NOT for Skills

## Problem

When restructuring the plugin directory to support domain-first organization (`agents/engineering/review/`, `skills/engineering/atdd-developer/`), the assumption was that both agents and skills would be discovered in nested subdirectories. Moving `code-simplicity-reviewer.md` to `agents/engineering/review/` worked -- the agent was discoverable as `soleur:engineering:review:code-simplicity-reviewer`. But moving `atdd-developer/` to `skills/engineering/atdd-developer/` caused the skill to disappear from the skill list entirely.

## Solution

Only agents support nested subdirectory organization. Skills must remain flat at `skills/<name>/SKILL.md`. The plan was revised from 30 file moves (15 agents + 15 skills) to 15 agent-only moves. Skills stay at root level regardless of domain.

The approach to validate this was a Phase 0 "loader test" -- move one agent and one skill, reload, verify both are discoverable. This caught the limitation before committing 15 broken skill moves.

## Key Insight

Always test loader behavior empirically before planning large directory restructures. The plugin loader has different recursion behavior for different component types:

- **Agents:** Loader walks subdirectories recursively. Path segments become part of the subagent_type name (e.g., `agents/engineering/review/foo.md` -> `soleur:engineering:review:foo`).
- **Skills:** Loader only discovers `skills/<name>/SKILL.md` at one level of nesting. `skills/<subdir>/<name>/SKILL.md` is NOT discovered.
- **Commands:** Not tested (all already under `commands/soleur/`), but the convention is to keep them flat.

The "Phase 0 blocker test" pattern -- validating infrastructure assumptions with a single reversible move before committing to a large migration -- saved significant rework.

## Tags

category: implementation-patterns
module: plugin-architecture
symptoms: skill-not-found, skill-not-discovered, nested-directory-skill-missing
