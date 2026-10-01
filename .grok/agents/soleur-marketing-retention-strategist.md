---
name: soleur-marketing-retention-strategist
description: "Designs churn prevention flows, payment recovery sequences, referral programs, and free tool strategies for customer retention and growth loops. Use soleur-sales-pipeline-analyst for deal-level expansion metrics; use soleur-marketing-cmo for overall strategy; use this agent for systematic retention programs."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/retention-strategist.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
