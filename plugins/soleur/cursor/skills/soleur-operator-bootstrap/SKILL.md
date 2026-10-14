---
name: soleur-operator-bootstrap
description: "This skill should be used when a merge leaves two or more operator steps blocked on one credential: generate a runnable staged bootstrap.sh an agent runs, not a prose checklist."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/operator-bootstrap/SKILL.md`, relative to the plugin root.
