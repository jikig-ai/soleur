---
name: soleur-engineering-review-test-design-reviewer
description: "Use this agent to score test quality (Farley's 8 properties) or check a diff's new tests against the test pyramid — layer classification, e2e justification markers, fast-feedback cost signals. Produces a weighted score, a separate Pyramid verdict block, and recommendations."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/test-design-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
