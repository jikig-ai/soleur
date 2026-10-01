---
name: soleur-engineering-review-kieran-rails-reviewer
description: "Use this agent when you need to review Rails code changes with an extremely high quality bar. Applies Kieran's strict Rails conventions and taste preferences. Use soleur-engineering-review-dhh-rails-reviewer for opinionated architectural critique; use this agent for strict convention and quality checks."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/kieran-rails-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
