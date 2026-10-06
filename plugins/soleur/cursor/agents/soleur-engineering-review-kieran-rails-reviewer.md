---
name: soleur-engineering-review-kieran-rails-reviewer
description: "Use this agent when you need to review Rails code changes with an extremely high quality bar. Applies Kieran's strict Rails conventions and taste preferences. Use soleur:engineering:review:dhh-rails-reviewer for opinionated architectural critique; use this agent for strict convention and quality checks."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/kieran-rails-reviewer.md`, relative to the plugin root.
