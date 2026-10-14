---
name: soleur-engineering-discovery-functional-discovery
description: "Use this agent when running soleur:plan to check whether community registries already have skills or agents with similar functionality to the feature being planned. Use soleur:engineering:discovery:agent-finder for stack-gap detection; use this agent to check if a planned feature already exists in registries."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/discovery/functional-discovery.md`, relative to the plugin root.
