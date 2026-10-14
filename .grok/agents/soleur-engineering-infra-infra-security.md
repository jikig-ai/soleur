---
name: soleur-engineering-infra-infra-security
description: "Use this agent when you need to audit domain security posture, configure DNS records, or manage Cloudflare security features (WAF, Workers, Zero Trust) via the Cloudflare MCP server. Use soleur-engineering-infra-terraform-architect for IaC generation; use this agent for live Cloudflare configuration and security auditing."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/infra/infra-security.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
