---
name: soleur-legal-legal-document-generator
description: "Use this agent when you need to generate draft legal documents for a project or company. All output is clearly marked as a draft requiring professional legal review. Use soleur-legal-legal-compliance-auditor to audit existing documents; use this agent to generate new ones; use soleur-legal-clo for cross-cutting legal strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/legal/legal-document-generator.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
