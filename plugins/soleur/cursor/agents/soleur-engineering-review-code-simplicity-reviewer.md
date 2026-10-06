---
name: soleur-engineering-review-code-simplicity-reviewer
description: "Use this agent when you need a final review pass to ensure code changes are as simple and minimal as possible. Invoked after implementation to identify simplification opportunities and ensure YAGNI adherence."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/review/code-simplicity-reviewer.md`, relative to the plugin root.
