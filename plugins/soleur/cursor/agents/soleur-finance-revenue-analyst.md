---
name: soleur-finance-revenue-analyst
description: "Use this agent when you need to track revenue, build financial forecasts, model P&L projections, or analyze revenue trends. Use soleur:sales:pipeline-analyst for deal-weighted pipeline forecasts from opportunity data; use this agent for company-level revenue analysis from aggregate data. Use soleur:finance:cfo for cross-cutting financial strategy."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/finance/revenue-analyst.md`, relative to the plugin root.
