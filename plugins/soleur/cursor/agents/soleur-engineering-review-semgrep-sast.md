---
name: soleur-engineering-review-semgrep-sast
description: "Use this agent to report the review scan receipt that soleur:engineering:review:security-sentinel reads. The orchestrator already ran the deterministic scan. This seat quotes that receipt and its finding lines. It does not run semgrep or shellcheck."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/review/semgrep-sast.md`, relative to the plugin root.
