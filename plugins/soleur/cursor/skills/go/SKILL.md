---
name: go
description: "This skill is the unified entry point that classifies intent and routes to the right workflow skill"
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `commands/go.md`, relative to the plugin root.
