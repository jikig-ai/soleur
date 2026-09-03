# (#7025) The throwaway rung-2 rehearsal host and everything it needs to boot.
#
# EVERY ADDRESS IN THIS FILE CARRIES `.rehearsal` IN ITS NAME, and that is a mechanical
# contract rather than a naming convention: git-data-rung2-rehearsal.test.sh asserts that
# every hcloud_* and doppler_* address in this root matches `\.rehearsal\b`. An address
# without it is either a typo or a prod resource that wandered in, and the two are
# indistinguishable at review speed.
#
# ONLY THE IDENTITY IS THROWAWAY, NOT THE MECHANISM. The volumes are real Hetzner volumes and
# the passphrase is a real random_password in a real (scratch) Doppler config, because the
# thing under test is `cryptsetup luksOpen` succeeding against a device the guest formats on
# first boot. A stub volume id was the shortcut an earlier draft proposed; it makes luksOpen
# fail, which lands in the capture script's FAIL arm — it would rehearse the failure path and
# report it as the success path never having been tried.

locals {
  # The trailing hyphen before the run id is LOAD-BEARING everywhere this prefix is matched:
  # `soleur-git-data` is a PREFIX of `soleur-git-data-rehearsal-…`, so an unanchored glob
  # written the other way round matches the PRODUCTION host. The orphan sweep in
  # scheduled-terraform-drift.yml pins the same literal for the same reason.
  rehearsal_host_name = "soleur-git-data-rehearsal-${var.rehearsal_run_id}"
}

# --- Throwaway SSH key -------------------------------------------------------
# NOT an access path — nothing in this route SSHes to the rehearsal host, and the runbook
# carries no SSH fallback (hr-no-ssh-fallback-in-runbooks). It exists because a Hetzner
# server created with no `ssh_keys` gets a ROOT PASSWORD MAILED to the account owner, which
# is a credential for a host holding a LUKS passphrase, delivered over email, outliving the
# host. A throwaway key that is destroyed with the root is strictly less material at rest.
resource "tls_private_key" "rehearsal" {
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "rehearsal" {
  name       = local.rehearsal_host_name
  public_key = tls_private_key.rehearsal.public_key_openssh

  labels = {
    app = "soleur-rung2-rehearsal"
  }
}

# --- The scratch Doppler config ----------------------------------------------
# A DISTINCT config, and this is what forces the one permitted cloud-init edit (R1). The boot
# service token is scoped to exactly one config; measured under an identically-scoped token,
# naming a config the token does not cover exits 1 with the key ABSENT, so `doppler run` never
# execs the LUKS heredoc, its `set -euo pipefail` runs ZERO times, luksOpen never runs, and
# the host boots dark with sshd up (#6982 W0). A rehearsal against a hardcoded `prd_git_data`
# would reproduce that exact failure — and would look like a rehearsal finding rather than a
# fixture bug.
#
# It also means a rehearsal-host compromise reads NOTHING of production's: not the prod LUKS
# passphrase, not service-role, not GIT_REMOVE or PROXY_TLS material.
resource "doppler_config" "rehearsal" {
  project     = "soleur"
  environment = "prd"
  name        = "prd_git_data_rehearsal_${var.rehearsal_run_id}"
}

resource "random_password" "rehearsal_luks" {
  length  = 48
  special = false
}

resource "doppler_secret" "rehearsal_luks_key" {
  project    = doppler_config.rehearsal.project
  config     = doppler_config.rehearsal.name
  name       = "GIT_DATA_LUKS_KEY"
  value      = random_password.rehearsal_luks.result
  visibility = "masked"
}

# The same INGEST token prod's config holds. Write-only against shared source 2457081, so
# sharing it with a throwaway host yields no readback. Prod's copy carries
# `ignore_changes = [value]` because rotation is managed at the source of truth; this config
# is destroyed within the hour, so there is no rotation window to protect.
resource "doppler_secret" "rehearsal_betterstack_logs_token" {
  project    = doppler_config.rehearsal.project
  config     = doppler_config.rehearsal.name
  name       = "BETTERSTACK_LOGS_TOKEN"
  value      = var.betterstack_logs_token
  visibility = "masked"
}

resource "doppler_service_token" "rehearsal" {
  project = doppler_config.rehearsal.project
  config  = doppler_config.rehearsal.name
  name    = "git-data-rung2-rehearsal-${var.rehearsal_run_id}"
  access  = "read"
}

# --- The two volumes ---------------------------------------------------------
# Both mirror prod's declaration exactly: a PLAIN ext4 hcloud_volume in each case. The guest's
# cryptsetup luksFormat overwrites the LUKS header region on the second one and lays the real
# filesystem INSIDE the mapper — so `format = "ext4"` here is only the hcloud-side initial FS,
# and rehearsing anything else would rehearse a boot that does not exist.
resource "hcloud_volume" "rehearsal" {
  name     = "${local.rehearsal_host_name}-store"
  size     = var.git_data_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-rung2-rehearsal"
  }
}

resource "hcloud_volume" "rehearsal_luks" {
  name     = "${local.rehearsal_host_name}-luks"
  size     = var.git_data_luks_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-rung2-rehearsal"
  }
}

