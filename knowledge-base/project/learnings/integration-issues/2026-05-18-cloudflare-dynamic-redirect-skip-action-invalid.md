---
title: "Cloudflare `skip` Action Invalid on http_request_dynamic_redirect Phase"
category: integration-issues
tags: [cloudflare, terraform, cloudflare-rulesets, dynamic-redirect, acme, http-01]
module: web-platform/infra
problem_type: integration_issue
component: tooling
symptoms:
  - "terraform apply on cloudflare_ruleset fails with CF API error 20016"
  - "Error message: 'action skip is not allowed for phase http_request_dynamic_redirect'"
  - "ACME HTTP-01 validator request 301-redirected to HTTPS by sibling redirect rule"
root_cause: wrong_api
resolution_type: code_fix
severity: high
date: 2026-05-18
incident_ref: knowledge-base/engineering/ops/post-mortems/soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md
synced_to: [terraform-architect]
rtd_issue: https://github.com/jikig-ai/soleur/issues/4004
---

# Cloudflare `skip` Action Invalid on http_request_dynamic_redirect Phase

## Problem

Designing an ACME-aware HTTPS upgrade ruleset for `soleur.ai`, the natural Terraform/Cloudflare shape was:

1. Rule A: match `http.request.uri.path matches "^/\.well-known/acme-challenge/"` → action `skip` (exempt from downstream rules).
2. Rule B: match anything else → action `redirect` (force HTTPS).

Cloudflare's API rejected the apply with:

```
error code: 20016 — action 'skip' is not allowed for phase 'http_request_dynamic_redirect'
```

This was not caught by `terraform plan`, by the deepen-plan review, by the work-phase, or by the code-review agents — it surfaced only at apply time because the validation lives on the CF API server.

## Root Cause

The `skip` action is valid on `http_request_firewall_custom` and a handful of other phases, but Cloudflare's rules-engine phase model does not permit a `skip` action on `http_request_dynamic_redirect`. The dynamic-redirect phase's semantic is "evaluate every rule in order until one matches and returns a redirect" — there is no concept of skipping subsequent rules because the next-match-wins semantic already covers exemption.

Stated differently: a `skip` rule on the redirect phase would need to short-circuit the phase, which contradicts the phase's evaluation model.

## Solution

Express the ACME exemption as a NEGATIVE match clause INSIDE the redirect rule's expression — not as a sibling skip rule:

```terraform
# WRONG (rejected by CF API at apply time):
resource "cloudflare_ruleset" "acme_aware_https_upgrade" {
  phase = "http_request_dynamic_redirect"
  rules {
    expression = "(http.request.uri.path matches \"^/\\.well-known/acme-challenge/\")"
    action     = "skip"  # ← CF API error 20016
  }
  rules {
    expression = "(http.host eq \"soleur.ai\")"
    action     = "redirect"
    action_parameters { ... }
  }
}

# CORRECT (negative match clause in the redirect rule's expression):
resource "cloudflare_ruleset" "seo_page_redirects" {
  phase = "http_request_dynamic_redirect"
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
  }
}
```

The negative-match clause carves out the ACME validator path so plaintext HTTP requests to `/.well-known/acme-challenge/<token>` pass through to the origin (GH Pages on port 80) unredirected, satisfying the RFC 8555 §8.3 HTTP-01 precondition.

## Prevention

- Treat any redirect-phase rule design that depends on `skip` semantics as a structural error in the plan, not an implementation detail. The deepen-plan and code-review phases should flag `action: "skip"` inside a `cloudflare_ruleset` block targeting `http_request_dynamic_redirect` before apply.
- Add a Terraform precondition or `terraform validate` plugin (if available for Cloudflare) that mirrors the CF API's phase/action validity matrix, so the error surfaces locally instead of at apply.
- When designing a new CF ruleset, look up the action whitelist for the target phase before writing the rule — the matrix is documented at <https://developers.cloudflare.com/ruleset-engine/rules-language/actions/> and varies per phase.

## See Also

- [Cloudflare One User-Defined Ruleset per Zone+Phase](./2026-05-18-cloudflare-one-user-defined-ruleset-per-zone-phase.md) — sibling learning from the same recovery; explains why this rule had to be inlined into `seo_page_redirects` rather than creating a new ruleset
- [Cloudflare Proxy Hides Origin IPs from GH Pages Domain Check](./2026-05-18-cloudflare-proxy-hides-origin-ip-from-gh-pages-domain-check.md) — sibling learning from the same recovery
- [GitHub Pages + Cloudflare Custom Domain Wiring](./2026-02-16-github-pages-cloudflare-wiring-workflow.md) — broader context
- Source incident: [soleur.ai 2026-05-18 SSL outage PIR](../../../engineering/ops/post-mortems/soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md)
