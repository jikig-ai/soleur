---
name: soleur:engineering:review:deployment-verification-agent
description: "Use this agent when a PR touches production data, migrations, or behavior that could silently discard or duplicate records. Produces a pre/post-deploy checklist with SQL verification queries and rollback procedures. Use data-integrity-guardian to review the migration code; use this agent to produce the deploy-day checklist."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/deployment-verification-agent.md.
