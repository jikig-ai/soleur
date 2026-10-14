---
name: soleur-operations-ops-advisor
description: "Use this agent when you need to track operational expenses, manage domain registrations, or get hosting recommendations. Use soleur-operations-ops-research for live research and provider comparison; use soleur-operations-ops-provisioner for account setup; use soleur-finance-cfo for financial analysis and budgeting; use this agent for reading and updating the expense ledger."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/operations/ops-advisor.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
