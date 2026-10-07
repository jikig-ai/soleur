---
name: soleur-agent-native-architecture
description: "This skill should be used when designing agent-native applications where agents are first-class citizens: architecting autonomous agents, creating MCP tools, building apps where features are agent-driven outcomes."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/agent-native-architecture/SKILL.md`, relative to the plugin root.
