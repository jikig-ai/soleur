# #6122 (ADR-096) — the self-hosted zot container-registry host.
#
# A dedicated Hetzner host running a single zot OCI registry as a docker container
# (digest-pinned upstream image), volume-backed at /var/lib/zot, on the existing
# private network (network.tf). Hetzner web hosts + CI `docker pull` our two private
# platform images from it with a Terraform-generated read-only htpasswd credential
# (zero human mint). Supersedes GHCR for our own images (ADR-096; a GitHub App
# installation token cannot pull private GHCR packages — community #171423).
#
# STRUCTURAL PRECEDENT: git-data.tf (ADR-068), NOT inngest.tf. inngest.tf has no host
# resources — Inngest runs as a unit ON the web host. git-data is the only brand-new
# dedicated-host precedent, so this file mirrors its host/volume/network/firewall/
# heartbeat/scoped-secret shape 1:1.
#
# APPLY-PATH (CTO ruling 2026-07-06, apply-path-cto-ruling.md): every resource here is
# an OPERATOR_APPLIED_EXCLUSION (parity test), applied by the operator's initial full
# (untargeted) `terraform apply` + the 12h drift detector — NONE are in the per-PR CI
# `-target=` list. The per-PR path bridges over SSH to the EXISTING web host; it cannot
# provision a brand-new host. Two load-bearing conditions: (1) cloud-init-only, NO
# `remote-exec` terraform_data (else the SSH-parity guard has no exclusion path); (2) no
# zot cred is a github_actions_secret — Phase-2 CI push reads ZOT_PUSH_* via `doppler run`.
#
# TRANSPORT: HTTP on the private net (deny-all-public firewall below). cosign digest-
# pinning + offline verify is the integrity guarantee (registry-agnostic — Phase-0 spike);
# the private network is the trust boundary (plan's accepted risk: a leaked read-only
# cred is pull-only, in-datacenter, private-network-scoped). Web hosts add the registry to
# docker `insecure-registries` in Phase 3. TLS on the private net is a documented hardening
# follow-up (not in this plan's scope; would add tls_* cert resources + CA distribution).

locals {
  # Fresh private IP in 10.0.1.0/24 — web = .10/.11, git-data = .20, registry = .30.
  registry_private_ip = "10.0.1.30"

  # The registry ref prefix web hosts + CI pull/push against (docker refs carry no
  # scheme). Published as ZOT_REGISTRY_URL.
  registry_endpoint = "${local.registry_private_ip}:5000"

  # zot's OWN image is third-party (upstream project-zot), DIGEST-PINNED, v2.1.2. Pulled from
  # the PUBLIC upstream registry at boot — NEVER from our own zot (bootstrap paradox, Sharp Edges).
  # Arch is DERIVED from var.registry_server_type so a single var switches the whole host: `cax*`
  # (Ampere) → arm64, anything else (`cx*`/`cpx*`) → amd64. This lets provisioning take whichever of
  # cax11 (ARM, €5.99) / cx23 (x86, €5.49) has Hetzner stock — both are functionally identical for a
  # store-and-serve registry (it never RUNS the amd64 platform images it holds). Re-verify BOTH
  # digests on a version bump: `crane digest ghcr.io/project-zot/zot-linux-{arm64,amd64}:vX.Y.Z`.
  registry_arch   = startswith(var.registry_server_type, "cax") ? "arm64" : "amd64"
  zot_image_arm64 = "ghcr.io/project-zot/zot-linux-arm64@sha256:c3fc47782d98b731d5928a24182b495e28cc92f9dcf1d5317f7dbd632e10bf30"
  zot_image_amd64 = "ghcr.io/project-zot/zot-linux-amd64@sha256:073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71"
  zot_image       = local.registry_arch == "arm64" ? local.zot_image_arm64 : local.zot_image_amd64
  # Doppler CLI (v3.75.3) per-arch SHA256 for the cloud-init download (arm64 / amd64).
  doppler_sha256 = local.registry_arch == "arm64" ? "f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143" : "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"

  # Non-secret, stable htpasswd usernames (constants — only the TOKENS are secret).
  zot_pull_user = "zot-pull"
  zot_push_user = "zot-push"
}

# --- Read-only pull + read/write push credentials (TF-generated, zero human mint) ----
# random_password (NOT random_id) → printable, htpasswd/URL-safe. special=false keeps the
# token free of chars that break `docker login -p` / htpasswd. NO ignore_changes anywhere
# downstream (TF owns the values) → rotation via `terraform apply -replace=random_password.zot_pull`
# re-propagates htpasswd + Doppler in ONE apply. Mirrors random_password.git_data_luks.
resource "random_password" "zot_pull" {
  length  = 40
  special = false
}

resource "random_password" "zot_push" {
  length  = 40
  special = false
}

