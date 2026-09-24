---
name: soleur-finance-cfo
description: "Orchestrates the finance domain -- assesses financial posture, recommends budgeting and reporting actions, and delegates to finance specialist agents. Use individual finance agents for focused tasks; use this agent for cross-cutting financial strategy and multi-agent coordination."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/finance/cfo.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
