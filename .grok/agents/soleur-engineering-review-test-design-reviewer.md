---
name: soleur-engineering-review-test-design-reviewer
description: "Use this agent when you need to evaluate test quality using Dave Farley's 8 properties of good tests. It produces a weighted Test Quality Score (1-10 per property) with letter grades and prioritized improvement recommendations."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/test-design-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
