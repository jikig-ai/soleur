---
name: soleur-operations-ops-research
description: "Use this agent when you need to research domains, hosting providers, tools, or find cost optimization opportunities. Use soleur-operations-ops-advisor for the expense ledger; use soleur-operations-ops-provisioner for account setup; use soleur-operations-coo for cross-cutting operations strategy; use this agent for live research and price comparison."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/operations/ops-research.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
