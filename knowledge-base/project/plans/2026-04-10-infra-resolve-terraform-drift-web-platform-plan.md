---
title: "infra: resolve Terraform infrastructure drift in web-platform"
type: fix
date: 2026-04-10
---

# infra: resolve Terraform infrastructure drift in web-platform

The Terraform drift detection workflow (run #51) found that live infrastructure
does not match the Terraform config on main. Two security hardening changes from
PR #1869 (merged 2026-04-10 12:54 UTC) were committed but never applied:

1. **DMARC policy upgrade** (`cloudflare_record.dmarc`): `p=quarantine` to
   `p=reject`. SPF is already `v=spf1 -all` (hard fail), so reject is the
   correct next step -- no legitimate email originates from `@soleur.ai`.

2. **Origin firewall lockdown** (`hcloud_firewall.web`): HTTP (80) and HTTPS
   (443) `source_ips` change from `0.0.0.0/0` + `::/0` to 15 Cloudflare IPv4
   ranges + 7 IPv6 ranges. This prevents direct origin access that bypasses
   Cloudflare WAF/DDoS protection. SSH (22) remains restricted to `admin_ips`
   and ICMP stays open.

The plan output is `0 to add, 2 to change, 0 to destroy` -- both are in-place
updates with zero downtime risk.

## Root Cause

PR #1869 updated `apps/web-platform/infra/dns.tf` and
`apps/web-platform/infra/firewall.tf` on main, but `terraform apply` was not
run after merge. The drift detection workflow correctly identified the gap
between desired state (Terraform config) and actual state (live
infrastructure).

## Acceptance Criteria

- [ ] Verify Terraform config on latest main matches the intended changes
      (DMARC reject, Cloudflare-only firewall IPs) -- no code changes needed
- [ ] Run `terraform plan` locally to confirm exactly 2 changes, 0 adds, 0
      destroys
- [ ] Run `terraform apply` to push the desired state to live infrastructure
- [ ] Verify DMARC record via DNS query shows `p=reject`
- [ ] Verify HTTP/HTTPS connectivity through Cloudflare proxy still works
      (health check)
- [ ] Close issue #1899 after successful apply

## Test Scenarios

- **DNS verify:** `dig TXT _dmarc.soleur.ai +short` expects `v=DMARC1; p=reject; rua=mailto:dmarc-reports@soleur.ai; pct=100`
- **Health check:** `curl -s -o /dev/null -w '%{http_code}' https://app.soleur.ai/health` expects `200`
- **Firewall verify:** `terraform show -json | jq '.values.root_module.resources[] | select(.address=="hcloud_firewall.web") | .values.rule[] | select(.port=="443") | .source_ips | length'` expects `22` (15 IPv4 + 7 IPv6)

## Implementation Steps

### 1. Sync to latest main

The worktree branched before PR #1869 merged. The Terraform files in the
worktree still have the old config. Since no code changes are needed (the fix
is already on main), rebase or merge main into the feature branch to get the
correct Terraform files.

```text
git fetch origin
git merge origin/main
```

### 2. Run Terraform plan

From `apps/web-platform/infra/`, run the plan with Doppler credentials to
confirm the expected 2 changes.

Per AGENTS.md, use the nested Doppler invocation pattern:

```text
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan -input=false
```

**Gate:** The plan must show exactly `0 to add, 2 to change, 0 to destroy`.
Any deviation requires investigation before proceeding.

### 3. Run Terraform apply

Apply the changes. The `-auto-approve` flag is acceptable here because the plan
was already reviewed in step 2 and the changes are pre-approved security
hardening from PR #1869.

```text
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -auto-approve -input=false
```

### 4. Verify

- DNS: `dig TXT _dmarc.soleur.ai +short`
- Health: `curl -s -o /dev/null -w '%{http_code}' https://app.soleur.ai/health`
- Re-run `terraform plan` to confirm `0 to add, 0 to change, 0 to destroy`

### 5. Close issue

```text
gh issue close 1899 --comment "Drift resolved. terraform apply completed successfully. DMARC upgraded to reject, firewall restricted to Cloudflare IPs."
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- **Terraform files:** `apps/web-platform/infra/dns.tf` (DMARC), `apps/web-platform/infra/firewall.tf` (origin firewall)
- **Related issues:** #1836 (firewall restriction, closed), #1838 (DMARC upgrade, closed)
- **PR with config changes:** #1869 (merged 2026-04-10)
- **Drift workflow:** `.github/workflows/scheduled-terraform-drift.yml`
- **Relevant learning:** `knowledge-base/project/learnings/2026-03-21-ci-terraform-plan-workflow.md` (Doppler + Terraform credential patterns)
- **Sharp edge:** Per AGENTS.md, when running Terraform locally with Doppler, export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately for the R2 backend -- the name transformer renames them to `TF_VAR_*` which the backend ignores.

## Notes

- This is TDD-exempt per AGENTS.md: "Infrastructure-only tasks (config, CI, scaffolding) are exempt."
- No code changes are needed in this branch -- the fix is already on main. The work is operational (terraform apply).
- The Cloudflare IP ranges in the firewall config match the official Cloudflare edge IP list at cloudflare.com/ips-v4/ and cloudflare.com/ips-v6/.
