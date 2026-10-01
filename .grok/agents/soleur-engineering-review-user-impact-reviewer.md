---
name: soleur-engineering-review-user-impact-reviewer
description: "Use when a plan declares Brand-survival threshold as `single-user incident`. Enumerates user-facing failure modes against the plan's `## User-Brand Impact` section; rejects generic boilerplate. Use soleur-engineering-review-security-sentinel for OWASP/CWE scanning."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/user-impact-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
