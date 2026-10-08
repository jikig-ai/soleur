---
name: soleur-competitive-analysis
description: "This skill should be used when running competitive intelligence scans against tracked competitors, or auditing a peer skill-library repo via peer-plugin-audit. Produces structured knowledge-base reports."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/competitive-analysis/SKILL.md`, relative to the plugin root.
