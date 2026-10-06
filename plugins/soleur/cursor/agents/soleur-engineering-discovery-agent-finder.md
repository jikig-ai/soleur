---
name: soleur-engineering-discovery-agent-finder
description: "Use this agent when running soleur:plan and the project uses a stack not covered by built-in agents. Queries external registries for community agents matching the detected stack gap. Use soleur:engineering:discovery:functional-discovery to check if a planned feature already exists; use this agent to find agents for a missing tech stack."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/discovery/agent-finder.md`, relative to the plugin root.
