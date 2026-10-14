---
name: soleur-model-launch-review
description: "This skill should be used when auditing the recurring per-Anthropic-model-release checklist (model IDs, claude-code-action pin freshness, pricing drift, tier-map re-evaluation): it auto-fixes stale model-ID swaps into a CI-gated PR and flags the rest."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/model-launch-review/SKILL.md`, relative to the plugin root.
