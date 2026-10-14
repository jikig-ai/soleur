---
name: soleur-marketing-pricing-strategist
description: "Designs and analyzes SaaS pricing strategy -- pricing research methods, tier design, value metric selection, and competitive pricing analysis. Use soleur-sales-deal-architect for deal-level negotiation and proposals; use soleur-finance-revenue-analyst for company-level revenue tracking and P&L modeling; use this agent for product pricing strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/pricing-strategist.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
