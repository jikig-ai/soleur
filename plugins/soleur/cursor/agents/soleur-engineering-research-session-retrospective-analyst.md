---
name: soleur-engineering-research-session-retrospective-analyst
description: "Fresh-context analyst that reads a session transcript and run-health ledger to produce improvement proposals. Use soleur:engineering:research:repo-research-analyst for repo structure research; use this agent for session forensics."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/research/session-retrospective-analyst.md`, relative to the plugin root.
