---
name: soleur-cf-token-scope
description: "This skill should be used to widen an existing Cloudflare API token's scope via Playwright dashboard automation, then run the ADR-130 retained-scope probe set verifying the target scope was added and none was dropped."
disable-model-invocation: true
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/cf-token-scope/SKILL.md`, relative to the plugin root.
