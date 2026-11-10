---
name: soleur-engineering-review-semgrep-sast
description: "Use this agent to report the review scan receipt that soleur-engineering-review-security-sentinel reads. The orchestrator already ran the deterministic scan. This seat quotes that receipt and its finding lines. It does not run semgrep or shellcheck."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/semgrep-sast.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
