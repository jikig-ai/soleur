---
name: soleur-engineering-review-session-forensics-analyst
description: "Use this agent when you need a fresh-context forensic analysis of a session transcript: it reads the raw transcript (and optional run-health ledger) and produces pending-operator-only improvement proposals (workflow/agent/skill changes, error-prevention rules, operator guidance, new-component proposals, learning captures, glossary entries, test additions). It must never auto-apply. Invoke from session-retrospective-compound and similar postmortem flows. Use soleur-engineering-review-code-quality-analyst for general code quality; use this agent for session-transcript forensics."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/session-forensics-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
