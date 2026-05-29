---
title: "A target-scoped apply workflow silently skips new resources not in its -target= list"
date: 2026-05-29
category: integration-issues
module: web-platform/infra, github-actions
tags: [terraform, doppler, apply-workflow, targeted-apply, kb-drift, secrets, "4570"]
---

# Learning: new tf resources must be added to a targeted-apply workflow's `-target=` list

## Problem

After PR #4570 fixed the KB-drift ingest host + middleware redirect, the route
still returned 500 `{"error":"Server misconfigured"}`. Two env vars the route
reads from the **app runtime** (Doppler `prd`) were never provisioned there:

- `KB_DRIFT_INGEST_SIGNING_KEY` — existed only in `prd_kb_drift_walker` (the
  signer-side blast-radius-scoped config), not in `prd` (the verifier side).
- `KB_DRIFT_OPERATOR_FOUNDER_ID` — existed **nowhere** (only in a test fixture;
  the never-landed AC-PM3 from the original PR-H bootstrap).

Both gaps were latent — the apex-host 405 bug masked them until the handler
became reachable. The route reads from `prd` because that's the app runtime
config (`ci-deploy.sh: doppler secrets download --config prd`).

## Solution

In `apps/web-platform/infra/kb-drift.tf`, add two `doppler_secret` resources
into `config = "prd"`: the signing key sourced from the **same** `random_id`
as the walker-config copy (so a `-replace` rotation cascades to both with no
verifier-freeze / 401-storm), and the founder id from a new sensitive
`variable` (value supplied via `TF_VAR_kb_drift_operator_founder_id` from
Doppler `prd_terraform`; no default → fail-closed per
`hr-tf-variable-no-operator-mint-default`).

## Key Insight (the trap)

`apps/web-platform/infra/`'s apply workflow (`.github/workflows/apply-web-platform-infra.yml`)
runs a **target-scoped** apply: `terraform plan -out=tfplan` with an explicit
`-target=<addr>` allowlist, then `terraform apply tfplan`. **A new resource that
is not in that `-target=` list is planned-but-never-applied — a silent no-op on
merge.** Adding a `doppler_secret` to a `.tf` file is therefore NOT sufficient;
you must also append `-target=doppler_secret.<name>` to the workflow's plan
invocation. `terraform validate` and a local `terraform plan` (no `-target`)
both pass and give no hint that the merge-time apply will skip the resource.

Corollary: before asserting "apply is operator-local / no apply workflow exists"
for an infra root, **grep `.github/workflows/` for an `apply-*-infra` workflow**
— this repo auto-applies `apps/web-platform/infra/**`, `apps/web-platform/infra/sentry/`,
and `infra/github/` on merge. The apply is automated, not manual.

## Session Errors

1. **Planning subagent asserted "no automated apply workflow exists; apply is operator-local."** Recovery: verified `apply-web-platform-infra.yml` exists (it ran green on PR #4570's merge), corrected the plan, and added the required `-target=` lines. Prevention: the plan/deepen flow should grep `.github/workflows/` for an `apply-*-infra` workflow before classifying an infra apply as operator-local.
2. **Targeted-apply silent-skip trap.** A new tf resource omitted from the workflow's `-target=` allowlist would have merged green but never created the secret — the walker would have stayed 500 with no error. Recovery: added both resource addresses to the `-target=` list, cross-checked spelling against the resource names. Prevention: when adding a resource to a root with a targeted-apply workflow, add its `-target=` line in the same PR.
3. **Stale route comment** (route.ts:117-121 claimed the founder id "lives in prd_kb_drift_walker"). Caught by security-sentinel review; fixed inline. Prevention: review's cross-artifact comment check caught it.
