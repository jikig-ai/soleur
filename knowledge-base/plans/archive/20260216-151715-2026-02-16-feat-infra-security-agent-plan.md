---
title: "feat: infra-security agent for domain security, DNS wiring, and auditing"
type: feat
date: 2026-02-16
issue: "#100"
version_bump: MINOR
---

# feat: infra-security agent

## Overview

Create a new agent at `plugins/soleur/agents/engineering/infra/infra-security.md` that audits domain security posture, configures DNS records and security settings via Cloudflare REST API, and wires domains to services with preconfigured recipes. This fills the gap between ops-research (acquisition) and terraform-architect (IaC) where no agent manages live DNS/SSL/WAF configuration.

## Problem Statement

After purchasing soleur.ai, manual Cloudflare dashboard navigation was required for DNS records, SSL/TLS, DNSSEC, and security headers. The existing agent trio (ops-advisor, ops-research, terraform-architect) covers purchase, tracking, and IaC -- but nobody handles live infrastructure configuration or security auditing.

## Proposed Solution

Single agent matching the terraform-architect prompt structure (~100 lines) with sections for:

- **Audit Protocol** -- Read-only security posture assessment via Cloudflare API + CLI tools (dig, openssl). Severity-graded output (Critical/High/Medium/Low), matching terraform-architect's pattern.
- **Configure Protocol** -- CRUD for DNS records and security settings via Cloudflare REST API. Confirmation required before every mutation.
- **Wire Recipes** -- GitHub Pages recipe (Cloudflare-side CNAME + optional apex A records + SSL Full; instruct user for GitHub-side setup). Hetzner is just a proxied A record -- covered as a configure example, not a separate recipe. Workers deferred to v2.

## Key Decisions

- **Confirmation before mutations.** Show preview of all planned changes and wait for explicit user approval before executing any API write.
- **Graceful degradation.** Two tiers: both env vars present = full operations; missing env vars = CLI-only audit (dig, openssl). No middle tier.
- **Workers recipe deferred.** Modern Workers routing uses Custom Domains, not CNAME. Defer until actually needed.
- **Single-zone via env var.** `CF_ZONE_ID` for v1. Multi-zone via domain name lookup is a v2 concern.
- **Include proxy defaults and severity guidelines in the prompt.** Let the LLM reason about specifics; provide the general framework (web records proxied, mail DNS-only; SSL Off = Critical, no HSTS = High).

## Environment Variables

- `CF_API_TOKEN` -- Cloudflare API token (minimum scope: Zone:DNS:Edit + Zone:Settings:Read + Zone:Settings:Edit)
- `CF_ZONE_ID` -- Cloudflare Zone ID for the target domain

## Acceptance Criteria

- [ ] Agent file at `plugins/soleur/agents/engineering/infra/infra-security.md` with proper YAML frontmatter
- [ ] Description includes 3 examples (audit, configure, wire) with `<example>` + `<commentary>` tags
- [ ] Audit Protocol section with Cloudflare API queries + CLI tool fallback when env vars missing
- [ ] Configure Protocol section with confirmation-before-mutation safety rule
- [ ] GitHub Pages wire recipe (Cloudflare-side only)
- [ ] Scope section delineating boundaries with terraform-architect, security-sentinel, ops-advisor
- [ ] Plugin version bumped 2.10.2 -> 2.11.0
- [ ] CHANGELOG.md updated with v2.11.0 entry
- [ ] README.md updated: agent count 27 -> 28, Infra table updated

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `plugins/soleur/agents/engineering/infra/infra-security.md` | Create | New agent file (~100 lines) |
| `plugins/soleur/plugin.json` | Modify | Bump version 2.10.2 -> 2.11.0, update description count |
| `plugins/soleur/CHANGELOG.md` | Modify | Add v2.11.0 entry |
| `plugins/soleur/README.md` | Modify | Agent count 27 -> 28, add to Infra table |

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-16-infra-security-agent-brainstorm.md`
- Spec: `knowledge-base/specs/feat-infra-security/spec.md`
- Sibling agent (structural reference): `plugins/soleur/agents/engineering/infra/terraform-architect.md`
- Issue: #100
- Cloudflare API v4: `https://api.cloudflare.com/client/v4/`
