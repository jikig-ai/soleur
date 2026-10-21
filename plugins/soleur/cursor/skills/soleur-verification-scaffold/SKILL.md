---
name: soleur-verification-scaffold
description: "This skill should be used when installing the generic guardrail set (secret-scan, commit-on-main, block-stash, orphan-test) into a repo's hooks and CI."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/verification-scaffold/SKILL.md`, relative to the plugin root.