# --- Host-scoped boot credential: the ISOLATED `soleur-registry` project ---------------
# The registry host builds its htpasswd from BOTH tokens at boot, reading them via a
# read-only service token. TRUE isolation requires a boundary that does NOT share the `prd`
# root: a Doppler *branch config* under `prd` (as the original design used) does NOT isolate —
# every config in an environment resolves that environment's ROOT config as its base, so a
# token "scoped" to a `prd` branch config reads the FULL prd secret set (SUPABASE_SERVICE_ROLE_KEY,
# GIT_* keys, PROXY_TLS_* — all 116). Empirically verified (#6122). So the host credential
# lives in a DEDICATED project `soleur-registry` whose own `prd` ROOT config holds ONLY these
# two ZOT tokens; a read token scoped to it resolves exactly two secrets and nothing else.
# This DEPARTS FROM — does not mirror — the `prd_git_data` / `prd_kb_drift_walker` branch-config
# pattern, which has the identical non-isolation bug (audit + remediation tracked in #6167).
# (A standalone *environment* in `soleur` was rejected: the project is at the 4-environment
# tier cap — dev/prd/ci/cli — so a 5th env is impossible without a Doppler Team-plan upgrade.)
#
# PROVISIONING (fully automated — ZERO operator CLI actions, per
# hr-fresh-host-provisioning-reachable-from-terraform-apply): the agent's `terraform apply` stands
# the whole isolation boundary up from empty state. Terraform creates the isolated project
# (`doppler_project.registry`) AND its `prd` environment + root config (`doppler_environment.registry_prd`),
# then writes the two host secrets + the boot token into that config. var.doppler_token_tf is a
# workplace-scope personal token (create-project + create-environment scope). Rotate via
# `terraform apply -replace=random_password.zot_pull`.
resource "doppler_project" "registry" {
  name        = "soleur-registry"
  description = "Isolated boot-credential project for the zot registry host (#6122, ADR-096) — its `prd` root config holds ONLY the two ZOT htpasswd tokens; cross-project isolation from soleur/prd (no shared root-secret resolution path)."
}

# The `prd` environment + its root config inside the isolated project. REQUIRED for zero-operator
# provisioning: a TF-created `doppler_project` is created BARE (no default dev/stg/prd configs that
# the Doppler CLI/dashboard would auto-add), so without this the host secrets below fail at apply
# with "Doppler Error: Could not find requested config 'prd'" (#6122 provisioning). Creating the
# environment also creates its same-named root config, which is the isolation boundary the host
# boot token resolves. Does NOT need the paid config-inheritance feature (#6067) — it is a basic
# Project-Structure resource, not a branch config.
resource "doppler_environment" "registry_prd" {
  project = doppler_project.registry.name
  slug    = "prd"
  name    = "Production"
}

resource "doppler_secret" "zot_pull_token_registry" {
  project    = doppler_project.registry.name
  config     = doppler_environment.registry_prd.slug
  name       = "ZOT_PULL_TOKEN"
  value      = random_password.zot_pull.result
  visibility = "masked"
}

resource "doppler_secret" "zot_push_token_registry" {
  project    = doppler_project.registry.name
  config     = doppler_environment.registry_prd.slug
  name       = "ZOT_PUSH_TOKEN"
  value      = random_password.zot_push.result
  visibility = "masked"
}

# Read-only service token scoped to the isolated `soleur-registry` project's `prd` ROOT config
# (only the two ZOT tokens). Handed to the registry host cloud-init in place of the full-prd
# var.doppler_token. `.key` is Computed/write-once (same handling as doppler_service_token.git_data);
# rotate via `terraform apply -replace=doppler_service_token.registry`.
resource "doppler_service_token" "registry" {
  project = doppler_project.registry.name
  config  = doppler_environment.registry_prd.slug
  name    = "zot-registry-boot"
  access  = "read"
}

# --- Client/CI-facing secrets: the shared `prd` config ---------------------------------
# Web hosts (pull) + CI (push) read these from `prd`, their existing runtime/deploy config.
# TF owns the values → NO ignore_changes (mirrors the ghcr-minter-doppler-token.tf shape, NOT
# ghcr-read-credential.tf's operator-minted ignore_changes shape).
resource "doppler_secret" "zot_registry_url" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_REGISTRY_URL"
  value      = local.registry_endpoint
  visibility = "masked"
}

resource "doppler_secret" "zot_pull_user" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PULL_USER"
  value      = local.zot_pull_user
  visibility = "masked"
}

resource "doppler_secret" "zot_pull_token" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PULL_TOKEN"
  value      = random_password.zot_pull.result
  visibility = "masked"
}

resource "doppler_secret" "zot_push_user" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PUSH_USER"
  value      = local.zot_push_user
  visibility = "masked"
}

resource "doppler_secret" "zot_push_token" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PUSH_TOKEN"
  value      = random_password.zot_push.result
  visibility = "masked"
}

