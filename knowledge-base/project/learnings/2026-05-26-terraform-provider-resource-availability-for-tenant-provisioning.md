---
title: Terraform provider resource availability for tenant provisioning — Hetzner Console-only, Cloudflare and Doppler partial, GitHub partial
date: 2026-05-26
category: capability-gap
tags:
  - terraform
  - hetzner
  - cloudflare
  - doppler
  - github
  - provisioning
  - multi-tenant
issue: 3723
related_issues: [3769, 3770, 3771, 3772]
brainstorm: knowledge-base/project/brainstorms/2026-05-26-tenant-provisioning-skills-brainstorm.md
adr: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
status: published
---

# Learning: Terraform provider resource availability for tenant provisioning

## Problem

When designing provisioning skills (#3769-#3772) to automate the tenant provisioning runbook, the operator required Terraform-first automation: use TF providers where they expose resources, fall back to CLI/API where they don't. The issue bodies described skills "wrapping" CLI tools (`hcloud`, `wrangler`, `doppler`), but the actual CLI/API coverage per provider was unverified.

## Solution

Research each provider's Terraform provider, CLI tool, and API for the specific operations needed (project creation, token minting, OIDC configuration, repo creation, environment setup).

### Resource Availability Map

| Provider | Operation | TF Resource | CLI Support | API Support |
|---|---|---|---|---|
| Hetzner | Project creation | NO (`hcloud_project` does not exist) | NO (`hcloud` has no `project` subcommand) | Unconfirmed (API docs show no project endpoint) |
| Hetzner | Token minting | NO | NO (Console-only) | NO |
| Cloudflare | Scoped API token | YES (`cloudflare_api_token`, v4+) | NO (`wrangler` cannot create tokens) | YES (`POST /user/tokens`) |
| Doppler | Project + config | YES (`doppler_project` + `doppler_config`, v1.21+) | YES (`doppler projects create` + `doppler configs create`) | YES |
| Doppler | OIDC service-account-identity | NO (no TF resource) | YES (via Doppler CLI) | YES (Doppler API v3) |
| GitHub | Repository | YES (`github_repository`, v6+) | YES (`gh repo create`) | YES |
| GitHub | Environment | YES (`github_repository_environment`, v6+) | YES (`gh api`) | YES |
| GitHub | App install | NO (ToS B.3 human consent gate) | NO | NO |

### Design Decision

Adopted "Approach A: Per-tenant Terraform provisioning root with guided CLI fallback." Each skill generates `.tf` files in a per-tenant `provisioning/` directory (separate from the tenant's `infra/` root). Operations without TF resources fall back to guided CLI steps with smoke-test verification.

## Key Insight

When designing skills that wrap provider operations, verify the actual TF resource + CLI + API surface BEFORE committing to an automation approach. Issue bodies described "wrapping `hcloud` CLI" for project creation, but `hcloud` cannot create projects. The gap between described scope and actual tool capability determined the skill's architecture (guided+verify vs. full automation).

Terraform Registry pages (`registry.terraform.io`) are JS-rendered SPAs — WebFetch returns empty content. Use WebSearch + GitHub repo README/docs pages as the research path for TF provider capabilities.

## Session Errors

1. **WebFetch failed on 3 `registry.terraform.io` URLs** — JS-rendered SPA returned only "Terraform Registry" header with no resource information. Recovery: used WebSearch to find provider docs, then checked GitHub repos directly. **Prevention:** when researching Terraform providers, skip `registry.terraform.io` WebFetch and go directly to GitHub repos (`github.com/<org>/terraform-provider-<name>`) or use `context7` MCP for docs lookup.

2. **`git rev-parse --show-toplevel` fails in bare repos** — incident telemetry emit script used `$(git rev-parse --show-toplevel)` which errors with "this operation must be run in a work tree" in bare repo context. Recovery: used absolute path instead. **Prevention:** in bare-repo-aware scripts, use `$REPO_ROOT` variable or hardcoded path instead of `git rev-parse --show-toplevel`. The brainstorm skill already handles this for most operations but the telemetry emit path was missed.

## References

- ADR-030: `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md`
- Tenant provisioning runbook: `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-26-tenant-provisioning-skills-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-tenant-provisioning-skills/spec.md`
- Hetzner TF provider: `hetznercloud/hcloud ~> 1.49` (no project-level resources)
- Cloudflare TF provider: `cloudflare/cloudflare ~> 4.0` (`cloudflare_api_token` available)
- Doppler TF provider: `DopplerHQ/doppler ~> 1.21` (project + config, no OIDC)
- GitHub TF provider: `integrations/github ~> 6.0` (repository + environment)
