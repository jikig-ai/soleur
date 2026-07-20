---
date: 2026-07-06
category: workflow-patterns
tags: [plan-review, verify-capability-claim, hr-verify-repo-capability-claim-before-assert, infra, zot, nomad]
refs: ["#6122", "#6126", "ADR-027", "ADR-068"]
---

# Verify the deployment substrate AND vendor auth capability before committing a plan's shape

Two capability claims shaped the first draft of the #6122 registry-migration plan; **both were
false**, and each was caught by a different verification, not by the drafting itself.

## 1. Deployment substrate — asserted "Nomad HA job" from target-state C4 prose

The draft designed zot as an "HA Nomad job, mirroring the existing web/CLI-engine jobs." There is
**no orchestrator in this system** — `ADR-027`: "No orchestrator (Kubernetes, Nomad, Docker Swarm)
is in use… `ci-deploy.sh` starts exactly one named container per host." Nomad is **post-GA**
(`ADR-068` Phase 4a). The claim came from `model.c4`'s `hetzner` description, which models the
*target* state ("Nomad clients") — C4 diagrams often describe where the system is going, not where
it is. The real precedent (Inngest) deploys as **systemd units**. A `grep` for `.nomad` specs / a
read of ADR-027 would have caught it before the HA/SPOF/bootstrap/cost sections were all built on it.

## 2. Vendor auth capability — asserted "zot has native OIDC bearer workload auth"

The brainstorm asserted zot could validate a control-plane-minted JWT natively (from a fuzzy
memory + a misread search hit `config-bearer-oidc-workload.json`). zot's actual machine-auth
(verified against zot docs): **htpasswd** (bcrypt + read-only ACL) or **bearer via an external
Docker-v2 token server you build yourself**. No native JWT/OIDC workload mode. The correction made
the design *simpler* — a Terraform `random_password` htpasswd credential is zero-touch, needs no
minter and no token server.

## How to apply (`hr-verify-repo-capability-claim-before-assert`)

- **Before a plan's shape depends on a substrate/orchestrator/service existing, grep for it** —
  `grep -rn nomad apps/*/infra`, read the governing ADR (`ADR-027`/`ADR-068`), find the closest
  shipped precedent. C4/brainstorm prose describing "the cluster" may be target-state, not current.
- **Before a plan's shape depends on a vendor doing X, verify X against the vendor's own docs**
  (WebFetch the canonical page), not memory or a search-snippet. This is the same class as the
  many plan Sharp Edges about verifying runtime shape against installed/canonical source.
- **The convergence dividend:** here the simplicity-review cut (drop HA + R2) and the architecture
  finding (no Nomad; multi-writer-R2 unsafe) *converged* on the same simpler design. When an
  independent YAGNI cut and an independent correctness finding point the same way, that's strong
  signal the simpler design is also the more correct one. See
  [[2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source]].
