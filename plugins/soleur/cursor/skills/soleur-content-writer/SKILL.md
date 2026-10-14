---
name: soleur-content-writer
description: "This skill should be used when generating full article drafts with brand-consistent voice, Eleventy frontmatter, and structured data. It requires a brand guide and existing blog infrastructure."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/content-writer/SKILL.md`, relative to the plugin root.
