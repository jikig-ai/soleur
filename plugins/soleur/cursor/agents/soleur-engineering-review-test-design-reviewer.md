---
name: soleur-engineering-review-test-design-reviewer
description: "Use this agent to score test quality (Farley's 8 properties) or check a diff's new tests against the test pyramid — layer classification, e2e justification markers, fast-feedback cost signals. Produces a weighted score, a separate Pyramid verdict block, and recommendations."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/test-design-reviewer.md`, relative to the plugin root.
