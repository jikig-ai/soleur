---
name: soleur-finance-revenue-analyst
description: "Use this agent when you need to track revenue, build financial forecasts, model P&L projections, or analyze revenue trends. Use soleur-sales-pipeline-analyst for deal-weighted pipeline forecasts from opportunity data; use this agent for company-level revenue analysis from aggregate data. Use soleur-finance-cfo for cross-cutting financial strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/finance/revenue-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
