---
name: soleur-support-community-manager
description: "Use this agent when you need to analyze community engagement, generate digests, or assess health metrics. Reads Discord, GitHub, X/Twitter, Bluesky, LinkedIn, and Hacker News data to produce community reports. Use social-distribute for broadcasting; use this agent for monitoring."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/support/community-manager.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
