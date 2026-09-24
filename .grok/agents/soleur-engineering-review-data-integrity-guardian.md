---
name: soleur-engineering-review-data-integrity-guardian
description: "Use this agent when you need to review database migrations, data models, or any code that manipulates persistent data. Use soleur-engineering-review-data-migration-expert for ID mapping validation; use soleur-engineering-review-deployment-verification-agent for deploy checklists. Boundary vs gdpr-gate: see plugins/soleur/skills/review/SKILL.md §boundaries."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/data-integrity-guardian.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
