---
name: soleur-engineering-research-framework-docs-researcher
description: "Use this agent when you need to gather documentation and best practices for specific frameworks, libraries, or dependencies. Use soleur:engineering:research:best-practices-researcher for general industry best practices; use this agent for a specific library's docs and source."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/research/framework-docs-researcher.md`, relative to the plugin root.
