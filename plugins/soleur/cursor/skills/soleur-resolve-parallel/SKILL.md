---
name: soleur-resolve-parallel
description: "This skill should be used when resolving all TODO comments in the codebase using parallel processing. It analyzes dependencies, creates a resolution plan with a mermaid flow diagram, and spawns parallel resolver agents."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/resolve-parallel/SKILL.md`, relative to the plugin root.
