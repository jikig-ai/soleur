---
name: soleur-operations-service-automator
description: "Use this agent when you need to provision third-party services via API or MCP tools. Use soleur:operations:ops-provisioner for browser-based SaaS setup."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/operations/service-automator.md`, relative to the plugin root.
