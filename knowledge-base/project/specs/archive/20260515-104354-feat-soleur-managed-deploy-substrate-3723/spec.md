---
feature: soleur-managed-deploy-substrate-3723
issue: 3723
brainstorm: knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md
draft_pr: 3744
branch: feat-soleur-managed-deploy-substrate-3723
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec-complete
---

# Feature: Soleur-managed multi-tenant deploy substrate

## Problem Statement

Soleur is building a platform where solo founders author web apps using Soleur agents. The current deploy posture — operator-manual `terraform apply` from an allowlisted laptop — does not generalize beyond Jean. Any Soleur user creating a new project will face the same problem: they do not want to run prod-write deploys from their laptop (security risk; tooling-setup friction; no audit trail).

Soleur needs a substrate that lets agents deploy on behalf of each Soleur user without (a) aggregating tenant credentials in a shared Soleur process, (b) requiring the user's laptop to be in the deploy path, or (c) silently failing when something drifts.

The validation forcing function is concrete: Jean (operator) plans to create his first non-Soleur project via Soleur. That project must deploy without his laptop.

## Goals

- Provide a per-tenant deploy substrate where each tenant's cloud credentials live exclusively inside that tenant's own infrastructure (GitHub repo secrets, OIDC trust relationships).
- Eliminate operator laptop dependency for tenant deploys.
- Replicate the existing #749 architecture (CF Tunnel + webhook + CF Access service-token) inside each tenant repo so the substrate is consistent end-to-end with Soleur's own monorepo posture.
- Ship the orchestration plane (per-tenant GitHub App install, account-provisioning automation, meta-audit log) as v1 primitives.
- Preserve reversibility: each tenant's stack is portable; Soleur can be removed without unwinding the tenant's infrastructure.

## Non-Goals

- A self-hosted Hetzner GH Actions runner serving the Soleur monorepo. Conflicts with prior decision #749 (`apps/web-platform/infra/firewall.tf:15`). The Soleur-monorepo symptom fix is split to a sibling issue and uses the #749 CF Tunnel pattern instead.
- A central runner pool shared across tenants. Eliminated by the credential-aggregation hard constraint.
- Provisioning automation for >4 provider types in v1. v1 covers Hetzner + Cloudflare + Doppler + GitHub (the stack Soleur already uses for itself). Adding more is opt-in.
- Soleur as authoritative audit-log source-of-truth for tenant cloud-side events. Each tenant's cloud-side audit logs remain authoritative; Soleur's meta-audit log records orchestration-plane events only.
- SOC2 attestation. Out of scope until a non-Soleur tenant signs a paid contract. CLO mandate covers RoPA + DPA + audit log; SOC2 follows revenue.
- Approach B (Cloudflare Worker executor) and Approach C (pure BYOInfra OAuth) implementations. Both are documented as open escape hatches with re-evaluation triggers; neither is built in v1.

## Functional Requirements

### FR1: Per-tenant account provisioning

Soleur agents provision the following per-tenant, one-time at tenant setup:
- A Hetzner sub-project owned by the tenant.
- A Cloudflare account (or scoped sub-account, if Cloudflare ToS permits) owned by the tenant.
- A Doppler project owned by the tenant.
- A GitHub repository owned by the tenant (or by a tenant-organization).

Soleur retains a scoped GitHub App install on the tenant's repo for orchestration access. Soleur does NOT retain Hetzner/CF/Doppler credentials past the provisioning step.

### FR2: Per-tenant deploy workflow scaffolding

Each tenant repo, on provisioning, receives a starter workflow set replicating the Soleur monorepo pattern:
- Build + lint + test on push/PR.
- Deploy on push to `main` via CF Tunnel + webhook + CF Access service-token to the tenant's prod server.
- GitHub Actions OIDC trust to the tenant's Hetzner / Cloudflare / Doppler accounts (short-lived per-job credentials only).

### FR3: Soleur orchestration plane

Soleur agents trigger tenant deploys via `workflow_dispatch` (or push to a deploy branch) on the tenant's GitHub repo, authenticated via the scoped GitHub App install. The agent records the trigger event in Soleur's meta-audit log.

### FR4: Meta-audit log

Soleur maintains an append-only audit log of orchestration-plane events: `{soleur_actor, tenant_id, action, target_repo, target_workflow, trigger_timestamp, trigger_outcome}`. Ships to Supabase eu-west-1, 24-month retention, accessible to the tenant via Soleur UI per `dsar_export_audit_pii` precedent.

### FR5: Deploy-failure surfacing (downstream gap, not v1 FR)

When a tenant's GitHub Actions workflow fails, the failure is surfaced in the Soleur UI. v1 scope: capture the failure event in the meta-audit log. v1.1+ scope: in-product UI surface. Flagged as a downstream product gap, not blocking infra v1.

## Technical Requirements

### TR1: No credential aggregation

No Soleur-owned process holds credentials for >1 tenant simultaneously. Enforced by construction: each tenant's cloud credentials are stored exclusively in that tenant's GitHub repo secrets and exposed only to that tenant's workflows. GitHub Actions OIDC mints short-lived per-job tokens for cloud APIs — long-lived cloud credentials do not exist on Soleur infrastructure.

