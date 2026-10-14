---
name: soleur-engineering-review-security-sentinel
description: "Use this agent when you need to perform security audits, vulnerability assessments, or security reviews of code. This includes checking for common security vulnerabilities, validating input handling, reviewing authentication/authorization implementations, scanning for hardcoded secrets, and ensuring OWASP compliance. Boundary vs gdpr-gate: see plugins/soleur/skills/review/SKILL.md §boundaries."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/security-sentinel.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
