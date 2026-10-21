---
mode: subagent
description: "Use this agent when a PR touches production data, migrations, or behavior that could silently discard or duplicate records. Produces a pre/post-deploy checklist with SQL verification queries and rollback procedures. Use soleur:engineering:review:data-integrity-guardian to review the migration code; use this agent to produce the deploy-day checklist."
---

Stub for the canonical agent `soleur:engineering:review:deployment-verification-agent`. OpenCode derives an agent's id from this
file's path, so the canonical `name:` frontmatter is deliberately not repeated here.

Read and follow the canonical agent definition at `__SOLEUR_PLUGIN_ROOT__/agents/engineering/review/deployment-verification-agent.md`,
then work as that agent.
