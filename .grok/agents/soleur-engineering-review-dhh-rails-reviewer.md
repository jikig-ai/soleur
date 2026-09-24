---
name: soleur-engineering-review-dhh-rails-reviewer
description: "Use this agent when you need a brutally honest Rails code review from the perspective of David Heinemeier Hansson. Use soleur-engineering-review-kieran-rails-reviewer for strict convention and taste checks; use this agent for opinionated architectural critique."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/dhh-rails-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
