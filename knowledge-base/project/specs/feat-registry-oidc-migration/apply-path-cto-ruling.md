---
feature: registry-oidc-migration
issue: "#6122"
kind: cto-ruling
date: 2026-07-06
routed_by: /work Phase 1 (architectural-fork routing rule)
adr: ADR-093 (Apply path section)
---

# CTO Ruling — Registry-host Terraform apply-path topology

## Why this was routed to the CTO
Mid-work, the plan's AC **P1-2** ("append EVERY new zot resource — including
`hcloud_server.registry` — to `apply-web-platform-infra.yml`'s `-target=` list, else they
silently never apply") was found to **contradict the codebase**: the parity test
`plugins/soleur/test/terraform-target-parity.test.ts` documents that the per-PR CI `-target`
apply "bridges over SSH to the EXISTING web host; it cannot provision a brand-new host, a new
private network, or that host's transport keypair/firewall." The only brand-new-host precedent
(git-data, ADR-068) puts its **entire stack in `OPERATOR_APPLIED_EXCLUSIONS`**, none in `-target`.
Provisioning topology for a new production host at a `single-user-incident` threshold is an
engineering decision with material trade-offs → routed to `soleur:engineering:cto`, not the
non-technical operator.

## Ruling (binding)
**The registry host follows the ADR-068 git-data model: all 16 new resources →
`OPERATOR_APPLIED_EXCLUSIONS`, applied by the operator's initial full (untargeted) `terraform
apply` + the 12h drift detector. ZERO added to the workflow `-target=` list.** Plan AC P1-2 is
**reversed**.

### Per-resource bucket (all → OPERATOR_APPLIED_EXCLUSIONS)
`hcloud_server.registry`, `hcloud_volume.registry`, `hcloud_volume_attachment.registry`,
`hcloud_server_network.registry`, `hcloud_firewall.registry`, `hcloud_firewall_attachment.registry`,
`random_password.zot_pull`, `random_password.zot_push`, `doppler_secret.zot_registry_url`,
`doppler_secret.zot_pull_user`, `doppler_secret.zot_pull_token`, `doppler_secret.zot_push_user`,
`doppler_secret.zot_push_token`, `betteruptime_heartbeat.registry_prd`,
`doppler_secret.zot_heartbeat_url_prd`, `doppler_service_token.registry`.

`doppler_service_token.registry` is **additionally** in `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`
(minted into an operator-created `prd_registry` config, consumed by cloud-init — CI cannot apply
it). Its non-vacuity check requires the resource to exist in a `.tf` (it does, in `zot-registry.tf`).

## Two load-bearing conditions (violating either re-classes a resource to CI-`-target`)
1. **Registry host MUST be cloud-init-only** — no `remote-exec` `terraform_data`. An SSH-provisioned
   `terraform_data` hits the *first* parity guard whose exclusion allowlist is only
   `root_authorized_keys`. Mirror git-data: all host setup in cloud-init.
2. **No zot cred may be published as a `github_actions_secret`.** The CI push workflow (Phase 2)
   MUST read `ZOT_PUSH_*` from Doppler at runtime via `doppler run` — never a `github_actions_secret`
   (that would be the #5566 silent-un-applied class and would force a `-target` line).

## AC #2 reinterpreted
With the stack operator-applied, the per-PR CI **targeted** plan shows **zero** zot resources —
that is correct, not a miss. Rewrite AC #2 as two checks:
- (a) per-PR targeted plan → zero zot resources, zero create/replace of existing infra;
- (b) operator full (untargeted) plan → all 16 as CREATE, zero create/replace of existing infra.

## Rejected alternatives (→ ADR-093 "Apply path")
- **Alt A — per-PR `-target` the whole stack (plan's literal P1-2).** Rejected: contradicts the sole
  brand-new-host precedent; makes unattended per-PR CI provision a host with no operator readiness
  checkpoint; a merge side-effect creating a host violates `hr-fresh-host-provisioning-reachable-from-terraform-apply`.
- **Alt B — new `workflow_dispatch` job (warm_standby-style).** Rejected: warm_standby exists to add a
  host to an existing `for_each` cluster + trigger deploy fan-out; the registry is a standalone
  singleton with neither.
- **Alt C — split creds (CI `-target`s `random_password`/`doppler_secret`, operator provisions host).**
  Rejected: htpasswd is rendered from the `random_password`s at cloud-init; splitting creates a
  two-writer choreography over shared R2 state for zero benefit, and publishes `zot_registry_url`
  before the endpoint exists.

## Precedent correction (secondary)
The plan/brainstorm named `inngest.tf` as the systemd-host precedent. `inngest.tf` has **no** host
resources — Inngest runs as a unit *on the web host*. The accurate dedicated-host precedent is
**`git-data.tf`** (ADR-068). Design intent (dedicated host, containerized zot, volume-backed) is
unchanged; only the file-to-mirror changed.
