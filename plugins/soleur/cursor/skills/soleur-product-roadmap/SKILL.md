---
name: soleur-product-roadmap
description: "This skill should be used when roadmapping. Sub-commands: validate (read-only roadmap-vs-GitHub-milestone drift report) and next (advisory next-action, routes to soleur:go or names an operator action)."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/product-roadmap/SKILL.md`, relative to the plugin root.
