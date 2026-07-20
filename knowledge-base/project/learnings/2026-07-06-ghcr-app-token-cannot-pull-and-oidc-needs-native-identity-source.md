---
date: 2026-07-06
category: infrastructure
tags: [ghcr, container-registry, oidc, github-app, machine-identity, zot, supply-chain]
refs: ["#6073", "#6031", "#6122"]
---

# GHCR App tokens can't pull, and "OIDC registry" buys nothing without a native identity source

## Two durable facts established while brainstorming the #6031 minter dead-end (#6073 → #6122)

### 1. A GitHub App installation token CANNOT `docker pull` private repo-linked GHCR packages

This is a **confirmed GitHub platform limitation**, not a misconfiguration. `docker login ghcr.io
-u x-access-token -p <installation-token>` **succeeds**, but `docker pull` returns `denied` — even
with `packages: read` granted, org-owner re-consent, repo linkage, and `repositories:[...]` scoping.
GitHub staff stated it on the record in [community discussion #171423](https://github.com/orgs/community/discussions/171423):
"GHCR does not yet accept GitHub App installation tokens for authentication." Last staff response
Aug 2025; still broken May 2026; no ETA.

Only two credential types pull private GHCR: a **user classic PAT** (`read:packages`) — browser-only
creation, so *not* automatable, no mint API for classic OR fine-grained PATs — and the Actions
**`GITHUB_TOKEN`** (workflow-only). **Implication:** GHCR cannot deliver a zero-touch machine
identity. Do NOT design a control-plane minter around App-token GHCR pulls, and do NOT file a
GitHub support ticket to "find the path" — the answer is already public and definitive.

### 2. "OIDC / workload-identity registry" buys nothing on a bare VM with no native identity issuer

The instinct after fact 1 is "move to an OIDC-federated registry (ECR/GAR/Cloudflare-OIDC)." But
OIDC federation requires the workload to **present a trusted JWT the registry can verify**. AWS EC2
(IMDS-signed role creds), GCP (metadata server), and K8s (kubelet SA tokens) all have a *native
issuer*. A **bare Hetzner VM has none.** So an OIDC registry forces you to **stand up your own IdP**
in the control plane (JWKS issuer, register as trusted IdP, mint per-host JWTs). Since you route
through the control plane anyway, OIDC's "no stored secret" advantage **collapses into the pattern
you already run**: control-plane mints a short-lived credential into your secret store, host reads
it at boot.

**So the real decision is not "which OIDC registry" — it's "which registry exposes an API to mint a
short-lived pull credential" (or validates a control-plane-signed bearer natively).** That is a
registry-substrate swap, not an architecture rewrite: the minter, IaC, and secret wiring all reuse.

## How to apply

- When a machine identity must pull private container images: first check whether the registry
  accepts a *programmatically mintable* credential. GHCR does not (for App tokens; no PAT mint API).
- Don't reach for "OIDC federation" reflexively — verify the workload has a **native token issuer**
  first. On bare VMs it usually doesn't, and the honest mechanism is control-plane-minted bearer.
- **zot** (self-hosted, OCI-native) validates a control-plane-signed OIDC bearer *natively*
  (`config-bearer-oidc-workload.json`) — no bespoke registry-auth code (the risk of an R2+Worker
  DIY registry). In-datacenter placement also satisfies a restricted-egress firewall for free.
