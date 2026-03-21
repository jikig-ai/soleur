# Learning: SKILL.md must mirror agent command lists

## Problem

When adding the fetch-user-timeline command to x-community.sh, only the community-manager agent prompt was updated to reference the new command. The community skill's SKILL.md was not updated. Agents entering through the skill loader (rather than being invoked directly) would not know the command exists, because SKILL.md is the entry point for skill-loader discovery.

## Solution

Updated SKILL.md to list fetch-user-timeline alongside the existing commands. Both the agent prompt and SKILL.md now enumerate the same command set.

## Key Insight

When a skill exposes CLI commands that agents consume, there are two documentation surfaces: the agent prompt (which the agent reads during execution) and SKILL.md (which the skill loader reads during discovery). Adding a command to one without the other creates a split-brain: agents invoked directly know the command, but agents discovering the skill through the loader do not. Treat SKILL.md and agent prompts as a synchronized pair -- any command addition or removal must touch both files.

## Related Learnings

- `2026-02-22-new-skill-creation-lifecycle.md` -- covers the 6-file registration checklist for new skills, but not the sync requirement when adding commands to existing skills
- `2026-03-03-community-skill-missing-skill-md.md` -- notes the community skill lacked SKILL.md entirely; this learning addresses the ongoing sync obligation after SKILL.md exists

## Tags

category: agent-prompts
module: community-manager
