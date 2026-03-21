---
category: infrastructure
tags: [cloudflare, service-token, monitoring, terraform, github-actions]
date: 2026-03-21
module: web-platform/infra
problem_type: infrastructure-monitoring
---

# Learning: Cloudflare Access Service Token Expiry Monitoring

## Problem

Cloudflare Access service tokens expire silently after 1 year (default 8760h lifetime). When the `github-actions-deploy` token expires, deploys fail with HTTP 403 from Cloudflare Access -- indistinguishable from other 403 causes (Bot Fight Mode, misconfigured policy). No built-in alerting exists unless explicitly configured.

## Solution

Two-layer monitoring with a rotation runbook:

1. **Terraform `cloudflare_notification_policy`** -- Cloudflare sends email 7 days pre-expiry. Zero CI cost, runs on Cloudflare infrastructure. Note: `expiring_service_token_alert` fires for ALL tokens in the account (no per-token filtering).

2. **GitHub Actions backup workflow** (`scheduled-cf-token-expiry-check.yml`) -- Queries Cloudflare API, creates GitHub issues at 30-day threshold. Defense-in-depth against missed email notifications.

3. **Rotation runbook** (`knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`) -- Documents refresh (extend expiry), zero-downtime rotation (`client_secret_version`), and hard-cut replacement procedures.

## Key Insight

Silent credential expiry is a class of problem, not a one-off. The fix is not just monitoring one token -- it's establishing a pattern: every credential with a finite lifetime gets (1) a vendor-native alert if available, (2) an independent backup that creates issues in the team's work tracker, and (3) a rotation runbook discoverable by agents.

## Review Findings Applied

| Issue | Resolution |
|---|---|
| Issue body rendered as code block | Heredoc instead of inline string (YAML indentation becomes literal content) |
| Unsanitized API date passed to `date -d` | ISO 8601 regex validation before shell evaluation |
| Temp file left behind on failure | `mktemp` + `trap cleanup EXIT` |
| `client_id` output not marked sensitive | Added `sensitive = true` |
| Rotation steps duplicated in issue body | Simplified to summary + link to canonical runbook |

## Prevention: YAML Heredoc Indentation Pitfall

In GitHub Actions `run:` blocks, inline multi-line strings inherit YAML indentation as literal content. 10 spaces of YAML nesting = 10 leading spaces in the output = GitHub renders as a code block. Always left-align heredoc content or extract to a separate file.

## Session Errors

- `terraform validate` failed before `terraform init` in new worktree (providers not cached) -- resolved by running `init -backend=false` first
- Code quality agent false positive on Doppler comment diff (pre-existing divergence between local main and origin/main, not introduced by this PR)

## Cross-References

- Issue: #974
- Originating PR: #971 / #967
- Related learnings: `2026-03-21-cloudflare-tunnel-server-provisioning.md`, `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`, `2026-03-21-doppler-tf-var-naming-alignment.md`
- Rotation runbook: `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`

## Tags
category: infrastructure
module: web-platform/infra