# --- The registry host -----------------------------------------------------------------
resource "hcloud_server" "registry" {
  name        = "soleur-registry"
  server_type = var.registry_server_type # cax11 (arm64) / cx23 (amd64) — arch derived in locals
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Public IPv4/IPv6 for EGRESS only (apt + the upstream zot image pull during cloud-init).
  # A no-public-IP host has NO internet (no NAT gateway). INGRESS on the public interface is
  # denied by hcloud_firewall.registry below; pull transport is private-net only. Mirrors
  # git-data.tf's public_net rationale.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # base64gzip-first (git-data.tf / ADR-080 #5927): wrap the whole render so the shell
  # payload compresses under Hetzner's 32,768-byte user_data cap. zot's cloud-init is small
  # (docker + one container + htpasswd gen; no bake-and-extract), but budget for it anyway
  # and verify the byte-exact size at the first `terraform plan`. Hetzner base64-decodes →
  # gzip magic → cloud-init auto-gunzips → byte-identical #cloud-config (DataSourceHetzner).
  user_data = base64gzip(templatefile("${path.module}/cloud-init-registry.yml", {
    # Mount the zot storage volume by its specific id (server.tf/cloud-init.yml by-id
    # pattern). Known at plan time; the attachment is a separate resource.
    registry_volume_id = hcloud_volume.registry.id
    # Scoped read-only Doppler token → 0600 root env file so the boot-time `doppler run`
    # can read ZOT_PULL_TOKEN/ZOT_PUSH_TOKEN and build htpasswd. The tokens themselves are
    # NEVER in this user_data (retrievable via the hcloud metadata API).
    doppler_token = doppler_service_token.registry.key
    # zot's digest-pinned upstream image + the fixed htpasswd usernames (non-secret).
    zot_image     = local.zot_image
    zot_pull_user = local.zot_pull_user
    zot_push_user = local.zot_push_user
    # Host arch (arm64/amd64) → the matching Doppler CLI release build + its checksum.
    doppler_arch   = local.registry_arch
    doppler_sha256 = local.doppler_sha256
  }))

  # Deliberately NO lifecycle.ignore_changes=[user_data]. A FRESH host has no spurious diff,
  # and omitting it preserves a clean replace-to-reprovision path (git-data.tf rationale) —
  # so a zot config change re-applies via cloud-init re-provision (cloud-init is idempotent).

  labels = {
    app = "soleur-web-platform"
  }
}

# --- zot storage block volume ----------------------------------------------------------
# The OCI blobs (both platform images + backfilled release tags + cosign .sig referrers)
# live here — never tmpfs (a wiped registry breaks cold-boot pulls). dedupe is on, so a
# small volume is ample. Shape mirrors hcloud_volume.git_data.
resource "hcloud_volume" "registry" {
  name     = "soleur-registry-store"
  size     = var.registry_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "registry" {
  volume_id = hcloud_volume.registry.id
  server_id = hcloud_server.registry.id
}

# --- Deny-all PUBLIC ingress firewall --------------------------------------------------
# ZERO inbound rules = deny-all on the PUBLIC interface. Hetzner firewalls filter only the
# public interface; intra-hcloud_network traffic (web hosts pulling on 10.0.1.0/24) is open
# by network membership and needs NO allow rule. NO public ingress for the registry — pull
# transport is private-net only. Egress (apt + upstream zot image pull) is unaffected by
# inbound rules. Mirrors hcloud_firewall.git_data exactly.
resource "hcloud_firewall" "registry" {
  name = "soleur-registry"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_firewall_attachment" "registry" {
  firewall_id = hcloud_firewall.registry.id
  server_ids  = [hcloud_server.registry.id]
}

# --- Liveness (PUSH heartbeat) ---------------------------------------------------------
# Better Stack cannot PULL a deny-all-public-ingress host, so liveness is a PUSH heartbeat:
# a web-host cron probes zot `/v2/` over the private net and pings this heartbeat URL on
# success; absence-of-ping alerts. Shape mirrors betteruptime_heartbeat.git_data_prd.
#
# paused = true initially (same rationale as git_data_prd / inngest_prd): until the web-host
# probe cron is wired + deployed (Phase-3/soak wiring), the gap between apply and the first
# ping would fire a false alert. Unpause via the Better Stack UI once the probe ships.
resource "betteruptime_heartbeat" "registry_prd" {
  name      = "soleur-registry-prd"
  period    = 60
  grace     = 30
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  # Literal case-sensitive team name (see inngest.tf / git-data.tf).
  team_name = "Your team"
  # Reuse the existing inngest escalation policy (git-data.tf does the same) — no new policy.
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  paused     = true
  sort_index = 0

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies (git-data.tf rationale).
    ignore_changes = [paused]
  }
}

# Heartbeat URL → Doppler prd, so the (Phase-3/soak) web-host probe cron can read it via the
# server's existing `doppler secrets download` flow. Mirrors doppler_secret.git_data_heartbeat_url_prd.
resource "doppler_secret" "zot_heartbeat_url_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_HEARTBEAT_URL"
  value      = betteruptime_heartbeat.registry_prd.url
  visibility = "masked"
}
