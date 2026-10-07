---
name: soleur-agent-native-audit
description: "This skill should be used when conducting a scored agent-native architecture review. It launches 8 parallel sub-agents to audit action parity, context injection, CRUD completeness, capability discovery, and prompt-native features."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/agent-native-audit/SKILL.md`, relative to the plugin root.
