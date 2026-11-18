---
name: soleur-session-retrospective-compound
description: "This skill should be used when running session-end retrospectives that analyze transcripts and produce improvement proposals."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/session-retrospective-compound/SKILL.md`, relative to the plugin root.
