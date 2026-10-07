---
name: soleur-social-distribute
description: "This skill should be used when distributing a blog article across social platforms (Discord, X/Twitter, IndieHackers, Reddit, Hacker News, LinkedIn). Writes a persistent content file for automated publishing."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/social-distribute/SKILL.md`, relative to the plugin root.
