# Epic #5274 Phase 2 PR B / ADR-068 — the git-data host (multi-host /workspaces).
#
# A dedicated Hetzner host that stores the per-workspace BARE git repos (objects +
# refs) and enforces the writer-side CAS fence (ADR-068 §3). The web host keeps
# worktrees on local NVMe and pushes to this host over the private net
# (network.tf). At replicas=1 the fence is live-but-non-rejecting; it becomes
# load-bearing at Phase 3's second writer.
#
# Apply-path note: cloud-init-only (NO remote-exec provisioner). The CI runner
# cannot SSH either host, so any provisioner here would hang the merge-triggered
# auto-apply. `terraform apply` returns green on server CREATE without waiting for
# cloud-init; the post-merge readiness/cutover script (web-host-driven, over the
# private net) verifies git + bare-repo root + hook are live BEFORE cutover
# (hr-fresh-host-provisioning-reachable-from-terraform-apply).

# --- In-band transport keypair (ED25519) ------------------------------------
# DEDICATED key — NOT reused from tls_private_key.ci_ssh. Mirrors the ci-ssh-key.tf
# shape (tls_private_key.ci_ssh + the trimspace() local + doppler_secret). The
# public half goes onto the git-data host (cloud-init authorized_keys, git-shell
# forced-command); the private half goes to Doppler for git-auth.ts to consume.
#
# Intentionally a single throwaway shared key (the Phase-2 floor: one web host,
# git-shell-scoped). Phase 3's per-workspace_id mTLS (ADR-068 §6) REPLACES it; it
# is NOT a cluster-wide mount credential, so the Phase-3 swap is additive-then-
# remove (the Phase-3 plan must plan its removal).
resource "tls_private_key" "git_transport" {
  algorithm = "ED25519"
}

# --- In-band PROVISION keypair (ED25519) ------------------------------------
# A SECOND, dedicated key — SEPARATE from tls_private_key.git_transport (ADR-068
# amendment 2026-07-01 "PR B bare-repo provisioning"). Its cloud-init forced
# command is the FIXED `git-data-provision.sh` (idempotent `git init --bare`),
# NEVER git-shell. Provisioning authority and ref-write authority are separate
# credentials with separate blast radii (ADR-068 §6): a leaked transport key
# cannot fabricate repos, and a leaked provision key cannot write refs. Same OS
# `git` user (per-key command= overrides the login shell). Same throwaway-shape as
# git_transport; Phase 3's per-workspace_id mTLS replaces both.
resource "tls_private_key" "git_provision" {
  algorithm = "ED25519"
}

locals {
  # trimspace() strips the trailing newline tls_private_key.public_key_openssh
  # carries — without it the cloud-init authorized_keys line renders with a
  # trailing blank, breaking the forced-command entry. Same rationale as
  # local.ci_ssh_pubkey (ci-ssh-key.tf).
  git_transport_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)
  git_provision_pubkey = trimspace(tls_private_key.git_provision.public_key_openssh)
}

# Private half → Doppler. Consumed at RUNTIME by the web host's git-auth.ts, which
# is configured from Doppler `prd` (prd values are baked into the container env at
# start) — NOT `prd_terraform` (that config feeds the CI/terraform deploy pipeline,
# which is where doppler_secret.deploy_ssh_private_key correctly lives because it is
# a DEPLOY-time key). This is a RUNTIME key, so it belongs in `prd`. The TF doppler
# token demonstrably writes `prd` (see doppler_secret.git_data_heartbeat_url_prd
# below). NOT cloud-init — the web host carries ignore_changes=[user_data], so
# cloud-init can never reach the running container.
resource "doppler_secret" "git_transport_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_TRANSPORT_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_transport.private_key_openssh
  visibility = "masked"
}

# Provision key private half → Doppler `prd` (RUNTIME key; same rationale as
# git_transport above). Consumed by git-data-replication.ts (sshWithPrivateKeyAuth)
# to reach the `git-data-provision.sh` forced command before the first push.
resource "doppler_secret" "git_provision_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_PROVISION_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_provision.private_key_openssh
  visibility = "masked"
}

