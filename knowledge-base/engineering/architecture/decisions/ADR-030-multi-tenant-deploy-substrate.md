---
title: "ADR-030 — Multi-tenant deploy substrate: per-tenant GH Actions OIDC + tenant-owned cloud accounts"
status: accepted
date: 2026-05-14
plan: knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md
spec: knowledge-base/project/specs/feat-soleur-managed-deploy-substrate-3723/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md
issue: 3723
supersedes: none
related: [ADR-006-terraform-remote-backend-r2, ADR-007-doppler-secrets-management, ADR-008-cloudflare-tunnel-deployment, ADR-023-supabase-environment-isolation, ADR-028-dsar-export-substrate-and-audit-retention]
---

# ADR-030 — Multi-tenant deploy substrate: per-tenant GH Actions OIDC + tenant-owned cloud accounts

## Context

Issue #3723 was reframed at brainstorm time from "fix Soleur's own SSH-based deploy pipeline" into "design the multi-tenant deploy substrate so Soleur can deploy *future tenant projects* without aggregating their cloud credentials on Soleur infrastructure." The sibling issue #3756 carries the original symptom-fix (replace `terraform_data.deploy_pipeline_fix` SSH provisioner with CF Tunnel + webhook per ADR-008 / #749) — independent track.

The brainstorm (`2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md`) evaluated three candidate approaches against a hard constraint and surfaced a constellation of open questions. Five reviewers (DHH + Kieran + code-simplicity + spec-flow-analyzer + legal-compliance-auditor) reviewed the resulting plan and converged on substantial scope reduction for the N=1 starting state.

This ADR records the architectural decisions that survive the brainstorm + plan-review + revision-2 process.

## Hard constraint — credential-aggregation ceiling

**The hard constraint**: at no point may Soleur-owned infrastructure hold credentials for more than one tenant's cloud account at the same time. A Soleur-side compromise must by construction be incapable of authorizing actions on any tenant's prod infrastructure other than (at most) the credentials of an active task — and in the steady state, Soleur holds zero long-lived tenant cloud credentials.

**Why hard**: this is the brand-survival threshold (`single-user incident` per brainstorm Phase 0.1). A credential aggregation point at Soleur is a single-event compromise vector across every tenant. The substrate's correctness criterion is the **absence** of such a point.

**Construction**: per-tenant GitHub Actions workflows run inside the **tenant's own** GitHub repository under the tenant's own GitHub org. Each workflow holds — in that repo's secrets / GitHub Environments — exactly that tenant's cloud-account credentials and nothing else. Soleur holds **only** the install-token-mint capability (1-hour TTL, App-scoped to `actions: write` + `metadata: read`, repo-pinned) for the Soleur GitHub App. Soleur cannot, by construction, hold a credential matrix indexed across tenants because each tenant's credentials live exclusively in that tenant's own repo.

This ADR therefore selects **Approach A** from the brainstorm: per-tenant GH Actions OIDC + tenant-owned cloud accounts. Approaches B and C (below under `## Open escape hatches`) are explicitly deferred.

## Validation gate — founder-as-first-tenant

**The validation gate**: Soleur is N=1 — exactly one founder (Jean) has the intent to onboard a non-Soleur project. No external founder has requested this capability. The substrate is being built **anyway** because:

1. The capability is load-bearing for the Soleur trajectory (per brainstorm Phase 0.1 ELT framing).
2. Operator-as-first-tenant is the canonical validation signal — exercising the runbook on a real non-Soleur project before any second tenant exists generates the empirical signal that determines where abstractions actually belong.
3. The cost of building the v1 substrate is bounded (legal pre-flight + audit-log migration + runbook + capability-gap learning) and the cost of being unable to onboard tenant #2 quickly when the moment arrives is unbounded.

**Explicit acknowledgment**: the substrate's abstraction shape is **not yet validated by external founder demand**. The revision-2 plan-review caught and removed three premature abstractions (scaffold template directory, orchestration TS module, cross-tenant integration test against synthesized founders) precisely because the shape these abstractions should take cannot be known at N=1.

**Re-evaluation at N=2**: when Jean's second project (or a first external tenant) arrives, the runbook will have been exercised once. The shape of the right abstraction will be visible. Extract then — not before.

## Open escape hatches — Approach B (CF Worker), Approach C (BYOInfra)

