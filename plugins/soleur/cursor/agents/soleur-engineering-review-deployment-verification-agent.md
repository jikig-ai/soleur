---
name: soleur-engineering-review-deployment-verification-agent
description: "Use this agent when a PR touches production data, migrations, or behavior that could silently discard or duplicate records. Produces a pre/post-deploy checklist with SQL verification queries and rollback procedures. Use soleur:engineering:review:data-integrity-guardian to review the migration code; use this agent to produce the deploy-day checklist."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/deployment-verification-agent.md`, relative to the plugin root.
