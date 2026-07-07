---
feature: registry-oidc-migration
issue: "#6122"
kind: cto-ruling
date: 2026-07-06
routed_by: /work Phase 1 (architectural-fork routing rule)
adr: ADR-096 (Apply path section)
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
`random_password.zot_pull`, `random_password.zot_push`, `doppler_project.registry`, `doppler_secret.zot_registry_url`,
`doppler_secret.zot_pull_user`, `doppler_secret.zot_pull_token`, `doppler_secret.zot_push_user`,
`doppler_secret.zot_push_token`, `betteruptime_heartbeat.registry_prd`,
`doppler_secret.zot_heartbeat_url_prd`, `doppler_service_token.registry`.

`doppler_service_token.registry` is **additionally** in `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`
(minted into the isolated `soleur-registry` project's `prd` root config — TF-created via
`doppler_project.registry` in the operator full apply — consumed by cloud-init; CI cannot apply it,
no host. **Updated 2026-07-07 (#6122 isolation fix):** the original "operator-created `prd_registry`
config under `prd`" was a leaky branch config that inherited the full `prd` root; replaced by a
dedicated project for true cross-project isolation — see #6167). Its non-vacuity check requires the
resource to exist in a `.tf` (it does, in `zot-registry.tf`).

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

## Rejected alternatives (→ ADR-096 "Apply path")
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

## Second ruling — CI→zot PUSH ingress path (2026-07-06)

**Gap:** the plan's Phase 2 needs GitHub Actions to push to zot, but the registry is deny-all-public
(private-net only) and the ingress path was unspecified (the plan is internally inconsistent —
firewall says "no public ingress", observability referenced a public `https://<zot-host>/v2/`).

**Ruling: Option A — CF Tunnel + CF Access, routed on the EXISTING `web` tunnel; NO cloudflared on
the registry host.** CI bridges with `cloudflared access tcp --hostname registry.<base> --url
127.0.0.1:5000` (auto-insecure to docker → plain-HTTP zot works, no runner `insecure-registries`),
then `docker login 127.0.0.1:5000` (zot-push htpasswd) + push. Mirrors the SSH bridge 1:1. The web
host's cloudflared (already a `10.0.1.0/24` member) proxies to `http://10.0.1.30:5000`. Firewall
UNCHANGED (deny-all-public preserved — traffic arrives via the tunnel, no public port opens). Push
auth = BOTH gates (CF Access service token + zot htpasswd).

**6 new resources → OPERATOR_APPLIED_EXCLUSIONS** (all ride the operator full apply with the host;
an unattended per-PR apply must not mint a push credential + DNS for a host that doesn't exist yet):
`cloudflare_zero_trust_access_application.registry`, `..._service_token.registry_push`,
`..._access_policy.registry_push_service_token`, `cloudflare_record.registry`,
`doppler_secret.registry_push_access_token_id`, `doppler_secret.registry_push_access_token_secret`.
The `..._tunnel_cloudflared_config.web` ingress_rule EDIT rides the already-`-target`ed config
resource (not a new resource). **Total #6122 resources now 24** (18 host-stack + 6 ingress).

**Implementation refinements over the raw ruling:**
- The CF Access token is published to Doppler via `doppler_secret` (operator-applied) with
  **`lifecycle { ignore_changes = [value] }`** — because `cloudflare_...service_token.client_secret`
  is write-once/empty-on-refresh (#4492→#4494 learning). The operator full apply writes it once; a
  later refresh cannot clobber. (The raw ruling said "no ignore_changes"; that holds for the
  random_password-derived zot secrets but NOT for the write-once CF client_secret.)
- CI reads `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET` from Doppler `prd_terraform` at runtime (like
  `CI_SSH_ACCESS_TOKEN_ID/_SECRET`) — NOT a `github_actions_secret` (condition #2 satisfied).

**Observability correction (CTO):** DROP the redundant public `https://<zot-host>/v2/`
`discoverability_test` — the `betteruptime_heartbeat.registry_prd` push-heartbeat is the single
liveness source (needs no ingress). Do NOT add a public HTTP uptime monitor.

**Retirement story unchanged:** Option A only changes the CI→zot push transport (a cloudflared
bridge); zero GHCR dependency introduced. GHCR remains dual-push + break-glass through the soak,
then fully removable.

## Precedent correction (secondary)
The plan/brainstorm named `inngest.tf` as the systemd-host precedent. `inngest.tf` has **no** host
resources — Inngest runs as a unit *on the web host*. The accurate dedicated-host precedent is
**`git-data.tf`** (ADR-068). Design intent (dedicated host, containerized zot, volume-backed) is
unchanged; only the file-to-mirror changed.
