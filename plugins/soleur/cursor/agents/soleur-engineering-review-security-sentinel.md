---
name: soleur-engineering-review-security-sentinel
description: "Use this agent when you need to perform security audits, vulnerability assessments, or security reviews of code. This includes checking for common security vulnerabilities, validating input handling, reviewing authentication/authorization implementations, scanning for hardcoded secrets, and ensuring OWASP compliance. Boundary vs gdpr-gate: see plugins/soleur/skills/review/SKILL.md §boundaries."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/review/security-sentinel.md`, relative to the plugin root.
