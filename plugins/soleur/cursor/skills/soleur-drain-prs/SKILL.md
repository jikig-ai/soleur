---
name: soleur-drain-prs
description: "This skill should be used when draining open remote GitHub PRs: triage every open pull request into mergeable tiers, confirm scope with the operator, then fix and merge the green ones. The PR-counterpart to drain-labeled-backlog."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/drain-prs/SKILL.md`, relative to the plugin root.
