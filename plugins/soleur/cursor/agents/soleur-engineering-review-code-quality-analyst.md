---
name: soleur-engineering-review-code-quality-analyst
description: "Use this agent when you need a formal quality report with severity-scored findings and a prioritized refactoring roadmap. Use soleur:engineering:review:pattern-recognition-specialist for quick pattern checks; use this agent when you need a formal report to plan refactoring work."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/engineering/review/code-quality-analyst.md`, relative to the plugin root.
