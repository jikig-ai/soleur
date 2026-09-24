---
name: soleur-operations-ops-provisioner
description: "Use this agent when you need to set up a new SaaS tool account via browser. Use soleur-operations-service-automator for API/MCP-driven provisioning; use soleur-operations-ops-research for evaluating alternatives; use soleur-operations-ops-advisor for the expense ledger; use soleur-operations-coo for cross-cutting operations strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/operations/ops-provisioner.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
