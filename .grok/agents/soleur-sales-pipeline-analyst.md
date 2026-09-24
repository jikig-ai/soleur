---
name: soleur-sales-pipeline-analyst
description: "Use this agent when you need to analyze sales pipeline health, model revenue forecasts, define pipeline stage criteria, or review deal velocity metrics. Use soleur-marketing-analytics-analyst for marketing attribution and A/B testing; use this agent for post-MQL sales pipeline metrics. Use soleur-sales-cro for cross-cutting sales strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/sales/pipeline-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
