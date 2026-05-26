---
title: Tenant provisioning skills — Terraform-first automation of runbook Steps 1-4+7
date: 2026-05-26
issues: [3769, 3770, 3771, 3772]
parent_issue: 3723
deferred_issues: [3773]
draft_pr: 4501
worktree: .worktrees/feat-tenant-provisioning-skills
branch: feat-tenant-provisioning-skills
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
status: brainstorm-complete
---

# Brainstorm: Tenant provisioning skills — Terraform-first automation

## User-Brand Impact

**Artifact at risk:** Tenant cloud credentials (Hetzner API tokens, Cloudflare API tokens, Doppler service tokens) and the live tenant production deploys those credentials authorize.

**Vector:** A skill that mishandles the credential quarantine discipline (leaks a token to shell history, env export, MCP parameter log, or Soleur-side persistent storage) would violate ADR-030's hard credential-aggregation ceiling. A skill that provisions with wrong scope (overly-broad CF token, single-claim OIDC binding) would weaken the tenant's blast-radius controls.

**Threshold:** `single-user incident`. One tenant's credential exposed = brand survival event. Operator selected "All of them" (credential leak + trust breach + cross-tenant).

## What We're Building

Four Soleur skills automating runbook Steps 1-4+7 from `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md`. Each skill generates a per-tenant Terraform provisioning root where TF resources exist, with guided CLI fallback for operations Terraform cannot reach.

### Scope

| Issue | Runbook Step | Skill Name | TF Coverage |
|---|---|---|---|
| #3771 | Step 3 | `provision-doppler` | `doppler_project` + `doppler_config` via TF; OIDC service-account-identity via CLI (no TF resource) |
| #3770 | Step 2 | `provision-cloudflare` | `cloudflare_api_token` via TF; full automation |
| #3769 | Step 1 | `provision-hetzner` | No TF resources (Console-only for project + token); guided + verify pattern |
| #3772 | Steps 4+7 | `provision-github` | `github_repository` + `github_repository_environment` via TF; App install via human consent gate (ToS B.3) |

### Deferred

| Issue | Reason |
|---|---|
| #3773 (Deploy-failure UI) | Trigger not fired (tenant complaint). Different design process (product, not ops). Separate from provisioning skills. |

### Architecture: Per-tenant Terraform provisioning root

