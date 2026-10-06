---
name: soleur-provision-cloudflare
description: "This skill should be used when provisioning scoped Cloudflare API tokens for tenant deploys."
disable-model-invocation: true
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/provision-cloudflare/SKILL.md`, relative to the plugin root.
