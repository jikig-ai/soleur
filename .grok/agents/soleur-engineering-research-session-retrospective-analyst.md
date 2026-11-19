---
name: soleur-engineering-research-session-retrospective-analyst
description: "Fresh-context analyst that reads a session transcript and run-health ledger to produce improvement proposals. Use soleur-engineering-research-repo-research-analyst for repo structure research; use this agent for session forensics."
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/research/session-retrospective-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
