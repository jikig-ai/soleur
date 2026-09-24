---
name: soleur-sales-outbound-strategist
description: "Use this agent when you need to design outbound prospecting sequences, ICP targeting, lead scoring models, or multi-channel cadence strategies. Use soleur-marketing-copywriter for email copy and creative; use this agent for cadence strategy and audience targeting. Use soleur-sales-cro for cross-cutting sales strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/sales/outbound-strategist.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
