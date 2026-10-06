---
name: soleur-eval-harness
description: "This skill provides a promptfoo eval harness that measures whether a Soleur skill or agent edit actually improves behavior, comparing a skill arm against a baseline control arm."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/eval-harness/SKILL.md`, relative to the plugin root.
