# Learning: Cloudflare Terraform provider v4 vs v5 resource attribute names

## Problem

When writing Cloudflare Tunnel Terraform resources against provider `~> 4.0`, used v5 attribute names from documentation and research agent output. `terraform validate` failed twice:

1. `tunnel_secret` is not a valid argument → should be `secret`
2. `ingress {}` block type is not expected → should be `ingress_rule {}`

Research agents and LLM training data defaulted to v5 naming because v5 GA docs are more prominent (published Feb 2025). The codebase pins `~> 4.0`.

## Solution

Always check the **installed provider version** before writing resources. Run `terraform validate` early and often — it catches attribute/block name mismatches immediately.

v4 → v5 renames relevant to Cloudflare Tunnel:

| v4 (current) | v5 |
|---|---|
| `secret` | `tunnel_secret` |
| `ingress_rule {}` | `ingress {}` |
| `cloudflare_record` | `cloudflare_dns_record` |
| `cloudflare_tunnel` | `cloudflare_zero_trust_tunnel_cloudflared` |

The `cloudflare_zero_trust_*` resource names work in both v4 and v5 (introduced late in v4).

## Key Insight

When research agents return Terraform resource schemas, verify against the actual provider version pinned in `main.tf`. Documentation and LLM training data skew toward the latest version. A 30-second `terraform validate` catches these mismatches before they become debugging sessions.

## Tags

category: integration-issues
module: infrastructure, terraform, cloudflare
