---
name: soleur-engineering-review-data-migration-expert
description: "Use this agent when reviewing PRs that touch database migrations, data backfills, or any code that transforms production data. Use soleur:engineering:review:data-integrity-guardian for general migration safety review; use this agent specifically when ID mappings or value swaps need validation."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/data-migration-expert.md`, relative to the plugin root.
