---
name: soleur-engineering-review-architecture-strategist
description: "Use this agent when you need to analyze code changes from an architectural perspective, evaluate system design decisions, or ensure modifications align with established architectural patterns. Use soleur:engineering:design:ddd-architect for Domain-Driven Design modeling; use this agent for general architectural compliance review."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/engineering/review/architecture-strategist.md`, relative to the plugin root.
