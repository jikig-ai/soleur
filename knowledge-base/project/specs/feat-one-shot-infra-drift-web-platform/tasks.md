---
title: "Tasks: fix Cloudflare DNS record name drift"
branch: feat-one-shot-infra-drift-web-platform
date: 2026-04-03
---

# Tasks: fix Cloudflare DNS record name drift

## Phase 1: Fix

- [ ] 1.1 Update `apps/web-platform/infra/dns.tf` line 59: change `name = "@"` to `name = "soleur.ai"`

## Phase 2: Verify

- [ ] 2.1 Run `terraform init` in `apps/web-platform/infra/`
- [ ] 2.2 Run `terraform plan -detailed-exitcode` and confirm exit code 0 (no changes)

## Phase 3: Ship

- [ ] 3.1 Commit, push, create PR (Closes #1412)
- [ ] 3.2 Merge PR
- [ ] 3.3 Trigger drift detection workflow manually (`gh workflow run scheduled-terraform-drift.yml`)
- [ ] 3.4 Confirm web-platform job exits with code 0
- [ ] 3.5 Close #1412
