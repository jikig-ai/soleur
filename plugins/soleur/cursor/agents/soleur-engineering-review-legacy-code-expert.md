---
name: soleur-engineering-review-legacy-code-expert
description: "Use this agent when you need to safely modify legacy code that lacks tests. It applies Michael Feathers' dependency-breaking techniques from \"Working Effectively with Legacy Code\" to identify seams, plan characterization tests, and recommend safe transformation paths."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/legacy-code-expert.md`, relative to the plugin root.
