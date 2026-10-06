---
name: soleur-test-browser
description: "This skill should be used when running end-to-end browser tests on pages affected by a PR. Uses agent-browser CLI to map changed files to routes and capture screenshots."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/test-browser/SKILL.md`, relative to the plugin root.
