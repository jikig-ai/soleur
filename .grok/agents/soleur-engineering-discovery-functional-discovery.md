---
name: soleur-engineering-discovery-functional-discovery
description: "Use this agent when running soleur:plan to check whether community registries already have skills or agents with similar functionality to the feature being planned. Use soleur-engineering-discovery-agent-finder for stack-gap detection; use this agent to check if a planned feature already exists in registries."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/discovery/functional-discovery.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
