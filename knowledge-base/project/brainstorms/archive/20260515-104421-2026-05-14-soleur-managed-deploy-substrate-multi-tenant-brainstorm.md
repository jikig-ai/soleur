---
title: Soleur-managed multi-tenant deploy substrate
date: 2026-05-14
issue: 3723
sibling_issue: 3756 (symptom-fix: replace terraform_data.deploy_pipeline_fix SSH provisioner with #749 CF Tunnel webhook)
draft_pr: 3744
worktree: .worktrees/feat-soleur-managed-deploy-substrate-3723
branch: feat-soleur-managed-deploy-substrate-3723
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
status: brainstorm-complete
---

# Brainstorm: Soleur-managed multi-tenant deploy substrate

## Scope reframe (relative to issue body)

The issue #3723 was originally framed as "ship a self-hosted GH Actions runner on Hetzner as scaffolding toward multi-tenant." The triad (CPO + CLO + CTO) surfaced that this conflated two problems:

1. **Symptom**: `apply-deploy-pipeline-fix.yml` times out because GH-hosted runner egress IPs are not in Doppler `prd_terraform/ADMIN_IPS`. Affects Soleur's own monorepo deploy pipeline today.
2. **Question**: What architectural shape lets Soleur deploy on behalf of non-technical tenants without aggregating tenant credentials or requiring an operator laptop?

The operator (Jean) chose to split: **#3723 covers the multi-tenant substrate question only**. The symptom fix gets a sibling issue, scoped narrowly and using the existing #749 architecture (CF Tunnel + webhook). This brainstorm document covers #3723 only.

## User-Brand Impact

**Artifact at risk:** Tenant cloud credentials (Hetzner API tokens, Cloudflare API tokens, Doppler service tokens, deploy SSH keys) and the live tenant production deploys those credentials authorize.

**Vector:** A substrate that aggregates credentials for >1 tenant in a single process (central runner pool, shared deploy executor, Soleur-as-cred-vault) becomes a credential-aggregation single point of failure. One compromise exposes N tenants. A silent-deploy-failure surface (runner offline, IP drift unnoticed, token expired) means a critical tenant bug fix never reaches their prod — the tenant sees stale buggy behavior with no signal.

**Threshold:** `single-user incident` (Phase 0.1 operator selection: both cross-tenant credential leak and silent deploy failure). One tenant's data exposed = brand survival event. One tenant's prod silently stuck on a vulnerable build = brand survival event.

**Plan inherits this threshold.** The `user-impact-reviewer` agent is the load-bearing PR-time gate per `hr-weigh-every-decision-against-target-user-impact`.

## What We're Building

**Hybrid: Approach A as v1 substrate, with Approach B and C documented as open escape hatches.**

### Approach A — Per-tenant GitHub Actions OIDC + tenant-owned cloud accounts

- **Provisioning (one-time per tenant)**: Soleur agents provision a per-tenant Hetzner sub-project, Cloudflare account, Doppler project, and GitHub repository. Tenant becomes the account owner; Soleur retains only a scoped GitHub App install on the tenant's repo (orchestration plane access, not cloud credentials).
- **Runtime**: each tenant's GitHub repo holds its own workflows. GitHub Actions OIDC mints short-lived per-job tokens for Hetzner / Cloudflare / Doppler at deploy time. No long-lived credentials exist on Soleur-owned infrastructure.
- **Deploy trigger**: Soleur agents call `workflow_dispatch` (or push to a deploy branch) on the tenant's repo via the GitHub App install. The tenant's workflow takes it from there.
- **Inside each tenant repo**: deploys to the tenant's prod use the #749 pattern (CF Tunnel + webhook + CF Access service-token). Identical architecture to Soleur's own monorepo, replicated per-tenant.
- **No Soleur-managed runtime**: GitHub provides the runners; Cloudflare provides the tunnel substrate. Soleur's role is provisioning automation + orchestration plane.

### Approach B (open escape hatch)

Per-tenant Cloudflare Worker as deploy executor, holding tenant-scoped tokens in Worker Secrets. Open if (i) GitHub vendor lock-in becomes painful or (ii) GH OIDC fan-out across N tenants hits API/rate-limit friction.

### Approach C (open escape hatch)

Pure BYOInfra: tenant brings their own cloud accounts; Soleur agents OAuth into them per-deploy. Open if a tenant arrives with pre-existing infrastructure and refuses Soleur provisioning.

## Why This Approach

1. **Zero credential aggregation by construction.** Each tenant's cloud credentials live exclusively inside the tenant's own GH repo secrets / OIDC trust relationships. No Soleur-side process holds >1 tenant's credentials simultaneously. Satisfies the hard constraint set by the operator's User-Brand Impact framing.
2. **No operator laptop dependency.** Deploys are triggered by Soleur agents calling tenant repo workflows. No laptop in the path. Generalizes from the founder use case (Jean creating his first non-Soleur project via Soleur) to every future tenant.
3. **#749 consistency preserved.** Each tenant repo's prod deploys use the same CF Tunnel + webhook architecture Soleur already uses for its own monorepo. No bespoke per-tenant runtime; identical pattern, replicated.
4. **Free runners.** GitHub-hosted runners cost zero for the tenant and zero for Soleur. No Soleur-managed compute to patch, monitor, or scale.
5. **Tenant inspectability.** Everything appears in the tenant's own GitHub Actions UI, Hetzner console, Cloudflare dashboard. Soleur is not a credential mystery box. Reduces support burden and increases tenant trust.
6. **Reversibility.** Each tenant's stack is portable. If a tenant offboards, they keep their accounts; if Soleur pivots, no centralized infrastructure to unwind.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Split #3723 from the symptom-fix. | The triad showed two distinct problems were conflated. The symptom-fix (Soleur monorepo IP-drift) ships independently and immediately; the substrate question (multi-tenant) is the real architectural decision. |
| 2 | Adopt Approach A (GH Actions OIDC + per-tenant cloud accounts) as v1 substrate. | Only candidate that satisfies the hard credential-aggregation constraint by construction. |
| 3 | Hybrid framing: A locked; B and C in Open Questions with re-evaluation triggers. | Avoids speculating on GH lock-in painfulness before it is felt; keeps escape hatches honest. |
| 4 | Validation gate: Jean's first non-Soleur project. | Founder is the first tenant. No need to wait for ≥2 external founders to ask — Jean himself is the validation signal, and his "no deploys from laptop" framing generalizes. |
| 5 | Symptom-fix sibling issue applies #749 pattern (CF Tunnel + webhook), not a new Hetzner runner. | Restores #749 consistency for the Soleur monorepo. Replaces the `terraform_data.deploy_pipeline_fix` SSH provisioner. |
| 6 | Meta-audit log of "Soleur agent X triggered deploy for tenant Y at time Z" is a load-bearing v1 primitive. | CLO mandate; cannot be deferred. Must ship with Approach A v1, not after first tenant ships. Lands in Supabase eu-west-1 with 24-month retention per `dsar_export_audit_pii` precedent. |
| 7 | RoPA entry added for the CI/CD + multi-tenant-deploy processing activity before any non-Soleur tenant uses the substrate. | CLO mandate; Hetzner DPA already covers single-tenant scope but the RoPA must reflect the multi-tenant trajectory. |

## Non-Goals (v1)

- A self-hosted Hetzner runner serving the Soleur monorepo. **Eliminated.** Conflicts with #749. The symptom fix uses the existing CF Tunnel + webhook substrate instead.
- A central runner pool shared across tenants. **Eliminated** by the credential-aggregation hard constraint.
- Provisioning automation for >5 tenant cloud-account types. v1 covers Hetzner + Cloudflare + Doppler + GitHub (the same stack Soleur uses for its own monorepo). Adding new provider types is opt-in scope expansion.
- Soleur as the audit-log source-of-truth for tenant cloud-side events. Each tenant's cloud-side audit logs remain authoritative; Soleur's meta-audit log only records orchestration-plane events.
- SOC2-attested substrate. Out of scope until a non-Soleur tenant signs a paid contract. CLO mandate covers RoPA + DPA + audit log; SOC2 follows revenue.

## Open Questions

1. **Approach B trigger.** When (if ever) does GitHub vendor lock-in become painful enough to force migration to per-tenant Cloudflare Workers? Concrete triggers: GitHub rate-limits on `workflow_dispatch` at N tenants; GitHub Actions pricing changes; a tenant requiring non-GitHub source control.
2. **Approach C trigger.** What does the onboarding flow look like for a tenant with pre-existing Hetzner/Cloudflare/Vercel accounts? Does Soleur OAuth into their existing setup or insist on a fresh Soleur-provisioned account?
3. **Cold-start provisioning automation.** Which Soleur agent (or skill) owns the 5-API account creation flow? CLO needs each provider's Terms of Service evaluated for "Soleur creates an account on behalf of a user" — some providers (Cloudflare) explicitly allow this with proper attribution; others may not.
4. **Per-tenant deploy failure surfacing.** When a tenant's GH Actions workflow fails, how does the tenant see it in the Soleur UI? The product surface for "your deploy failed" needs design (CPO ownership; out of scope for this infra brainstorm but flagged as a downstream gap).
5. **Tenant offboarding.** If a tenant cancels, what happens to their provisioned Soleur-named accounts? Account ownership transfer mechanism per provider is heterogeneous.
6. **Symptom-fix migration of Soleur-as-tenant-zero.** Once Approach A's provisioning automation exists, should Soleur's own monorepo migrate onto it (i.e., Soleur deploys itself via Approach A, becoming its own first tenant)? Defer the migration but design Approach A so it's not blocked.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Multi-tenant deploy substrate is not on the current roadmap (T1-T4) and no external founder has asked for it; the brainstorm proceeds anyway because the operator-as-first-tenant validation signal is load-bearing — Jean creating his next project via Soleur is the forcing function. ADR must explicitly capture "validated by founder-as-first-tenant, not by external founder demand" as the rationale.

### Legal (CLO)

**Summary:** Hetzner DPA already covers single-tenant scope (existing CX33 server); the multi-tenant trajectory requires four mandatory pre-merge primitives before any non-Soleur tenant uses the substrate: (i) RoPA entry at `knowledge-base/legal/article-30-register.md` for the multi-tenant deploy processing activity, (ii) ADR for the new orchestration plane, (iii) day-1 append-only audit log shipping to Supabase eu-west-1 with 24-month retention, (iv) `/soleur:gdpr-gate` clean PR run. Any code path serving a non-Soleur tenant before all four exist is descoped from v1.

### Engineering (CTO)

**Summary:** Approach A (per-tenant GH Actions OIDC + tenant-owned accounts) is the only candidate that satisfies the hard credential-aggregation constraint by construction; it inherits the #749 CF Tunnel + webhook pattern inside each tenant repo so the substrate is consistent end-to-end. The original issue's Hetzner-runner proposal silently reversed the #749 decision and aggregated prod-write credentials in a persistent VM — eliminated. Sibling symptom-fix issue applies #749 directly to `terraform_data.deploy_pipeline_fix` instead.

## Capability Gaps

| Gap | Domain | Evidence | Why needed |
|---|---|---|---|
| Per-tenant account-provisioning automation (Hetzner + Cloudflare + Doppler + GitHub) | Engineering | `grep -r "hcloud_project\|tenant.*hetzner" apps/ knowledge-base/` returns zero hits; `apps/web-platform/lib/supabase/tenant.ts` exists for app-layer multi-tenancy only | Approach A v1 cannot ship without an automated 5-API account-creation flow. Manual provisioning per tenant would block N=many scaling and require operator laptop. |
| Meta-audit log: "Soleur agent X triggered deploy for tenant Y at time Z" | Legal + Engineering | No existing Soleur-side audit primitive for cross-tenant orchestration events (`grep -r "audit_log" apps/web-platform/lib/` returns app-event audit only) | CLO mandate; must ship day-1 with v1, not deferred. GitHub-side audit logs are 60-day retention and don't capture Soleur-agent identity. |
| GitHub App install + scoped permission model for tenant repos | Engineering | `gh api /apps` returns Soleur's existing apps; no per-tenant-repo-scoped install pattern documented | Approach A's orchestration plane requires a GitHub App install per tenant repo. Token scoping, install-rotation, and breach-response need design. |
| Tenant-side deploy-failure surface in Soleur UI | Product + Engineering | No existing UI surface for "your tenant's external GitHub workflow failed" — Soleur UI is currently agent-event-driven, not cross-system observability | Tenants who don't watch their GitHub Actions tab need an in-Soleur signal when their deploys fail. Out of scope for the infra v1 but flagged for downstream product work. |
| RoPA processing-activity entry for multi-tenant deploys | Legal | `knowledge-base/legal/article-30-register.md` exists with single-tenant Hetzner row only | Mandatory before any non-Soleur tenant uses the substrate. Article 30 GDPR requirement. |
| ToS evaluation per provider for "Soleur creates accounts on behalf of users" | Legal | No prior research artifact found in `knowledge-base/legal/` for ToS-acceptance-on-behalf-of | Soleur-provisions-accounts model requires explicit per-provider authorization. Cloudflare allows; Hetzner unclear; Doppler unclear. Pre-build research. |

## Lane

**Resolved:** `cross-domain`. Auto-set by `USER_BRAND_CRITICAL=true` from Phase 0.1 framing (cross-tenant credential leak + silent deploy failure both selected). Triad (CPO + CLO + CTO) ran in parallel.

## Validation Gate

**Trigger to commit to build:** Operator (Jean) decides to create a new non-Soleur project via Soleur and chooses Approach A as the deploy substrate for that project. The first such project is the v1 implementation target.

**Trigger to re-open Approach B (CF Worker):** GitHub Actions OIDC rate-limit hit at N tenants, OR a tenant arrives requiring non-GitHub source control.

**Trigger to re-open Approach C (BYOInfra):** A tenant arrives with pre-existing Hetzner/Cloudflare/Vercel accounts AND refuses Soleur-provisioned alternates.

**Re-evaluation cadence:** Quarterly, or upon any of the above triggers firing.

## References

- Original issue: `#3723` (state: OPEN, reframed mid-brainstorm to multi-tenant substrate only).
- Sibling symptom-fix issue: `#3756` — "fix(infra): replace terraform_data.deploy_pipeline_fix SSH provisioner with #749 CF Tunnel webhook". Scope: replace `terraform_data.deploy_pipeline_fix` SSH provisioner with #749 CF Tunnel + webhook pattern.
- Draft PR: `#3744` (worktree push).
- Brainstorm bundle deferring #3723 from "ops toil" framing: `knowledge-base/project/brainstorms/2026-05-13-unified-ci-deploy-stall-hardening-brainstorm.md` decision row #5.
- Prior architectural decision #749: "CI deploy SSH rule removed — deploys now use webhook via Cloudflare Tunnel" — see `apps/web-platform/infra/firewall.tf:15` and `apps/web-platform/infra/tunnel.tf:1-4`.
- Hard rule citation correction: `hr-every-new-terraform-root-must-include-an` (AGENTS.core.md:16) mandates the R2 backend, NOT a destroy runbook. The original issue body cited this rule for destroy-runbook requirement; the rule does not say that. (A destroy runbook is good practice per ADR-019 but not the rule the issue cited.)
- Relevant learnings: `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`, `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`, `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`, `2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md`, `2026-03-29-doppler-service-token-config-scope-mismatch.md`, `2026-03-21-terraform-state-r2-migration.md`.
- Roadmap: `knowledge-base/product/roadmap.md` (multi-tenant deploy substrate is not currently a surfaced theme; this brainstorm proposes opening one only after Approach A v1 ships and the founder-as-first-tenant validation closes).
- Validation thesis: `knowledge-base/product/business-validation.md` (verdict: PIVOT — recruit founders, don't build more; the founder-as-first-tenant framing is consistent with this, not a violation).
