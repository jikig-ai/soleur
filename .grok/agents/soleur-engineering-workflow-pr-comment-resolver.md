---
name: soleur-engineering-workflow-pr-comment-resolver
description: "Use this agent when you need to address comments on pull requests or code reviews by making the requested changes and reporting back on the resolution."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/workflow/pr-comment-resolver.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
