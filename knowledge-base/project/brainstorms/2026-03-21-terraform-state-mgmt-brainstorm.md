# Terraform State Management Brainstorm

**Date:** 2026-03-21
**Status:** Approved
**Branch:** feat-terraform-state-mgmt

## What We're Building

A systematic fix for Terraform state management across both infrastructure stacks (`telegram-bridge` and `web-platform`), plus guardrails to prevent state management problems in the future.

### Problem Statement

Both Terraform stacks use the implicit local backend — no remote state, no locking, no backup. State has been lost (confirmed in #967: "Terraform state: not found on server or local machine"). Live infrastructure exists in Hetzner Cloud and Cloudflare but Terraform cannot track it. This blocks #967 (Cloudflare Tunnel server provisioning) and creates ongoing operational risk.

### Triggers

- State was lost — `terraform plan` failed because state file was missing
- #967 is blocked specifically because state is missing
- Pattern noticed across multiple issues: no remote backend, no locking, no CI for infra

## Why This Approach

### Remote Backend: Cloudflare R2

- Already in the stack (DNS, tunnels, Zero Trust) — no new vendor
- S3-compatible with zero egress fees
- Free tier (10 GB storage) covers state files indefinitely
- Encrypts at rest by default
- No native locking, but acceptable for solo operator
- Single bucket `soleur-terraform-state` with per-app key paths

**Alternatives considered:**

- Hetzner Object Storage — functionally equivalent but R2 has zero egress and existing Cloudflare account is already operationally active
- AWS S3 — only option with native `use_lockfile` locking, but adds unnecessary vendor dependency
- HCP Terraform Free — batteries-included but adds latency, vendor coupling, and 500-resource cap

### Secrets: Doppler-First

- Doppler already adopted as secrets manager (d48da30)
- Single `DOPPLER_TOKEN` in GitHub Secrets as bootstrap
- Everything else pulled from Doppler at runtime via `doppler run --`
- Eliminates split-brain between Doppler and GitHub Secrets

### Recovery: Import Existing Resources

- Both stacks have live infrastructure with no state tracking
- `terraform import` for each resource in both stacks
- Preserves current infra exactly as-is, no downtime risk

## Key Decisions

1. **Cloudflare R2 as remote backend** — single bucket, per-app key paths (`telegram-bridge/terraform.tfstate`, `web-platform/terraform.tfstate`)
2. **Enable R2 bucket versioning** — state recovery if corruption occurs
3. **Import all existing resources** — servers, volumes, firewalls, SSH keys, DNS records, tunnels
4. **Three-layer guardrails:**
   - AGENTS.md hard rule: every new Terraform root must have R2 remote backend
   - Pre-commit hooks: `terraform_fmt`, `terraform_validate`, `terraform_tflint`
   - CI `terraform plan` on PRs: Doppler-first credentials, plan posted as PR comment
5. **Doppler as canonical secrets source** — only `DOPPLER_TOKEN` in GitHub Secrets
6. **Commit `.terraform.lock.hcl`** — remove from `.gitignore` for reproducible builds
7. **Root-level gitignore** — `**/*.tfstate` as defense-in-depth

## Open Questions

1. Should drift detection be scheduled (e.g., nightly `terraform plan -detailed-exitcode`) or on-demand only?
2. When a second operator joins, should we add R2 + Cloudflare Worker locking or migrate to S3?
3. Should the CI plan job require manual approval for `terraform apply`, or auto-apply on merge to main?

## References

- [Hetzner S3 as Terraform Backend](https://community.hetzner.com/tutorials/howto-hcloud-s3-terraform-backend/)
- [Cloudflare R2 Remote Backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Terraform S3 Backend Configuration](https://developer.hashicorp.com/terraform/language/backend/s3)
- [S3 Native Locking (Terraform 1.11+)](https://www.bschaatsbergen.com/s3-native-state-locking)
- Existing learnings: `knowledge-base/project/learnings/2026-02-13-terraform-best-practices-research.md`
- Related issues: #967 (blocked on missing state), #969 (Doppler + Terraform integration)
