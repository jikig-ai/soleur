---
name: soleur-engineering-discovery-agent-finder
description: "Use this agent when running soleur:plan and the project uses a stack not covered by built-in agents. Queries external registries for community agents matching the detected stack gap. Use soleur-engineering-discovery-functional-discovery to check if a planned feature already exists; use this agent to find agents for a missing tech stack."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/discovery/agent-finder.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
