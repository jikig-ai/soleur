---
name: soleur-engineering-review-session-forensics-analyst
description: "Use this agent when you need a fresh-context forensic analysis of a session transcript: it reads the raw transcript (and optional run-health ledger) and produces pending-operator-only improvement proposals (workflow/agent/skill changes, error-prevention rules, operator guidance, new-component proposals, learning captures, glossary entries, test additions). It must never auto-apply. Invoke from session-retrospective-compound and similar postmortem flows. Use soleur:engineering:review:code-quality-analyst for general code quality; use this agent for session-transcript forensics."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/session-forensics-analyst.md`, relative to the plugin root.
