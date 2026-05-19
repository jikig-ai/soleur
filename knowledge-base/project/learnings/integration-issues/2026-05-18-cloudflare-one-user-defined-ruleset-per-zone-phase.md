---
title: "Cloudflare Allows Only ONE User-Defined Ruleset per (Zone, Phase)"
category: integration-issues
tags: [cloudflare, terraform, cloudflare-rulesets, phase-collision, infra-security]
module: web-platform/infra
problem_type: integration_issue
component: tooling
symptoms:
  - "terraform apply fails creating a second cloudflare_ruleset on a phase already owned by another ruleset"
  - "Error message: 'A similar configuration with rules already exists'"
  - "Terraform plan succeeds locally but CF API rejects at apply time"
root_cause: wrong_api
resolution_type: code_fix
severity: high
date: 2026-05-18
incident_ref: knowledge-base/engineering/ops/post-mortems/soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md
synced_to: [terraform-architect]
rtd_issue: https://github.com/jikig-ai/soleur/issues/4004
---

# Cloudflare Allows Only ONE User-Defined Ruleset per (Zone, Phase)

## Problem

The recovery plan for the 2026-05-18 soleur.ai SSL outage proposed creating a NEW `cloudflare_ruleset` resource named `acme_aware_https_upgrade` on the `http_request_dynamic_redirect` phase, alongside the existing `seo_page_redirects` ruleset on the same phase.

The Terraform apply failed with:

```
Error: A similar configuration with rules already exists
```

CF rejects the second ruleset because the zone already had a user-defined ruleset owning that phase.

## Root Cause

Cloudflare's ruleset engine permits exactly ONE user-defined `cloudflare_ruleset` per `(zone_id, phase)` tuple. The model is: CF maintains a managed system ruleset for each phase, and a single user-defined ruleset for each phase that contains all user rules for that phase in evaluation order. You cannot fan out user rules across multiple `cloudflare_ruleset` resources on the same phase.

This is documented at <https://developers.cloudflare.com/ruleset-engine/about/rules/> but is easy to miss because Terraform's `cloudflare_ruleset` resource gives no compile-time hint — the constraint is a CF API-server invariant, not a Terraform schema invariant.

## Solution

Inline new rules into the EXISTING phase-owning ruleset, in evaluation-priority order. For the 2026-05-18 recovery, the ACME-aware HTTPS upgrade rule was added as the first rule inside `seo_page_redirects` (so it evaluates before any redirect rule):

```terraform
resource "cloudflare_ruleset" "seo_page_redirects" {
  zone_id = var.zone_id
  name    = "SEO page redirects"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  # ACME-aware HTTPS upgrade — must evaluate FIRST so plaintext ACME validator
  # requests to /.well-known/acme-challenge/* reach the origin unredirected.
  rules {
    expression = <<-EOT
      (http.host eq "soleur.ai")
        and not (http.request.uri.path matches "^/\.well-known/acme-challenge/")
    EOT
    action = "redirect"
    action_parameters {
      from_value {
        target_url { expression = "concat(\"https://\", http.host, http.request.uri.path)" }
        status_code = 301
      }
    }
    description = "Force HTTPS on soleur.ai except ACME HTTP-01 validator path"
  }

  # Existing SEO redirects below ...
  rules { ... }
  rules { ... }
}
```

Rule ordering inside a ruleset is significant — CF evaluates top-down and the first match wins. The ACME-aware rule must be ahead of any catch-all redirect that would otherwise capture the validator path.

## Prevention

- Before proposing a new `cloudflare_ruleset` resource on any phase, grep the existing Terraform state for `phase = "<target-phase>"` and verify no user-defined ruleset already owns it. If one exists, the new rules must be inlined into that resource.
- Add a Terraform pre-commit/plan-time check: any `cloudflare_ruleset` resource creation should warn if another `cloudflare_ruleset` resource in the same `zone_id` declares the same `phase`.
- Update the `terraform-architect` agent's CF-ruleset section with this constraint so future plans propose inlining by default rather than creating new resources.

## See Also

- [Cloudflare Dynamic-Redirect Skip Action Invalid](./2026-05-18-cloudflare-dynamic-redirect-skip-action-invalid.md) — sibling learning from the same recovery; the `skip`-action defect made the team consider a sibling ruleset, which then collided on this constraint
- [Cloudflare Proxy Hides Origin IPs from GH Pages Domain Check](./2026-05-18-cloudflare-proxy-hides-origin-ip-from-gh-pages-domain-check.md) — sibling learning from the same recovery
- [Cloudflare Terraform v4→v5 Resource Names](../2026-03-20-cloudflare-terraform-v4-v5-resource-names.md) — related CF-Terraform schema constraint
- Source incident: [soleur.ai 2026-05-18 SSL outage PIR](../../../engineering/ops/post-mortems/soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md)
