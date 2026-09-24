---
name: soleur-sales-deal-architect
description: "Use this agent when you need to create proposals, SOWs, competitive battlecards, objection-handling playbooks, or deal negotiation frameworks. Use soleur-marketing-pricing-strategist for product pricing and tier design; use this agent for deal-level negotiation and sales collateral. Use soleur-sales-cro for cross-cutting sales strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/sales/deal-architect.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
