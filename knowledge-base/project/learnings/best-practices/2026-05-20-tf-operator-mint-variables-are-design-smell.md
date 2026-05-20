---
module: Web Platform Infrastructure
date: 2026-05-20
problem_type: workflow_drift
component: tooling
symptoms:
  - "`terraform plan` fails with `Error: No value for required variable` on `apply-web-platform-infra.yml` post-merge"
  - "PR adds 4 new `variable \"...\" { sensitive = true }` blocks; issue body asks operator to mint each in vendor dashboards"
root_cause: design_smell
resolution_type: rule_addition
severity: medium
tags: [terraform, doppler, github-app, iac, autonomy, operator-mint]
synced_to: []
---

# `variable { sensitive = true }` is the most expensive secret-supply shape — exhaust autonomous paths first

## Problem

PR-H #4066 (Daily Priorities multi-source webhook ingress) added four new sensitive variables to `apps/web-platform/infra/variables.tf`:

- `github_app_client_id`
- `github_app_client_secret`
- `github_actions_token` (fine-grained PAT)
- `doppler_token_kb_drift` (Doppler service token)

The PR shipped without populating Doppler `prd_terraform`. Three weeks later, when `apply-web-platform-infra.yml` (#4122) tried to run the canonical `terraform plan` post-merge, it failed with `Error: No value for required variable` on all four. Issue #4150 proposed the path of least resistance: "Operator actions required — mint each credential in a vendor dashboard and paste into Doppler `prd_terraform`." That's 4 manual steps across 3 vendor surfaces (GitHub Apps UI, fine-grained PAT page, Doppler dashboard) per fresh-clone operator, per credential rotation, in perpetuity.

## Root cause — design smell at variable-declaration time

A `variable { sensitive = true }` block is the **least flexible** secret-supply path:

- Every consumer (dev workstation, CI runner, drift detector) needs its own copy of the credential in its Doppler/secret-store.
- Rotation requires touching N consumer surfaces, not 1 producer surface.
- The runbook cost grows linearly with consumer count; the variable block looks like 5 lines of HCL at PR time but loads cost onto every downstream surface forever.

The IaC providers Soleur already loads have higher-affinity primitives that the PR-H author skipped:

- `doppler_service_token` (DopplerHQ/doppler ≥1.x): mints config-scoped Doppler tokens in-band using the provider's workplace-scope auth.
- `random_id` / `random_password` (hashicorp/random): for Soleur-generated secrets where the value is opaque (webhook secrets, signing keys).
- `app_auth { id, installation_id, pem_file }` (integrations/github ≥6.x): exchanges App credentials for a short-lived installation token at each plan/apply, replacing long-lived PATs.

Skipping these in favor of `var.X` is a design smell because the variable-shaped solution looks cheap at PR time but is the most expensive choice over the lifecycle.

## Resolution — 4 operator-mints collapsed to 0 net-new credentials

| Variable | Resolution | Mechanism |
|---|---|---|
| `github_app_client_id` | Deleted (var + 1 doppler_secret resource) | Zero TS/TSX consumers — `git grep` returned 0. Dead OAuth plumbing the webhook flow never uses. |
| `github_app_client_secret` | Deleted (var + 1 doppler_secret resource) | Same — zero consumers. |
| `github_actions_token` (PAT) | Deleted (var) | `provider "github"` switched to `app_auth` using existing `var.github_app_id` + `var.github_app_private_key`. Net narrowing: long-lived PAT → short-lived installation token (1-hour TTL, auto-rotated per terraform invocation). |
| `doppler_token_kb_drift` | Deleted (var) | Replaced by `doppler_service_token.kb_drift` resource — workplace-scope `DOPPLER_TOKEN_TF` (already in `prd_terraform`) authorizes the in-band mint. |

Pre-flight: mirrored `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from `prd` → `prd_terraform` so the App-auth provider can resolve them via `--name-transformer tf-var`. One-time value move, no new credentials.

One non-obvious side effect: the App needed `Repository Secrets: Read and write` permission added to its declared permissions, AND the installation needed to accept the new permission. Both were one-time browser actions (no GitHub API for App-permission self-modification) handled via Playwright in the PR session.

## Prevention — `hr-tf-variable-no-operator-mint-default`

Added to `AGENTS.core.md`:

> New TF sensitive variables must prefer provider-side mint (`doppler_service_token`, `random_id`, `app_auth`) or credential reuse over operator-mint.

PR reviewers verify the autonomy hierarchy was considered. The rule's existence catches the next operator-mint anti-pattern at PR-author time, not three weeks later at apply time.

## Key insight

The cheapest path at PR-write time is rarely the cheapest path at lifecycle level. A `variable { sensitive = true }` block is 5 lines of HCL; the operator-onboarding runbook to feed it is 50; the recurring debt across CI runners + drift detectors + new contributors is unbounded.

The corollary: **if a vendor's API can mint the credential and your TF provider has scope to call it, the credential should be a resource, not a variable.** The few exceptions (CAPTCHA-gated registrations, payment cards, hardware MFA) are exactly the operator-only canonical-list class enumerated in `2026-05-15-operator-only-step-canonical-list.md`.

## References

- Plan: `knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-tf-autonomy-4150-plan.md`
- Sibling pattern (Inngest IaC, same autonomy reasoning): `apps/web-platform/infra/inngest.tf`
- Doppler service-token provider docs: <https://registry.terraform.io/providers/DopplerHQ/doppler/1.21.2/docs/resources/service_token>
- App-installation auth on integrations/github: <https://registry.terraform.io/providers/integrations/github/6.12.1/docs#authenticating-via-github-app-installation>
- Canonical TF invocation: `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- Operator-only canonical list (the legitimate exceptions): `knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md`
