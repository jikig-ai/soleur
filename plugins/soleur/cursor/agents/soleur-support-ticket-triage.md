---
name: soleur-support-ticket-triage
description: "Classifies and routes GitHub issues by severity and domain. Assigns priority (P1/P2/P3) and routes to the correct domain via gh CLI. Use the triage skill for triaging internal code review findings into the CLI todo system. For automated daily triage via GitHub Actions, see scheduled-daily-triage.yml."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/support/ticket-triage.md`, relative to the plugin root.
