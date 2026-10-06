---
name: soleur-legal-audit
description: "This skill should be used when auditing existing legal documents for compliance gaps, outdated clauses, missing disclosures, and cross-document consistency. It scans a project for legal documents and displays findings inline."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/legal-audit/SKILL.md`, relative to the plugin root.