Each skill generates `.tf` files in a per-tenant `provisioning/` directory (separate from the tenant's `infra/` root). The separation matters because:

- **Privilege levels differ:** provisioning needs higher-privilege bootstrap credentials (create tokens, create projects); infra uses the scoped tokens that provisioning created.
- **Lifecycle differs:** provisioning runs once at onboarding; infra runs on every deploy.
- **Teardown path:** `terraform destroy` on the provisioning root revokes all created tokens/resources cleanly.

For operations where no TF resource exists (Hetzner project, Doppler OIDC, GitHub App install), skills fall back to guided CLI steps with smoke-test verification.

## Why This Approach

1. **Terraform-first matches `hr-all-infrastructure-provisioning-servers`** and the operator's stated preference. Declarative configs are auditable; TF state captures exactly what was provisioned.
2. **Separate provisioning root preserves privilege isolation.** The deploy-time infra root never needs bootstrap-level credentials. The provisioning root is a one-time setup artifact.
3. **CLI fallback is honest about TF gaps.** Hetzner has no project-level TF resources; Doppler has no OIDC TF resources. Pretending everything fits TF would produce worse outcomes than acknowledging the gaps.
4. **CTO-recommended build order (by automation readiness)** frontloads the skill with the best TF/CLI coverage (#3771 Doppler), letting the first skill establish the pattern before tackling harder providers.
5. **Operator override on #3772 scope.** CPO and CLO recommended deferring #3772 (human consent gate, architecturally distinct). The operator chose to include it to have repo setup automated for the new project. The human consent gate is preserved per GitHub ToS B.3.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Build all 4 provisioning skills (#3769-#3772). Defer #3773. | Operator override: N=2 is imminent, all 4 steps needed for the new project. #3773's trigger (tenant complaint) hasn't fired. |
| 2 | Terraform-first with guided CLI fallback. | Use TF resources where they exist (`cloudflare_api_token`, `doppler_project`, `doppler_config`, `github_repository`, `github_repository_environment`). CLI/guided for Hetzner project, Doppler OIDC, GitHub App install. |
| 3 | Separate `provisioning/` TF root per tenant. | Privilege isolation (bootstrap vs. deploy creds), lifecycle separation (one-time vs. recurring), clean teardown via `terraform destroy`. |
| 4 | Build order: #3771 → #3770 → #3769 → #3772. | CTO-recommended automation-readiness order. Doppler (best TF/CLI coverage) first to establish the pattern. Hetzner (Console-only) and GitHub (human gate) last. |
| 5 | Shared conventions doc, not shared framework. | Matches ADR-030 "extract at N=2" philosophy. Extract shared bash library at N=3+ if convention drift materializes. |
| 6 | `read -s` + subshell for bootstrap credentials. | Never MCP (parameters logged), never env export (session-persistent), never CLI arg (history). Token-quarantine discipline from the runbook, codified in skill scripts. |
| 7 | `--dry-run` mode per skill. | Matches existing patterns (`admin-ip-refresh`, `flag-create`). Validates inputs, prints TF plan / API calls, exits without mutations. |
| 8 | No orchestration skill at N=2. | Each skill prints "next step" hint. Compose at N=3+ when the orchestration shape is visible from 2 exercises. |
| 9 | Update tenant-provisioning.md runbook to reflect TF-where-possible. | Runbook currently describes CLI-only Steps 1-3. Update to note which steps use TF and which fall back to CLI. |

## Non-Goals (this brainstorm)

- A shared bash library across provisioning skills (extract at N=3+)
- An orchestration skill that chains all 4 steps
- Mock provider testing (use `--dry-run` + input validation tests)
- Tenant offboarding automation (separate scope)
- Automating Steps 5, 6, 8, 9, 10 of the runbook (remain manual at N=2)

## Open Questions

1. **TF state backend for provisioning root.** Same R2 backend as Soleur's infra, or per-tenant backend? Per-tenant is cleaner but requires R2 bucket setup per tenant.
2. **Hetzner API project creation.** Confirmed Console-only at time of writing. If Hetzner adds a project API, the skill should migrate from guided to automated.
3. **Doppler OIDC via TF.** `DopplerHQ/doppler` provider has no `doppler_service_account_identity` resource. If added, migrate from CLI to TF.
4. **CF provider version.** Codebase pins `~> 4.0`. `cloudflare_api_token` exists in v4 but check for breaking changes vs. v5.
5. **GitHub provider version.** Not currently in Soleur's TF root. Need to add `integrations/github ~> 6.0` for `github_repository` + `github_repository_environment`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** N=2 trigger is valid. Recommended building #3769-#3771 only (Steps 1-3) and deferring #3772 (human consent gate). Operator overrode to include #3772. Primary argument for building now: token-quarantine discipline is security-critical and manually error-prone — automation is a correctness play, not just convenience. Promoted priority from P3 to P2.

### Legal (CLO)

**Summary:** No fundamental new legal risk — skills automate the same manual runbook actions within the same credential boundaries. Three material gaps: (1) ToS/LIA/PA-10 delta amendments for automation shape, (2) Doppler/GitHub DPA verification (operator actions), (3) credential boundary documentation in each SKILL.md ("MUST run on operator's local machine, MUST NOT run in CI"). N=2 re-evaluation fires the tenant-DPA signing workflow.

### Engineering (CTO)

**Summary:** Hetzner CLI lacks project creation (`hcloud` has no `project` subcommand). Cloudflare skill must use CF API v4 (or TF `cloudflare_api_token`), not `wrangler` (can't create tokens). Doppler is most automatable. Shared conventions doc over shared framework. `--dry-run` per skill. Complexity: #3771 small (hours), #3770 medium (days), #3769 medium (guided+verify), #3772 medium (human gate). Total: 2-3 weeks.

## Capability Gaps

| Gap | Domain | Evidence | Why needed |
|---|---|---|---|
| Hetzner project creation is Console-only | Engineering | `hcloud --help` shows no `project` subcommand. Hetzner API docs show no project-creation endpoint. No `hcloud_project` TF resource. | #3769 must use guided+verify pattern instead of full automation. |
| Doppler OIDC service-account-identity has no TF resource | Engineering | `DopplerHQ/doppler` TF provider has `doppler_project`, `doppler_config`, `doppler_service_token` but no `doppler_service_account` or OIDC resource | #3771 OIDC binding must fall back to Doppler CLI/API |
| GitHub provider not in Soleur TF root | Engineering | `grep github main.tf` returns no GitHub provider in required_providers | #3772 needs `integrations/github ~> 6.0` added to the provisioning TF root |
| ToS research lacks automation-shape delta | Legal | `2026-05-14-tenant-account-provisioning-tos-research.md` covers manual provisioning only | Each skill must document the ToS compliance boundary in SKILL.md |
| PA-10 does not cover automated provisioning | Legal | PA-10 scopes to deploy-orchestration audit logging, not infrastructure provisioning | Amend PA-10 or create new processing activity |

## Terraform Resource Availability

| Provider | TF Resource | Available? | Provider Version |
|---|---|---|---|
| Cloudflare | `cloudflare_api_token` | YES | `~> 4.0` (existing) |
| Doppler | `doppler_project` | YES | `~> 1.21` (existing) |
| Doppler | `doppler_config` | YES | `~> 1.21` (existing) |
| Doppler | OIDC service-account | NO | N/A |
| Hetzner | Project creation | NO | N/A |
| Hetzner | Token minting | NO | N/A |
| GitHub | `github_repository` | YES | `~> 6.0` (new) |
| GitHub | `github_repository_environment` | YES | `~> 6.0` (new) |
| GitHub | App install | NO (ToS B.3) | N/A |

## Learnings Incorporated

22 relevant learnings surfaced. Key ones informing this design:

1. **Doppler service-token scope is invisible** — baked at creation, ignores `-c` flag. Use config-suffixed names.
2. **Doppler `--name-transformer tf-var` is additive** — store WITHOUT `TF_VAR_` prefix.
3. **GitHub App three-plane permission drift** — all three planes (declaration, manifest, installation grant) must be kept in sync.
4. **GitHub secrets cannot start with `GITHUB_` prefix** — HTTP 422.
5. **CF tokens with `cfut_` prefix invisible on dashboard** — document for teardown.
6. **CF service tokens expire silently after 1 year** — scaffold expiry monitoring.
7. **Hetzner API tokens must be read-write** — read-only gives false-positive on read tests.
8. **`read -s` + subshell is the canonical credential quarantine pattern** — matches `admin-ip-refresh`.
