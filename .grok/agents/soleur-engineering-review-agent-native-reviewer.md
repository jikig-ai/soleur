---
name: soleur-engineering-review-agent-native-reviewer
description: "Use this agent when reviewing code to ensure features are agent-native -- any action a user can take, an agent can also take, and anything a user can see, an agent can see. Enforces agent-user parity in capability and context."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/agent-native-reviewer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
