---
name: soleur-release-announce
description: "This skill should be used when announcing a new release. It parses CHANGELOG.md, generates a summary, and creates a GitHub Release. Manual releases do not trigger the CI Slack notification."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/release-announce/SKILL.md`, relative to the plugin root.
