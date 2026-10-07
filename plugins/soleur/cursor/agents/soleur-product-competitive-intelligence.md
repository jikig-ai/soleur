---
name: soleur-product-competitive-intelligence
description: "Use this agent when you need recurring competitive landscape monitoring and market research reports. After producing the base report, it cascades to 4 specialist agents (soleur:marketing:growth-strategist, soleur:marketing:pricing-strategist, soleur:sales:deal-architect, soleur:marketing:programmatic-seo-specialist) to refresh downstream artifacts. Use soleur:product:business-validator for one-time idea validation; use this agent for ongoing competitor tracking."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/product/competitive-intelligence.md`, relative to the plugin root.
