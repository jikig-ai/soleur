---
name: soleur-legal-generate
description: "This skill should be used when generating draft legal documents for a project or company. It gathers company context interactively, invokes the soleur:legal:legal-document-generator agent, and writes markdown output."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/legal-generate/SKILL.md`, relative to the plugin root.
