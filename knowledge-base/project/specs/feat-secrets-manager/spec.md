# Spec: Adopt Doppler as Secrets Manager

**Issue:** #734
**Branch:** feat-secrets-manager
**Date:** 2026-03-20

## Problem Statement

Credentials are scattered across 4 surfaces (GitHub Actions secrets, local `.env`, server `/mnt/data/.env`, Terraform variables) with no single source of truth. This causes secret drift after rotation, makes disaster recovery uncertain (BYOK_ENCRYPTION_KEY has no backup), leaves live credentials in plaintext on the developer machine, and requires manual multi-location updates for every rotation.

## Goals

- G1: Single source of truth for all ~25 secrets via Doppler
- G2: Runtime secret injection — no plaintext `.env` files on disk (local dev or server)
- G3: Credential rotation is a single `doppler secrets set` command
- G4: Incremental migration by surface with rollback capability at each phase
- G5: $0/mo added cost (Doppler free tier)

## Non-Goals

- Automatic secret rotation (requires Doppler Team tier at $21/mo)
- Self-hosted secrets infrastructure
- Terraform remote state backend migration (separate initiative)
- Migrating SSH keys used for CI deploy (structural, not rotatable)

## Functional Requirements

- FR1: Doppler account with project structure: 1 project, 3 environments (dev, ci, prod)
- FR2: Local dev uses `doppler run -- <command>` instead of sourcing `.env` files
- FR3: GitHub Actions workflows use `dopplerhq/cli-action` to inject secrets, replacing `secrets.*` references
- FR4: Production server uses `doppler run` at container start via systemd/Docker entrypoint
- FR5: Terraform uses `doppler run --name-transformer tf-var -- terraform apply`
- FR6: Community setup scripts (`discord-setup.sh`, `x-setup.sh`, etc.) write to Doppler instead of `.env`
- FR7: BYOK_ENCRYPTION_KEY has an offline backup before any migration begins
- FR8: Worktree manager copies Doppler config (not `.env`) to new worktrees

## Technical Requirements

- TR1: Server bootstrap credential (`DOPPLER_TOKEN`) provisioned via cloud-init user-data
- TR2: Doppler CLI installed on production server via cloud-init
- TR3: All Terraform sensitive variables marked with `sensitive = true` (verify existing)
- TR4: `.gitignore` updated: add `*.tfstate` and `*.tfvars` to web-platform infra
- TR5: Pre-commit hook or CI check to prevent `.env` files from being committed
- TR6: Existing `chmod 600` convention maintained for any files that touch credentials

## Migration Phases

| Phase | Surface | Secrets | Validation | Rollback |
|-------|---------|---------|------------|----------|
| 0 | Doppler setup | N/A | Account created, project/envs configured | Delete account |
| 1 | Local dev | ~10 | `doppler run -- env` shows all expected vars | Restore `.env` from git-ignored backup |
| 2 | CI (GitHub Actions) | ~25 | All 14 workflow files pass CI with Doppler injection | Revert workflow changes, re-add GH secrets |
| 3 | Server runtime | ~12 | Health check passes after container restart with `doppler run` | Restore `/mnt/data/.env` from Doppler export |
| 4 | Terraform | 3 | `terraform plan` succeeds with Doppler-injected vars | Pass vars via `TF_VAR_*` env vars manually |

## Risks

| Risk | Mitigation |
|------|------------|
| Doppler outage blocks deploys | Export secrets to encrypted backup periodically; keep GH Actions secrets as fallback during migration |
| Bootstrap credential leak | Single `DOPPLER_TOKEN` on server; rotate via Doppler dashboard; restrict to prod config only |
| CI migration breaks scheduled workflows | Migrate one workflow at a time; keep `secrets.*` as fallback until validated |
| Free tier limit exceeded | Current needs: 1 project, 3 envs, ~4 service tokens — well within 10/4/50 limits |
