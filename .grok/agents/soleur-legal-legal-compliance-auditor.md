---
name: soleur-legal-legal-compliance-auditor
description: "Use this agent when you need to audit existing legal documents for compliance gaps, outdated clauses, missing disclosures, and cross-document consistency. Use soleur-legal-legal-document-generator to create new documents; use this agent to audit existing ones; use soleur-legal-clo for cross-cutting legal strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/legal/legal-compliance-auditor.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
