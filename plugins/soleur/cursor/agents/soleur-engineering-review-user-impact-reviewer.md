---
name: soleur-engineering-review-user-impact-reviewer
description: "Use when a plan declares Brand-survival threshold as `single-user incident`. Enumerates user-facing failure modes against the plan's `## User-Brand Impact` section; rejects generic boilerplate. Use soleur:engineering:review:security-sentinel for OWASP/CWE scanning."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/user-impact-reviewer.md`, relative to the plugin root.
