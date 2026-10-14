---
name: soleur-docs-site
description: "This skill should be used when scaffolding a Markdown-based documentation site using Eleventy. It generates a complete docs setup with base layout, data files, GitHub Pages deployment workflow, and passthrough copy configuration."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/docs-site/SKILL.md`, relative to the plugin root.
