---
name: soleur-engineering-review-code-simplicity-reviewer
description: "Use this agent when you need a final review pass to ensure code changes are as simple and minimal as possible. Invoked after implementation to identify simplification opportunities and ensure YAGNI adherence."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/code-simplicity-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
