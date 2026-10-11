---
name: soleur-engineering-review-test-design-reviewer
description: "Use this agent when you need to evaluate test quality using Dave Farley's 8 properties of good tests. It produces a weighted Test Quality Score (1-10 per property) with letter grades and prioritized improvement recommendations."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/engineering/review/test-design-reviewer.md`, relative to the plugin root.