### TR2: GitHub App install scope per tenant

The Soleur GitHub App is installed per tenant repo with the narrowest permission set sufficient for `workflow_dispatch` + repo metadata read. No write access to repo contents, no access to repo secrets. Install token rotation cadence: 1 hour (GitHub default). Install revocation runbook ships with v1.

### TR3: Per-tenant Terraform roots, R2 backend

Each tenant's infrastructure is managed by a per-tenant Terraform root **inside that tenant's GitHub repo** (NOT inside the Soleur monorepo — the scaffold template at `apps/_templates/tenant-stack/infra/` is the source pattern, copied into each tenant repo at provisioning time). R2 backend pattern from `apps/web-platform/infra/main.tf:1-14` is copied. Each tenant has a dedicated R2 key: `tenants/<founder-id>/terraform.tfstate` (the data-layer term for "tenant" in this codebase is `founder_id` — see TR5 reconciliation). Per `hr-every-new-terraform-root-must-include-an` (AGENTS.core.md:16) — the rule mandates the **R2 backend**, NOT a destroy runbook; the original issue body misread the rule (correction documented in ADR-030).

### TR4: CF Tunnel + webhook per tenant

Each tenant's prod deploy uses the #749 architecture: a CF Tunnel from the tenant's prod server to a deploy hostname on Cloudflare, protected by CF Access service-token (`CF-Access-Client-Id` + `CF-Access-Client-Secret`). GitHub Actions calls the tunnel; tunnel forwards to a local webhook on the tenant's prod server. No SSH from CI to tenant prod.

### TR5: Day-1 audit log to Supabase eu-west-1

Meta-audit log table schema, retention policy (12 months — orchestration-plane events do not justify 24mo per legal-compliance review; PA 8 P0 mirror precedent), and write path ship in v1. SECURITY DEFINER functions for log writes pin `SET search_path = public, pg_temp` (public FIRST, in that order, per `cq-pg-security-definer-search-path-pin-pg-temp` verbatim). RLS forbids cross-tenant reads.

**Data-layer term reconciliation:** the brainstorm and product framing use "tenant"; the codebase's existing convention is `founder_id` / `user_id` (see `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:127-216` for the audit-table precedent). v1 maps `founder_id` ↔ "tenant" 1:1 (one founder owns one tenant stack). The new audit table uses `founder_id` as the FK column to match precedent. ADR-030 documents the mapping; future multi-stack-per-founder support is out of v1 scope.

**Audit shape:** writes go via SECURITY DEFINER RPC only (direct INSERT blocked by table-level REVOKE per learning `2026-03-20-supabase-column-level-grant-override.md` — table-level REVOKE + GRANT-only-on-RPC, never column-level). Include `gh_run_id bigint` + `oidc_jti text` (RFC 7519 §4.1.7 — jti is a case-sensitive string, NOT uuid) as non-forgeable upstream discriminators per learning `2026-03-20-gdpr-remediation-migration-discriminator-strategy.md`. Include `retention_until timestamptz NOT NULL DEFAULT (now() + interval '12 months')` per GDPR Art. 5(1)(e) fixture. `founder_id` FK uses `ON DELETE RESTRICT` (NOT `SET NULL`) so the Art. 17 `anonymise_tenant_deploy_audit()` RPC runs BEFORE `auth.users` deletion; offboarding runbook documents the explicit ordering.

### TR6: RoPA entry for the multi-tenant deploy processing activity

`knowledge-base/legal/article-30-register.md` updated with a new processing-activity row before any non-Soleur tenant uses the substrate. Names Hetzner + Cloudflare + Doppler + GitHub as sub-processors. CLO mandate.

### TR7: ADR captures the credential-aggregation ceiling as load-bearing constraint

A new ADR (`/soleur:architecture create`) documents Approach A's selection. Captures: (i) the hard credential-aggregation constraint as the design ceiling, (ii) the validation gate (founder-as-first-tenant), (iii) the open escape hatches B and C with re-evaluation triggers, (iv) explicit acknowledgment that this is unvalidated by external founder demand and is committed to anyway on operator-as-first-tenant signal.

### TR8: Provider ToS pre-merge research

Each provider's Terms of Service is evaluated for "Soleur creates an account on behalf of a user" patterns before any provisioning automation ships:
- Cloudflare: documented as allowed with proper attribution.
- Hetzner: TBD — research artifact lands in `knowledge-base/legal/` pre-merge.
- Doppler: TBD — research artifact lands in `knowledge-base/legal/` pre-merge.
- GitHub: documented (org/repo creation via App install is supported).

### TR9: GDPR gate clean

`/soleur:gdpr-gate` runs on the v1 PR and produces a clean report before merge. Triggered by the multi-tenant data surface.

### TR10: Sentry-mirrored failure signals

All orchestration-plane failures (provisioning failures, GitHub App install failures, audit-log write failures) mirror to Sentry per `cq-silent-fallback-must-mirror-to-sentry`. No green-checkmark-with-zero-effect failure modes.
