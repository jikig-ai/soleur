---
name: soleur-operator-digest
description: "This skill should be used when generating the operator's weekly private comprehension digest: reading merged PRs, expenses, resolved incidents, and open action-required issues, then writing a plain-language digest.md without posting."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/operator-digest/SKILL.md`, relative to the plugin root.