# --- The git-data host -------------------------------------------------------
resource "hcloud_server" "git_data" {
  name        = "soleur-git-data"
  server_type = var.git_data_server_type # cax11 = ARM64 (Ampere); git/sshd are ARM-native
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # P0 — public IPv4/IPv6 for EGRESS only (apt + GitHub during cloud-init). A
  # no-public-IP host has NO internet (no NAT gateway exists in this account), so
  # `apt-get install git` in the bootstrap would fail. INGRESS on the public
  # interface is denied by hcloud_firewall.git_data below; transport is private-
  # net only.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  user_data = templatefile("${path.module}/cloud-init-git-data.yml", {
    git_data_bootstrap_b64               = base64encode(file("${path.module}/git-data-bootstrap.sh"))
    git_data_pre_receive_placeholder_b64 = base64encode(file("${path.module}/git-data-pre-receive-placeholder.sh"))
    # The FIXED provision forced-command wrapper (git init --bare), delivered to
    # /usr/local/bin like the bootstrap (ADR provisioning amendment).
    git_data_provision_b64 = base64encode(file("${path.module}/git-data-provision.sh"))
    # trimspace()'d — see local.git_transport_pubkey / local.git_provision_pubkey.
    git_transport_pubkey = local.git_transport_pubkey
    git_provision_pubkey = local.git_provision_pubkey
    # Mount the bare-repo volume by its specific id (server.tf/cloud-init.yml
    # by-id pattern). Known at plan time; the attachment is a separate resource.
    git_data_volume_id = hcloud_volume.git_data.id
  })

  # Deliberately NO lifecycle.ignore_changes=[user_data]. The web host carries it
  # only as an IMPORT ARTIFACT (server.tf:66-72); a FRESH host has no spurious
  # diff, and omitting it preserves a clean replace-to-reprovision path during the
  # fence-iteration window (P1).

  labels = {
    app = "soleur-web-platform"
  }
}

# --- Bare-repo block volume --------------------------------------------------
# The bare repos AND the per-(workspace,worktree) fence sidecar/lock live here —
# never tmpfs (a reboot resetting the fence max to 0 would let a stale writer
# win). Shape mirrors hcloud_volume.workspaces (server.tf:926-940).
resource "hcloud_volume" "git_data" {
  name     = "soleur-git-data-store"
  size     = var.git_data_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "git_data" {
  volume_id = hcloud_volume.git_data.id
  server_id = hcloud_server.git_data.id
}

# --- Deny-all PUBLIC ingress firewall ----------------------------------------
# ZERO inbound rules = deny-all on the PUBLIC interface (P1). Hetzner firewalls
# filter only the public interface; intra-hcloud_network traffic (the web host's
# git transport + liveness probe on 10.0.1.0/24) is open by network membership
# and needs NO allow rule. NO inbound SSH/git rule on the public interface —
# private-net transport only. Egress (apt/GitHub) is unaffected by inbound rules.
resource "hcloud_firewall" "git_data" {
  name = "soleur-git-data"

  labels = {
    app = "soleur-web-platform"
  }
}

# Separate attachment resource (mirrors hcloud_firewall_attachment.web,
# firewall.tf:91-94) rather than an inline apply_to block.
resource "hcloud_firewall_attachment" "git_data" {
  firewall_id = hcloud_firewall.git_data.id
  server_ids  = [hcloud_server.git_data.id]
}

# --- Liveness (PUSH heartbeat) -----------------------------------------------
# Better Stack cannot PULL a deny-all-public-ingress host, so liveness is a PUSH
# heartbeat: a web-host cron probes git-data over the private net (git ls-remote /
# ssh) and pings this heartbeat URL on success; absence-of-ping alerts. Shape
# mirrors betteruptime_heartbeat.inngest_prd (inngest.tf:258-288).
#
# paused = true initially (same rationale as inngest_prd): until the web-host
# probe cron is wired + deployed, the gap between apply (Better Stack starts
# expecting a ping within `grace`) and the first ping would fire a false alert.
# Unpause via the Better Stack UI (or flip in a follow-up) once the probe ships.
resource "betteruptime_heartbeat" "git_data_prd" {
  name      = "soleur-git-data-prd"
  period    = 60
  grace     = 30
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  # Literal name of the only team in this Better Stack workplace (case-sensitive
  # provider lookup) — see inngest.tf:267-271.
  team_name  = "Your team"
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  paused     = true
  sort_index = 0

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies (mirrors
    # betteruptime_heartbeat.inngest_prd).
    ignore_changes = [paused]
  }
}

# Heartbeat URL → Doppler prd, so the (follow-up) web-host probe cron can read it
# via the server's existing `doppler secrets download` flow. Mirrors
# doppler_secret.inngest_heartbeat_url_prd (inngest.tf:313-319).
#
# TODO(#5274 PR C / follow-up): the web-host probe cron itself (git ls-remote over
# the private net to 10.0.1.20, then curl GIT_DATA_HEARTBEAT_URL on success) needs
# ci-deploy wiring (a systemd timer like inngest-heartbeat.timer). This resource +
# the URL secret are the IaC deliverable here; the probe script is the follow-up.
resource "doppler_secret" "git_data_heartbeat_url_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_DATA_HEARTBEAT_URL"
  value      = betteruptime_heartbeat.git_data_prd.url
  visibility = "masked"
}
