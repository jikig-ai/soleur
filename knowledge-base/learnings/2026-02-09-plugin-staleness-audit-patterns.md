# Learning: Plugin staleness audit patterns

## Problem

After rapid iteration on the Soleur plugin (1.0 to 1.7 in 4 days), accumulated technical debt:
- 10 agents defined but never invoked by any command
- 7 references to agents that never existed (aspirational names left in commands)
- Component counts in 3 READMEs diverged from reality
- Stale CLI references in AGENTS.md for code (src/, bun test) that was already removed
- Duplicate agent/skill for every-style-editor

## Solution

Systematic three-pronged audit using parallel research agents:
1. **Agent audit**: Cross-reference every agent definition against all commands/skills for actual usage
2. **Skill audit**: Check each SKILL.md for external dependencies, duplicates, and stale content
3. **Config audit**: Verify counts, versions, and references across all config and documentation files

Key technique: `grep` for agent names across commands/ directory to determine which agents are actually invoked vs just defined.

## Key Insight

**Agents should only exist if a command explicitly invokes them.** Defining agents "just in case" creates maintenance burden and confuses the system prompt (Claude sees all agents in its tool descriptions). The audit pattern is: for each agent, search all commands for `Task <agent-name>`. If not found, the agent is dead weight.

**Never reference aspirational agents in commands.** If an agent doesn't exist yet, don't put it in a command's parallel task list. This creates silent failures where commands reference things that can't run.

**Count verification is a triad obligation.** Every time agents/commands/skills change, three READMEs and the plugin.json must be updated. Automate or enforce this in the /ship checklist.

## Tags
category: maintenance
module: plugin
symptoms: stale-references, count-mismatch, unused-agents
