# Learning: Security agents in open-source repos must output inline-only

## Problem

When designing the infra-security agent (issue #100), we needed to decide where to persist audit results -- security posture reports covering SSL/TLS mode, DNSSEC status, WAF configuration, HSTS headers, and other domain security settings.

## Solution

Audit results are output inline in the conversation only. Nothing is written to files or committed to the repository.

## Key Insight

Individual security facts (DNS records, SSL mode, DNSSEC status) are publicly queryable via dig, SSL Labs, or browser inspection. But a consolidated report that says "WAF is disabled, these security headers are missing, DNSSEC is off" is an actionable roadmap for an attacker. **The aggregation is the risk, not the individual facts.**

This applies to any security-adjacent agent or tool in an open-source repository. Options if persistence is needed:
- `.gitignore`d local directory (available locally, not committed)
- Private repository or separate tracking system
- Encrypted at rest with a project-specific key

## Tags

category: architecture-decisions
module: agents/engineering/infra
symptoms: security audit data exposure, sensitive aggregated findings in public repos