The brainstorm enumerated three candidate approaches. Approach A is chosen above. Approaches B and C are **not rejected** — they are deferred to specific re-evaluation triggers.

### Approach B — CF Worker executor

**Shape**: a Cloudflare Worker (or analogous edge function) per tenant executes the deploy logic from inside a tenant-isolated execution boundary. Soleur ships the worker code; the tenant runs it under their own CF account.

**Why deferred**: at N=1 the GitHub Actions substrate already provides an execution boundary (GH Actions runners are tenant-isolated per the tenant's repo). Adding a Worker layer is premature.

**Re-evaluation trigger**: a tenant requires a deploy execution model that GitHub Actions cannot satisfy — e.g., a deploy that must execute in <30 seconds end-to-end, or a deploy that requires edge-network adjacency to the target infrastructure.

### Approach C — BYOInfra

**Shape**: the tenant operates their own GitHub Actions + cloud accounts entirely; Soleur provides a CLI / OAuth-based "deploy command" that the tenant invokes from their own infrastructure. Soleur never holds even a mint-capable token.

**Why deferred**: at N=1 the GitHub App install-token-mint capability is acceptable under the hard constraint (the 1-hour TTL + App-permission ceiling caps blast radius adequately). Pure BYOInfra adds onboarding friction without proportional risk reduction at this scale.

**Re-evaluation trigger**: a regulated-tenant onboarding demands that Soleur hold zero mint-capable credentials (e.g., a tenant in a highly regulated industry whose security review rejects the 1-hour install-token-mint window).

**Both escape hatches are documented here — not as backlog issues** — because they represent architectural-option deferrals (not capability gaps). Per code-simplicity feedback, filing them as backlog issues confuses "thing we should build" with "alternative shape we chose not to take." The ADR is the canonical location for the latter.

## Prior decision #749 — preserved end-to-end

**Prior decision #749** (CF Tunnel + webhook auth envelope for Hetzner deploy plane) is preserved end-to-end in the multi-tenant substrate. Each tenant's deploy pipeline replicates the #749 pattern inside the tenant's own repo:

- **CF Access service-token at the edge** (Layer 1 auth).
- **HMAC-SHA256 at the webhook** (Layer 2 auth).
- **`webhook` listener as a systemd unit** on the tenant's Hetzner host.

This is the load-bearing operational pattern from `apps/web-platform/infra/firewall.tf:15` + `apps/web-platform/infra/tunnel.tf:1-4` + `apps/web-platform/infra/webhook.service` + `apps/web-platform/infra/hooks.json.tmpl`. Sibling issue #3756 ports it into Soleur-as-tenant-zero's monorepo; this ADR records that all future tenant scaffolds replicate the **same two-auth-layer envelope**. Single-layer auth (CF Access alone, or HMAC alone) is **not acceptable** under the hard constraint — both layers are load-bearing.

Repo-research-analyst's revision-2 finding (spec TR4): the two auth layers are an invariant of the substrate, not an implementation detail. Documenting this invariant in the ADR (rather than only in code comments) ensures future tenant scaffolds inherit the constraint.

## OIDC subject-claim binding — repository_owner + environment

**The OIDC subject-claim binding** for tenant-repo trust policies is fixed at v1:

- Trust `repository_owner:<tenant-org>` (binds to the GitHub organization that owns the tenant repo).
- AND trust `environment:production` (binds to the GitHub Environment used by the deploy job).

Both claims required. Single-claim binding is **not acceptable**:

- `repository_owner` alone would trust any workflow in any repo under the tenant org — too broad.
- `environment` alone is unkeyed to a specific tenant — meaningless across tenants.

Kieran P2-7 selected this two-claim shape as the canonical pattern; this ADR fixes it now (no defer) so all future tenant scaffolds inherit it. Amending requires an ADR amendment, not a per-tenant configuration choice.

**Per-provider subject-claim notes**:

- **Doppler OIDC service-account identity**: trust the same two-claim shape (`repository_owner:<tenant-org>` + `environment:production`). Reference: `https://docs.doppler.com/docs/github-oidc-examples`.
- **Hetzner (no native OIDC)**: `hetznercloud/tps-action` mints short-lived per-job tokens from a long-lived `HCLOUD_TOKEN` repo secret. The OIDC binding does not apply at Hetzner; the equivalent binding is the GitHub Environment + required-reviewers gate on the tenant repo.
- **Cloudflare (no native OIDC)**: scoped account-API token in tenant's GH repo secrets. Same Environment-gated pattern as Hetzner.

## Data-layer reconciliation — founder_id ↔ tenant 1:1

**The data-layer term for "tenant" is `founder_id`**. Repo-research-analyst's revision-2 finding (spec TR5): the codebase has zero `tenant_id` columns; every multi-tenant boundary in the existing schema uses `founder_id` (or `user_id`). Introducing `tenant_id` would create a new term-of-art that diverges from the rest of the codebase.

**Decision**: one founder ↔ one tenant stack at v1. The multi-tenant substrate's audit log uses `founder_id` (not `tenant_id`). One Soleur founder owns one tenant stack; multi-stack-per-founder is **out of v1 scope**.

**Implications**:

- `public.tenant_deploy_audit.founder_id` is a UUID FK to `auth.users(id)` with `ON DELETE RESTRICT` (forcing Art. 17 anonymise to run first; see ADR-028 precedent for the cascade pattern).
- The Phase 2 runbook's "tenant" mental model maps 1:1 to a Soleur founder's identity.
- Re-evaluation trigger for the 1:1 model: a single founder needs to manage multiple independent tenant stacks (e.g., a founder running multiple distinct products). At that point the data layer needs a `stack_id` (or `installation_id` etc.) sub-key. **Out of v1 scope** — explicitly captured here so future schema work knows where to extend.

## Consequences

**Positive**:

- Hard constraint satisfied by construction; Soleur cannot become a credential aggregation point.
- Two-layer auth envelope (#749) preserved end-to-end; existing operational pattern carries forward.
- OIDC subject-claim shape fixed; future tenant scaffolds inherit a consistent trust model.
- Data-layer term (`founder_id`) aligned with existing schema; no term-of-art divergence.
- Revision-2 scope cut (no scaffold template, no orchestration module, no cross-tenant test, no registry table) preserves abstraction flexibility for N=2.

**Negative / accepted**:

- Manual runbook is the orchestration plane at N=1; every new tenant onboarding is a multi-hour human-driven sequence.
- GitHub App install-token-mint capability is a non-zero blast radius (1-hour TTL × `actions: write` × every installed tenant). Mitigated by GitHub Environments + required reviewers on the tenant side (load-bearing per external research).
- Hetzner and Cloudflare have no native OIDC; `tps-action` and scoped account-API tokens are the closest substitutes. Acceptable under the hard constraint because each tenant holds only their own provider tokens in their own GH repo secrets.
- Founder-as-first-tenant validation gate is N=1; design choices may be biased toward Jean's workflow. Mitigated by deferred abstraction extraction at N=2.

## Status

**Accepted** (2026-05-14, per plan revision-2 sign-off).

Re-evaluation triggers (canonical list):

1. First non-Soleur tenant onboarding (full counsel + CTO + CPO re-review).
2. Tenant requires execution model GitHub Actions cannot satisfy → Approach B re-evaluation.
3. Regulated-tenant onboarding requires zero Soleur-held mint-capable tokens → Approach C re-evaluation.
4. Founder needs multiple independent tenant stacks → `founder_id ↔ tenant` 1:1 model extension.
5. Any ToS amendment from {Hetzner, Cloudflare, Doppler, GitHub} affects agent-provisioning posture (per Phase 0 ToS-research artifact).

## References

- Plan: `knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-soleur-managed-deploy-substrate-3723/spec.md`
- LIA: `knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md`
- ToS research: `knowledge-base/legal/tos-research/2026-05-14-tenant-account-provisioning-tos-research.md`
- Prior decision #749 (CF Tunnel + webhook): `apps/web-platform/infra/firewall.tf:15` + `apps/web-platform/infra/tunnel.tf:1-4`.
- Audit-log template: `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:127-216`.
- ADR-028 (DSAR substrate + audit retention precedent).
- External research:
  - Doppler OIDC: `https://docs.doppler.com/docs/github-oidc-examples`
  - Hetzner TPS-action: `https://github.com/hetznercloud/tps-action`
  - Cloudflare CI/CD: `https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/`
  - GitHub Environments: `https://docs.github.com/actions/managing-workflow-runs/reviewing-deployments`
