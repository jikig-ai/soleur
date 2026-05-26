---
title: "Cloudflare Proxy Hides Origin IPs from GitHub Pages Domain-Config Check"
category: integration-issues
tags: [cloudflare, github-pages, dns, cert-provisioning, proxied-records, infra-security]
module: web-platform/infra
problem_type: integration_issue
component: tooling
symptoms:
  - "GitHub Pages domain-config UI shows 'DNS check successful but unavailable to your site'"
  - "Let's Encrypt cert provisioning silently never completes on the apex"
  - "dig +short soleur.ai returns 104.x.x.x / 172.x.x.x (Cloudflare anycast) instead of 185.199.108-111.153"
root_cause: config_error
resolution_type: workflow_improvement
severity: high
date: 2026-05-18
incident_ref: knowledge-base/engineering/ops/post-mortems/soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md
synced_to: [terraform-architect, infra-security]
rtd_issue: https://github.com/jikig-ai/soleur/issues/4004 https://github.com/jikig-ai/soleur/issues/4005
---

# Cloudflare Proxy Hides Origin IPs from GitHub Pages Domain-Config Check

## Problem

When `soleur.ai` apex and `www` are proxied through Cloudflare (orange-cloud), GitHub Pages' domain-configuration health check can never confirm the origin is GitHub. GH Pages performs a DNS resolution of the apex expecting one of `185.199.108.153 / 185.199.109.153 / 185.199.110.153 / 185.199.111.153`. With CF proxying enabled, the public-facing resolution returns Cloudflare anycast IPs (`104.x.x.x` or `172.x.x.x`), so GH Pages' check returns "DNS check successful but unavailable to your site" and never schedules Let's Encrypt cert provisioning for the custom domain.

Net effect during the 2026-05-18 outage recovery: GH Pages would not re-issue the expired LE cert until GH could see its own apex-record IPs at the public DNS layer.

## Root Cause

GH Pages' domain-config validator is a public-DNS dig, not an HTTP probe against `gh-pages.github.io`. CF's proxy is transparent at HTTP but opaque at DNS — it is the entire point of the proxy. There is no GH Pages flag that says "trust me, the CNAME points to GH" — the validator runs unconditionally on every cert-issuance schedule.

## Solution

Temporarily flip the 5 records (apex A x4 + `www` CNAME) to `proxied = false` (gray-cloud) for the duration of GH Pages cert provisioning. Once GH Pages reports "cert active" on the domain-config UI, flip them back to `proxied = true`.

```terraform
# Temporarily during recovery:
resource "cloudflare_record" "apex_a_1" {
  zone_id = var.zone_id
  name    = "soleur.ai"
  type    = "A"
  value   = "185.199.108.153"
  proxied = false  # <-- flip from true → false
}
# ... repeat for .109, .110, .111, and www CNAME
```

The window during which records are unproxied is short (CF dashboard reports cert-active typically within 10-20 min for GH Pages); the CF DDoS/WAF protections are temporarily off for `soleur.ai` during that window. The CF cert (edge-side TLS termination) is independent and stays valid throughout.

## Prevention

- Document the proxied/unproxied flip explicitly in the GH-Pages-CF wiring runbook so future operators do not waste hours diagnosing "DNS check successful but unavailable" as a permissions or propagation issue.
- Add a CI/Terraform plan-time guard: any apex record change for `soleur.ai` should warn if `proxied = true` is being set without a corresponding `gh_pages_cert_provisioned = true` confirmation in the plan.
- Consider migrating `soleur.ai` off GH Pages to a CF-native origin (Pages/Workers) to eliminate the proxied-vs-unproxied gymnastics permanently.

## See Also

- [GitHub Pages + Cloudflare Custom Domain Wiring](./2026-02-16-github-pages-cloudflare-wiring-workflow.md) — original wiring blockers; this learning adds the cert-renewal-time variant
- [Cloudflare Dynamic-Redirect Skip Action Invalid](./2026-05-18-cloudflare-dynamic-redirect-skip-action-invalid.md) — sibling learning from the same recovery
- [Cloudflare One User-Defined Ruleset per Zone+Phase](./2026-05-18-cloudflare-one-user-defined-ruleset-per-zone-phase.md) — sibling learning from the same recovery
- Source incident: [soleur.ai 2026-05-18 SSL outage PIR](../../../engineering/ops/post-mortems/soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md)
