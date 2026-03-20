# Spec: infra-security agent

**Issue:** #100
**Branch:** feat-infra-security
**Date:** 2026-02-16

## Problem Statement

After purchasing the soleur.ai domain, there is no agent to handle live infrastructure configuration and security auditing. The existing ops agents (ops-advisor, ops-research) handle acquisition and tracking, and terraform-architect handles IaC provisioning, but nobody manages DNS records, SSL/TLS settings, DNSSEC, WAF rules, or verifies that configurations propagated correctly.

## Goals

- G1: Audit a domain's security posture (SSL, DNSSEC, headers, WAF) via API and CLI tools
- G2: Configure DNS records and security settings via Cloudflare REST API
- G3: Wire domains to services (GitHub Pages, Hetzner, Workers) with preconfigured recipes
- G4: Provide inline security reports without persisting sensitive findings to disk

## Non-Goals

- IaC generation (terraform-architect)
- Domain purchase or cost tracking (ops-research, ops-advisor)
- Application-level security review (security-sentinel)
- Email routing configuration
- Cloudflare Workers code deployment

## Functional Requirements

- FR1: Agent can query Cloudflare API for zone settings, DNS records, and security configuration
- FR2: Agent can create, update, and delete DNS records (A, AAAA, CNAME, TXT, MX)
- FR3: Agent can check and toggle SSL/TLS mode, DNSSEC, Always Use HTTPS
- FR4: Agent can verify DNS propagation using dig/nslookup
- FR5: Agent can validate SSL certificate chains using curl/openssl
- FR6: Agent provides wiring recipes for GitHub Pages, Hetzner servers, Cloudflare Workers
- FR7: Audit results are output inline in conversation only (never written to files)

## Technical Requirements

- TR1: Agent file at `plugins/soleur/agents/engineering/infra/infra-security.md`
- TR2: Requires `CF_API_TOKEN` and `CF_ZONE_ID` environment variables
- TR3: Uses Bash tool for curl (Cloudflare API), dig, nslookup, openssl s_client
- TR4: Uses WebSearch for provider documentation lookup when needed
- TR5: Follows existing agent YAML frontmatter conventions (name, description with examples, model: inherit)
- TR6: Agent name resolves to `soleur:engineering:infra:infra-security`

## Acceptance Criteria

- [ ] Agent file exists at TR1 path with proper frontmatter
- [ ] Agent can audit a Cloudflare zone's security posture given CF_API_TOKEN + CF_ZONE_ID
- [ ] Agent can create DNS records for GitHub Pages wiring
- [ ] Agent produces a formatted security checklist inline
- [ ] Agent description includes 2-3 usage examples
- [ ] Plugin version bumped, CHANGELOG and README updated
- [ ] Docs updated with new agent count
