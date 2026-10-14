---
name: soleur-dhh-rails-style
description: "This skill should be used when writing Ruby and Rails code in DHH's 37signals style: REST purity, fat models, thin controllers, Current attributes, Hotwire patterns."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/dhh-rails-style/SKILL.md`, relative to the plugin root.
