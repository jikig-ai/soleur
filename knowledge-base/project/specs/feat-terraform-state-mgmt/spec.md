# Spec: Terraform State Management

**Status:** Draft
**Branch:** feat-terraform-state-mgmt
**Brainstorm:** [2026-03-21-terraform-state-mgmt-brainstorm.md](../../brainstorms/2026-03-21-terraform-state-mgmt-brainstorm.md)
**Related Issues:** #967 (blocked on missing state), #969 (Doppler + Terraform integration)

## Problem Statement

Both Terraform stacks (`apps/telegram-bridge/infra/` and `apps/web-platform/infra/`) use the implicit local backend with no remote state storage. State has been lost, blocking #967 and creating ongoing operational risk. There are no guardrails to prevent this from recurring in new Terraform roots.

## Goals

1. Migrate both Terraform stacks to a Cloudflare R2 remote backend
2. Import all existing infrastructure resources into Terraform state
3. Establish guardrails that prevent state management regressions
4. Make Doppler the canonical secrets source for CI/CD Terraform operations

## Non-Goals

- State locking (acceptable risk for solo operator)
- Multi-environment support (staging/prod split — no staging environments exist yet)
- Migration to HCP Terraform or AWS S3
- Refactoring Terraform module structure

## Functional Requirements

- **FR1:** Both stacks store state in Cloudflare R2 bucket `soleur-terraform-state` with per-app key paths
- **FR2:** R2 bucket has versioning enabled for state recovery
- **FR3:** All existing Hetzner and Cloudflare resources are imported into state
- **FR4:** `terraform plan` runs with no changes after import (state matches reality)
- **FR5:** AGENTS.md contains a hard rule requiring remote backend in every new Terraform root
- **FR6:** Pre-commit hooks run `terraform_fmt`, `terraform_validate`, and `terraform_tflint` on infra changes
- **FR7:** CI runs `terraform plan` on PRs touching `apps/*/infra/**` and posts output as PR comment
- **FR8:** CI authenticates to Doppler via a single `DOPPLER_TOKEN` GitHub Secret; all other secrets fetched from Doppler
- **FR9:** `.terraform.lock.hcl` is committed to version control (removed from `.gitignore`)
- **FR10:** Root-level `.gitignore` includes `**/*.tfstate` and `**/*.tfstate.backup` as defense-in-depth

## Technical Requirements

- **TR1:** Terraform >= 1.10 (current CI uses 1.10.5)
- **TR2:** R2 backend uses S3-compatible configuration with required `skip_*` flags
- **TR3:** R2 API token scoped to `soleur-terraform-state` bucket with Object Read & Write permission
- **TR4:** R2 credentials stored in Doppler project, injected via `doppler run --` locally and `DOPPLER_TOKEN` in CI
- **TR5:** State migration uses `terraform init -migrate-state` (not manual copy)
- **TR6:** Pre-commit hooks use `antonbabenko/pre-commit-terraform`
- **TR7:** CI workflow uses `concurrency` groups with `cancel-in-progress: false` to prevent concurrent applies

## Acceptance Criteria

- [ ] `terraform plan` in both stacks shows "No changes" after migration
- [ ] State files exist in R2 bucket at correct key paths
- [ ] R2 bucket versioning is enabled
- [ ] AGENTS.md contains remote backend hard rule
- [ ] Pre-commit hooks run on `apps/*/infra/**` changes
- [ ] CI workflow runs `terraform plan` on infra PRs
- [ ] `.terraform.lock.hcl` is committed for both stacks
- [ ] No `.tfstate` files exist in the repository
- [ ] #967 is unblocked (state available for Cloudflare Tunnel provisioning)
