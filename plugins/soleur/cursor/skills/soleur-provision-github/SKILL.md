---
name: soleur-provision-github
description: "This skill should be used when provisioning GitHub repos and environments for tenant workflows."
disable-model-invocation: true
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/provision-github/SKILL.md`, relative to the plugin root.
