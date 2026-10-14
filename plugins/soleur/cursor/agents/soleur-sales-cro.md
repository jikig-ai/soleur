---
name: soleur-sales-cro
description: "Orchestrates the sales domain -- assesses revenue posture, recommends pipeline actions, and delegates to sales specialist agents. Use individual sales agents for focused tasks; use this agent for cross-cutting sales strategy and multi-agent coordination. Use soleur:finance:cfo for company-level financial analysis and budgeting."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/sales/cro.md`, relative to the plugin root.
