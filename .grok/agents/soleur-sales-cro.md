---
name: soleur-sales-cro
description: "Orchestrates the sales domain -- assesses revenue posture, recommends pipeline actions, and delegates to sales specialist agents. Use individual sales agents for focused tasks; use this agent for cross-cutting sales strategy and multi-agent coordination. Use soleur-finance-cfo for company-level financial analysis and budgeting."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/sales/cro.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
