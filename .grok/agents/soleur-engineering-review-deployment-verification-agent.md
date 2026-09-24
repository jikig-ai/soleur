---
name: soleur-engineering-review-deployment-verification-agent
description: "Use this agent when a PR touches production data, migrations, or behavior that could silently discard or duplicate records. Produces a pre/post-deploy checklist with SQL verification queries and rollback procedures. Use soleur-engineering-review-data-integrity-guardian to review the migration code; use this agent to produce the deploy-day checklist."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/deployment-verification-agent.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
