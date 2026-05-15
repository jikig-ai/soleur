---
title: GitHub Actions OIDC subject-claim binding — no prior precedent in KB; substrate establishes the canonical two-claim shape
date: 2026-05-14
category: capability-gap
tags:
  - oidc
  - github-actions
  - subject-claim-binding
  - multi-tenant
  - trust-policy
  - capability-precedent
issue: 3723
plan: knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
status: published
---

# Learning: GitHub Actions OIDC subject-claim binding — no prior precedent in KB

## Problem

When designing the multi-tenant deploy substrate (issue #3723), every reviewer and every external research source converged on the same operational invariant: GitHub Actions OIDC trust policies need a **subject-claim binding** scoped tightly enough that a compromised workflow on an unrelated repo cannot mint a token for a tenant's cloud account. The canonical shape from external research is `repo:<org>/<repo>:environment:<env>` or, for cross-repo trust, `repository_owner:<org>:environment:<env>`.

The repo-research-analyst run at plan time surfaced **zero prior OIDC trust-policy learnings** in `knowledge-base/project/learnings/`. The canonical shape was a known industry pattern but the choice between candidate two-claim shapes (`repo` + `environment` vs `repository_owner` + `environment` vs ref-based) was unprecedented in this codebase. Kieran's P2-7 plan-review comment surfaced the gap explicitly: pick the shape now or future tenant scaffolds will each re-litigate the choice.

## Decision (captured in ADR-030)

For the multi-tenant deploy substrate the trust policy on every tenant repo uses the **two-claim binding**:

```text
repository_owner:<tenant-org>  AND  environment:production
```

Both claims required. Neither claim is sufficient alone:

- `repository_owner` alone — trusts any workflow in any repo under the tenant org. Too broad. Any forked-PR workflow on any tenant-org repo could mint a token.
- `environment` alone — unkeyed to a specific tenant. Meaningless across tenants (every tenant uses `environment: production`).
- `ref` (e.g., `ref:refs/heads/main`) — implied by GitHub Environment's deployment-branch-policy (pinned to `main` per runbook Step 7), so adding it explicitly is redundant. The Environment-policy gate is enforced server-side regardless of the OIDC claim shape; relying on a `ref` claim alone (without the Environment gate) is weaker.

## Per-provider notes

- **Doppler** (`https://docs.doppler.com/docs/github-oidc-examples`): trust both claims natively. The Doppler Service Account Identity's OIDC trust config accepts a `subject` field with arbitrary content; setting it to `repository_owner:<tenant-org>:environment:production` is the canonical shape.
- **Hetzner**: no native OIDC. `hetznercloud/tps-action` mints a short-lived per-job token from a long-lived `HCLOUD_TOKEN` repo secret. OIDC subject-claim binding does not apply at Hetzner directly; the equivalent enforcement is the GitHub Environment + required-reviewers gate on the tenant repo (the Environment is the trust boundary, not the OIDC subject).
- **Cloudflare**: no native OIDC. Scoped account-API token in tenant repo secrets. Same Environment-gated pattern as Hetzner.
- **GitHub Actions itself**: the OIDC token GitHub mints for the workflow run carries the standard subject claim shape `repo:<org>/<repo>:environment:<env>` plus extras (`repository_owner`, `ref`, `sha`, etc.). External trust policies (Doppler, AWS, GCP) pick which claims to bind to.

## Why this is a capability-gap learning (not a code-quality learning)

The choice of subject-claim shape is **architectural** and **forward-binding**: every future tenant scaffold must use the same shape, or the substrate's trust model fragments across tenants. The decision is captured in ADR-030 (canonical) and this learning is the breadcrumb pointing back to that ADR from future search queries on "GitHub OIDC subject claim how do we bind this".

## Impact

Future search queries for "OIDC subject claim", "github actions OIDC trust", or "two-claim binding" should land on this learning, which points to ADR-030 §`OIDC subject-claim binding — repository_owner + environment` for the canonical decision. No more rediscovery cost when tenant #2 onboards.

## References

- ADR-030 `## OIDC subject-claim binding — repository_owner + environment`
- Plan: `knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md`
- Doppler OIDC examples: `https://docs.doppler.com/docs/github-oidc-examples`
- GitHub OIDC docs: `https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect`
- Runbook Step 7 (Environment + reviewers): `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md`
