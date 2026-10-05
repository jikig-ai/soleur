---
name: soleur-finance-financial-reporter
description: "Use this agent when you need to generate financial summaries, cash flow statements, periodic financial reports, or investor-ready financial overviews. Use soleur-finance-budget-analyst for budget planning; use soleur-finance-revenue-analyst for forecasting; use this agent for synthesizing financial data into reports. Use soleur-finance-cfo for cross-cutting financial strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/finance/financial-reporter.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
