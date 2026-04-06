---
adr: ADR-006
title: Terraform Remote Backend on Cloudflare R2
status: active
date: 2026-03-27
---

# ADR-006: Terraform Remote Backend on Cloudflare R2

## Context

Both Terraform stacks used local backend with no locking and no backup. State was lost (issue #967). Need reliable, versioned remote state.

## Decision

Cloudflare R2 as remote backend with bucket versioning. Single bucket `soleur-terraform-state` with per-app key paths (e.g., `web-platform/terraform.tfstate`). Doppler-first secrets (only DOPPLER_TOKEN in GitHub Secrets, rest pulled at runtime). Every new Terraform root must include R2 remote backend block.

## Consequences

State loss eliminated via bucket versioning. Per-app key paths enable clean multi-stack management. Zero egress cost (R2 has free egress). Requires `terraform import` for existing resources during migration.
