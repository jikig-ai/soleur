---
title: "Building an Operations Department for a One-Person Company"
date: 2026-03-10
description: "Running a company -- even solo -- requires expense tracking, domain management, hosting decisions, and infrastructure security. AI agents built a full operations function with structured documentation that survives context switches."
tags:
  - case-study
  - operations
  - company-as-a-service
---

Running a company -- even a one-person company -- requires tracking recurring expenses, managing domain registrations, configuring DNS and security settings, evaluating hosting providers, and making infrastructure procurement decisions. These are not engineering problems. They are operational logistics that a technical founder handles in spreadsheets, browser bookmarks, and memory. When the founder context-switches away from operations for two weeks, the state is lost. There is no institutional record of what was decided, what it costs, or why.

## The AI Approach

The operations domain was built as a first-class function with a domain leader (COO) and three specialist agents:

1. **COO Domain Leader** (brainstormed 2026-02-22): Orchestrates the ops domain using the 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges). Hooks into brainstorm Phase 0.5 for automatic consultation when operational decisions arise -- vendor selection, tool provisioning, expense tracking, infrastructure procurement.

2. **Ops Advisor**: Provides operational guidance on process and vendor decisions.

3. **Ops Research**: Researches hosting options, analytics solutions, domain registrars, and infrastructure providers. The analytics evaluation (Plausible vs. alternatives) and hosting decision (Hetzner CX22) were both products of this agent's research.

4. **Ops Provisioner**: Executes provisioning decisions -- domain DNS configuration, security headers, SSL settings.

The operational data lives in two structured files:

**Expense Tracker** -- A structured expense tracker with recurring and one-time costs:

| Service | Amount | Category |
|---------|--------|----------|
| GitHub Copilot Business | $10.00/mo | dev-tools |
| Hetzner CX22 | EUR 5.83/mo | hosting |
| soleur.ai domain | $70.00/yr | domain (2-year .ai TLD) |
| Plausible Analytics | $0.00 (trial), then $9/mo | saas |
| Domain registration (one-time) | $140.00 | domain |

**Domain Inventory** -- Domain inventory with DNS records and security configuration:
- 4 A records (GitHub Pages IPs), 1 CNAME (www redirect), 1 TXT (domain verification)
- Security: Full Strict SSL, HTTPS enforced, TLS 1.2 minimum, HSTS with preload, nosniff headers

## The Result

The operations domain produced:

- **Structured expense tracking** with provider, category, amount, renewal dates, and notes for every recurring cost.
- **Domain and DNS inventory** with full record-level documentation and security configuration audit.
- **Hosting decision**: Hetzner CX22 selected (2 vCPU, 4 GB RAM, 40 GB SSD, eu-central datacenter) at EUR 5.83/month -- the result of ops-research evaluating options against requirements.
- **Analytics decision**: Plausible Analytics selected as a cookie-free, GDPR-compliant analytics solution -- which directly simplified the Cookie Policy (no tracking cookies to disclose) and the GDPR Policy (no consent mechanism required for analytics).
- **Infrastructure security**: Cloudflare configuration with strict SSL, HSTS preload, and proper GitHub Pages wiring.
- **3 brainstorms** covering COO domain leader design, ops provisioner scope, and domain purchase evaluation.
- **3 archived specs** covering ops directory, ops research agent, and ops provisioner implementation.

## The Cost Comparison

A fractional COO or operations consultant for an early-stage startup charges $100-250/hour. Setting up expense tracking, evaluating hosting providers, configuring DNS and security, selecting analytics tools, and documenting infrastructure decisions is typically a 15-25 hour engagement: $1,500-6,250. An IT services firm charges $2,000-5,000 for DNS configuration, SSL setup, and security hardening. The ongoing value is in the structured documentation: when the founder returns to operations after weeks of engineering work, the institutional record is there. No context reconstruction required.

## The Compound Effect

The operations data feeds directly into other domains. The expense tracker informed the business model evaluation in the business validation document (the cost structure constrains pricing). The Plausible Analytics decision simplified three legal documents (Cookie Policy, GDPR Policy, Privacy Policy) by eliminating tracking cookies from the disclosure requirements. The Cloudflare security configuration became a learning that applies to any future domain or infrastructure provisioning. The COO domain leader now participates automatically in brainstorm sessions when operational decisions arise -- the founder does not need to remember to "check with ops" because the system routes operational questions to the right agents. The expenses file has a `last_updated` field and review cadence, so the system itself flags when the data is stale.
