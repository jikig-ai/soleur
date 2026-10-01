---
name: soleur-engineering-infra-terraform-architect
description: "Use this agent when you need to generate Terraform configurations or review existing .tf files for security and cost issues. Use soleur-engineering-infra-infra-security for live Cloudflare configuration and security auditing; use this agent for Terraform code generation and review."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/infra/terraform-architect.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
