---
name: soleur-constraint-scaffold
description: "This skill should be used when generating the Layer 1 dependency-cruiser import-boundary gate (client modules importing server secrets) into a Next.js product codebase's CI."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/constraint-scaffold/SKILL.md`, relative to the plugin root.
