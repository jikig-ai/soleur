# Brainstorm: Infra-Security Agent

**Date:** 2026-02-16
**Issue:** #100
**Status:** Complete

## What We're Building

A full-scope infrastructure security agent (`soleur:engineering:infra:infra-security`) that audits domain security posture, configures DNS records and security settings, and wires domains to services. It fills the gap between ops-research (purchases domains) and terraform-architect (provisions compute/network) where no agent handles live DNS/SSL/WAF configuration and verification.

## Why This Approach

### The Gap

During the soleur.ai domain purchase workflow, we identified that:
- **ops-advisor** tracks domain costs and registrations (ledger)
- **ops-research** researches and purchases domains (acquisition)
- **terraform-architect** generates IaC for Hetzner/AWS (compute provisioning)
- **Nobody** handles DNS records, SSL/TLS, DNSSEC, WAF, or security auditing

### Why Not Extend terraform-architect?

Terraform has Cloudflare/Route53 providers and can manage DNS records and security settings declaratively. However:

1. **Auditing is awkward in Terraform** -- checking live state requires importing resources first
2. **Verification is outside scope** -- DNS propagation checks (dig), SSL cert chain validation, DNSSEC probing aren't Terraform's strength
3. **One-off checks are overkill** -- "is DNSSEC enabled?" shouldn't require .tf state management
4. **Different mental model** -- Terraform is declarative desired state; security auditing is imperative observation

### Why One Agent, Not Two?

Considered splitting into infra-audit (read-only) and infra-config (write) agents. Rejected per the ops-advisor consolidation learning: "split when it hurts." The scope isn't large enough yet to justify two agents. Internal mode separation (audit vs. configure) achieves the same safety boundary.

## Key Decisions

1. **API-first tool strategy** -- Cloudflare REST API via curl for configuration. CLI tools (dig, nslookup, curl) for read-only auditing. No agent-browser dependency.
2. **Methodology-driven provider support** -- Agent prompt covers Cloudflare as primary provider. No formal abstraction layer. Extend by adding provider sections to the prompt when needed.
3. **Lives at `agents/engineering/infra/`** -- Alongside terraform-architect. Name: `soleur:engineering:infra:infra-security`.
4. **Inline audit output only** -- Security posture reports stay in conversation. Nothing persisted to disk or committed. Aggregated security findings in an open-source repo would be an attacker roadmap.
5. **Three operating modes:**
   - **Audit** -- Read-only security posture assessment (SSL mode, DNSSEC, headers, WAF, DNS records)
   - **Configure** -- Create/update DNS records, toggle security settings via API
   - **Wire** -- Preconfigured recipes for common patterns (GitHub Pages, Hetzner server, Cloudflare Workers)
6. **Environment variables required:** `CF_API_TOKEN`, `CF_ZONE_ID` for Cloudflare operations.

## Scope

### In Scope
- DNS record management (A, AAAA, CNAME, TXT, MX)
- SSL/TLS mode configuration and verification
- DNSSEC enablement and validation
- HSTS and security header checks
- WAF rule overview
- Bot protection status
- GitHub Pages / Hetzner / Workers wiring recipes
- DNS propagation verification (dig)
- SSL certificate chain validation

### Out of Scope
- IaC generation (terraform-architect's domain)
- Domain purchase or registration (ops-research's domain)
- Cost tracking (ops-advisor's domain)
- Application-level security (security-sentinel's domain)
- Cloudflare Workers code deployment
- Email routing configuration (future scope)

## Open Questions

- Should the agent auto-detect the DNS provider from nameserver records, or require explicit provider specification?
- Should wire recipes be hardcoded in the prompt or loaded from a config file?
- What's the minimum Cloudflare API token scope needed? (Likely: Zone.DNS read/write + Zone.Settings read/write)
