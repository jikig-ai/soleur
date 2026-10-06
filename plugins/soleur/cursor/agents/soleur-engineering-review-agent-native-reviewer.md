---
name: soleur-engineering-review-agent-native-reviewer
description: "Use this agent when reviewing code to ensure features are agent-native -- any action a user can take, an agent can also take, and anything a user can see, an agent can see. Enforces agent-user parity in capability and context."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/agent-native-reviewer.md`, relative to the plugin root.
