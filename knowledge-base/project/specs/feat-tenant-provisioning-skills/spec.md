---
title: "Tenant provisioning skills — Terraform-first automation"
date: 2026-05-26
issues: [3769, 3770, 3771, 3772]
parent_issue: 3723
deferred_issues: [3773]
brainstorm: knowledge-base/project/brainstorms/2026-05-26-tenant-provisioning-skills-brainstorm.md
adr: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
runbook: knowledge-base/engineering/operations/runbooks/tenant-provisioning.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Spec: Tenant provisioning skills

## Problem Statement

The multi-tenant deploy substrate (ADR-030) ships with a manual 11-step tenant provisioning runbook. At N=2 (operator's second non-Soleur project), the runbook's credential-minting steps (1-4+7) are error-prone, security-sensitive, and ready for automation. The token-quarantine discipline (`read -s` + subshell) is easy to violate manually. Automation is a correctness play.

## Goals

1. Automate runbook Steps 1-4+7 as four independent Soleur skills.
2. Use Terraform where providers expose resources; fall back to guided CLI where they don't.
3. Preserve ADR-030's hard credential-aggregation ceiling — no credential touches Soleur infrastructure.
4. Update the tenant-provisioning runbook to reflect the Terraform-first approach.

## Non-Goals

- Automating Steps 0, 5, 6, 8-10 (remain manual at N=2).
- Building an orchestration skill that chains all 4 steps.
- Building a shared bash library (extract at N=3+).
- Automating tenant offboarding.
- Building the deploy-failure UI (#3773).

## Functional Requirements

| ID | Requirement |
|---|---|
| FR1 | `provision-doppler` skill creates Doppler project + config via Terraform, configures OIDC service-account-identity with two-claim binding via CLI. |
| FR2 | `provision-cloudflare` skill creates scoped API token via Terraform `cloudflare_api_token` with least-privilege permission set. |
| FR3 | `provision-hetzner` skill guides operator through Console project creation, accepts token via `read -s`, runs write-class smoke-test. |
| FR4 | `provision-github` skill creates repo + Environment via Terraform, drives App install to consent screen, resumes after human confirmation. |
| FR5 | Each skill has `--dry-run` mode (validate inputs, print plan, no mutations). |
| FR6 | Each skill generates `.tf` files in a per-tenant `provisioning/` directory (separate from `infra/`). |
| FR7 | Each skill prints "next step" hint on completion (pointing to the next skill in sequence). |
| FR8 | Each skill has explicit teardown instructions for abort-mid-provisioning scenarios. |
| FR9 | Each skill refuses to execute without a confirmed DPA row in `tenant-dpa-register.md` (Step 0 gate). |

## Technical Requirements

| ID | Requirement |
|---|---|
| TR1 | Bootstrap credentials accepted via `read -s` + subshell. Never MCP, env export, or CLI arg. |
| TR2 | No Soleur infrastructure holds tenant credentials at any point. Ephemeral process memory only. |
| TR3 | TF state stored in per-tenant R2 backend (key: `tenants/<slug>/provisioning.tfstate`). |
| TR4 | Skills follow existing anatomy: `SKILL.md` + `scripts/` + optional `references/`. |
| TR5 | Each SKILL.md includes Art. 32 credential boundary pre-condition: "MUST run on operator's local machine. MUST NOT run in CI." |
| TR6 | Doppler OIDC binding enforces two-claim shape (`repository_owner` + `environment`). Single-claim rejected. |
| TR7 | CF token enforces least-privilege: `Workers Scripts:Edit` + `Workers Routes:Edit` + `Account:Cloudflare Pages:Edit` + `Zone:DNS:Edit` only. |
| TR8 | GitHub App install preserves human consent gate per ToS B.3. Skill does NOT automate the install click. |
| TR9 | GitHub Environment configured with required reviewers + deployment-branch-policy pinned to `main`. |
| TR10 | Operator ack gate before every `terraform apply` per `hr-menu-option-ack-not-prod-write-auth`. |

## Build Sequence

| Order | Issue | Skill | Rationale |
|---|---|---|---|
| 1 | #3771 | `provision-doppler` | Best TF/CLI coverage. Establishes the pattern. |
| 2 | #3770 | `provision-cloudflare` | Full TF automation via `cloudflare_api_token`. |
| 3 | #3769 | `provision-hetzner` | Console-only; guided + verify pattern. |
| 4 | #3772 | `provision-github` | Most complex (human gate + TF + teardown sweep). |

## Legal Pre-Conditions

| Action | Owner | Blocking? |
|---|---|---|
| Amend ToS research with automation-shape delta per provider | CLO / legal-compliance-auditor | P1 — before first skill ships |
| Amend PA-10 to include provisioning as sub-purpose | CLO / legal-document-generator | P1 — before first skill ships |
| Amend LIA for skill-driven provisioning | CLO / legal-document-generator | P1 — before first skill ships |
| Verify Doppler DPA status (flip "verification pending") | Operator | P0 — before #3771 ships |
| Verify GitHub DPA status (flip "PENDING" to "AUTO") | Operator | P0 — before #3772 ships |
| Run `gdpr-gate` per skill plan | Operator | P2 — at plan time |