# --- Deny-all firewall -------------------------------------------------------
# Zero rules, same shape as hcloud_firewall.git_data. The host needs public EGRESS (apt,
# GitHub, the Doppler CDN, Sentry, Better Stack) and zero public ingress; Hetzner firewalls
# filter ingress only, so an empty rule set is exactly "publish nothing".
#
# This is now the ONLY network control that matters here, because R2 removed the private-net
# attachment entirely — there is no intra-network surface left for it to fail to cover.
resource "hcloud_firewall" "rehearsal" {
  name = local.rehearsal_host_name

  labels = {
    app = "soleur-rung2-rehearsal"
  }
}

# --- The render, from the SHARED module --------------------------------------
# The same module hcloud_server.git_data renders from. This is what makes the evidence
# meaningful: the bytes that boot here are the same template and the same nine payloads the
# rung-2 gate hashes, so the hash in the evidence file is a hash OF WHAT BOOTED.
#
# Only identity-shaped vars diverge, and the set below is exactly
# GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST in tests/scripts/lib/git-data-birth-readiness-gate.sh.
# The capture script writes that same set into RUNG2_VAR_DIVERGENCE and the gate refuses
# anything outside it — so this block and that allowlist are bound, not merely consistent.
module "git_data_userdata" {
  source = "../modules/git-data-userdata"

  # MAY DIVERGE — identity only.
  host_name               = local.rehearsal_host_name
  git_data_volume_id      = hcloud_volume.rehearsal.id
  git_data_luks_volume_id = hcloud_volume.rehearsal_luks.id
  doppler_token           = doppler_service_token.rehearsal.key
  doppler_config_name     = doppler_config.rehearsal.name
  git_transport_pubkey    = trimspace(tls_private_key.rehearsal.public_key_openssh)
  git_provision_pubkey    = trimspace(tls_private_key.rehearsal.public_key_openssh)
  git_remove_pubkey       = trimspace(tls_private_key.rehearsal.public_key_openssh)

  # MUST MATCH PROD — these change WHAT the host does, not WHICH host it is.
  # The Doppler arch token and its checksum are NOT passed: the module derives both from the
  # server type, so the pair exists once for both roots and cannot diverge. It used to be a
  # local ternary here, i.e. a fourth uncompared copy of the checksum literals — a version bump
  # applied to git-data.tf alone left every suite green while this root verified a different
  # binary (#6570 class).
  git_data_server_type   = var.git_data_server_type
  sentry_dsn             = var.sentry_dsn
  betterstack_ingest_url = var.betterstack_ingest_url
  # (#7460) MUST MATCH PROD, and deliberately NOT a declarable divergence. Prod and rehearsal
  # ship their stage markers to the SAME Better Stack source, exactly as sentry_dsn and
  # betterstack_ingest_url already do — neither of which is on the divergence allowlist
  # either. Adding this one to that allowlist would permit a rehearsal that shipped to a
  # DIFFERENT sink than production while still producing hash-valid evidence, which is the
  # one thing the allowlist exists to refuse.
  betterstack_logs_token = var.betterstack_logs_token
}

# --- The host ----------------------------------------------------------------
# CLOUD-INIT ONLY. No remote-exec provisioner and no in-place patch path, matching
# git-data.tf's own posture — the host is created fresh, boots once, is measured off-box, and
# is destroyed. Anything that reached in over SSH to fix a boot would be measuring a boot that
# production will not get.
resource "hcloud_server" "rehearsal" {
  name        = local.rehearsal_host_name
  server_type = var.git_data_server_type
  location    = var.location
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.rehearsal.id]

  # Public IPv4/IPv6 for EGRESS only. A no-public-IP host has NO internet in this account (no
  # NAT gateway exists), so `apt-get install git` in the bootstrap would fail and the boot
  # would die for an infrastructure reason that has nothing to do with the template under
  # test. Ingress is denied by hcloud_firewall.rehearsal.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  user_data = base64gzip(module.git_data_userdata.rendered)

  # NO `lifecycle.ignore_changes` anywhere in this root. The host is cattle by construction —
  # it exists for one boot — so there is no drift to suppress, and suppressing user_data drift
  # in particular would let a rehearsal re-report a stale boot as a fresh one.

  # Order the passphrase BEFORE the host boots. Same edge git-data.tf carries, for the same
  # reason: doppler_service_token.rehearsal is upstream because its .key is baked into
  # user_data, but a token is only an AUTHORIZATION TO READ the config — it says nothing about
  # the config CONTAINING the key. Without this, terraform is free to create the host first,
  # `doppler run` returns a config with no GIT_DATA_LUKS_KEY, luksOpen fails, and the
  # rehearsal reports a FAIL that is an artifact of its own scheduling rather than a finding
  # about the template.
  depends_on = [doppler_secret.rehearsal_luks_key, doppler_secret.rehearsal_betterstack_logs_token]

  labels = {
    app = "soleur-rung2-rehearsal"
  }
}

resource "hcloud_volume_attachment" "rehearsal" {
  volume_id = hcloud_volume.rehearsal.id
  server_id = hcloud_server.rehearsal.id
  automount = false
}

resource "hcloud_volume_attachment" "rehearsal_luks" {
  volume_id = hcloud_volume.rehearsal_luks.id
  server_id = hcloud_server.rehearsal.id
  automount = false
}

resource "hcloud_firewall_attachment" "rehearsal" {
  firewall_id = hcloud_firewall.rehearsal.id
  server_ids  = [hcloud_server.rehearsal.id]
}
