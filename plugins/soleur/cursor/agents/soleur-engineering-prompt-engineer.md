---
name: soleur-engineering-prompt-engineer
description: "Use this agent to author, optimize, and test prompts and agent/skill definitions -- define expected output format and success criteria, write happy/edge/failure test cases, version prompts, and remove vague qualifiers. Use the skill-creator skill for SKILL.md scaffolding and packaging, and soleur:engineering:research:best-practices-researcher for external prompt-engineering research; use this agent to engineer the prompt content itself."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/prompt-engineer.md`, relative to the plugin root.
