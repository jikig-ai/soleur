---
name: soleur-engineering-review-data-migration-expert
description: "Use this agent when reviewing PRs that touch database migrations, data backfills, or any code that transforms production data. Use soleur-engineering-review-data-integrity-guardian for general migration safety review; use this agent specifically when ID mappings or value swaps need validation."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/data-migration-expert.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
