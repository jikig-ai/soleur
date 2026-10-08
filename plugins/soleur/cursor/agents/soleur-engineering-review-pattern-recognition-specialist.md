---
name: soleur-engineering-review-pattern-recognition-specialist
description: "Use this agent when you need to analyze code for design patterns, anti-patterns, naming conventions, and code duplication. This agent excels at identifying architectural patterns, detecting code smells, and ensuring consistency across the codebase."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/pattern-recognition-specialist.md`, relative to the plugin root.
