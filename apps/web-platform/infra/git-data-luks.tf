# Epic #5274 Phase 3, Sub-PR 3.D / ADR-068 — the FRESH LUKS-at-rest git-data volume.
#
# The cutover TARGET for git-data-cutover.sh. That script (already committed)
# rsyncs the live bare repos from the Phase-2 PLAINTEXT volume (hcloud_volume.git_data,
# mounted /mnt/git-data == OLD_ROOT) onto THIS fresh volume (mounted
# /mnt/git-data-luks == FRESH_ROOT) under a write-freeze, then flips the
# GIT_DATA_STORE_ENABLED flag. Both volumes are attached to the SAME git-data host
# and mounted SIMULTANEOUSLY during the cutover (additive, non-destructive — the
# plaintext source is the rollback backstop until the DL-2 wipe).
#
# SHARP EDGE — encryption-at-rest is GUEST-SIDE LUKS, NOT an hcloud_volume attribute.
# There is no hcloud "encrypted" flag; the hcloud_volume below is a PLAIN block
# device. cryptsetup luksFormat/luksOpen runs IN THE GUEST at cloud-init
# (cloud-init-git-data.yml), unlocked by the passphrase generated here and delivered
# ONLY as the Doppler-injected env GIT_DATA_LUKS_KEY — never an argv positional,
# never baked into user_data. See cloud-init-git-data.yml's LUKS block.

# --- LUKS passphrase --------------------------------------------------------
# Soleur-generated (no operator-mint TF_VAR — hr-tf-variable-no-operator-mint-default),
# published to Doppler `prd` where the git-data host's boot-time `doppler run` reads
# it as GIT_DATA_LUKS_KEY. special=false keeps it shell/stdin-safe for the
# `printf %s | cryptsetup --key-file -` pipe; length 40 alphanumeric is ~238 bits.
# Mirrors random_password.live_verify_user (live-verify.tf) + doppler_secret shape
# (git-data.tf, doppler_secret.git_transport_ssh_private_key).
#
# Rotation (leak response) is NOT a re-key of an existing LUKS header — it is a full
# volume cutover: `terraform apply -replace=random_password.git_data_luks` mints a
# new passphrase, then a fresh -replace of the git-data host re-luksFormats the (then
# empty) fresh volume and re-runs git-data-cutover.sh from the plaintext source. NO
# ignore_changes — rotation is operator-explicit via -replace.
resource "random_password" "git_data_luks" {
  length  = 40
  special = false
}

# GIT_DATA_LUKS_KEY lands in a DEDICATED `prd_git_data` config (NOT the shared `prd`),
# so the read-only service token handed to the git-data host (below) can read this ONE
# secret and nothing else. Least-privilege (3.D security review MEDIUM / CTO ruling):
# the git-data host runs the client-facing git-shell transport and is a distinct attack
# surface, so it must NOT carry the full-prd token (which would expose
# SUPABASE_SERVICE_ROLE, GIT_REMOVE_SSH_PRIVATE_KEY, and PROXY_TLS_KEY/CERT). Doppler
# tokens are config-scoped, so isolation requires a separate config.
#
# (#6977) The `prd_git_data` branch config, PROVISIONED IN TERRAFORM.
#
# This replaces an OPERATOR NOTE that stood here and was wrong in two ways: it told the
# reader to create the config by hand in the dashboard, and it justified that with "the
# Doppler provider manages environments-and-their-configs as a unit". `doppler_config` is
# a first-class resource in the installed provider (dopplerhq/doppler v1.21.2 — verified
# against `terraform providers schema -json`, which gives it exactly three required
# attributes and two optional inheritance ones this block does not use).
#
# VERIFIED ABSENT 2026-07-27: `GET /v3/configs?project=soleur&environment=prd` returns
# prd, prd_cla, prd_ghcr, prd_kb_drift_walker, prd_scheduled, prd_terraform,
# prd_workspaces_luks — no prd_git_data. Both writes below target it, so without this
# resource the birth apply fails with "Doppler Error: Could not find requested config",
# which is verbatim the failure zot-registry.tf's doppler_environment.registry_prd exists
# to prevent ("REQUIRED for zero-operator provisioning").
#
# SCOPE, PROBED NOT ASSUMED (ADR-130 shape): `var.doppler_token_tf` is the sole
# `provider "doppler"` token and is a PERSONAL token carrying its owner's workplace
# scope. A live `POST /v3/configs` for a throwaway branch config under soleur/prd
# returned 200 with `root:false` — the exact shape this resource needs — and the
# throwaway was deleted. A branch config is a distinct API surface from the
# `doppler_environment` this token already provisions for the registry and inngest, so
# the capability was measured rather than inferred from the sibling.
#
# ALREADY-EXISTS IS AN ERROR, NOT AN ADOPTION — measured the same way: a repeated create
# returns 400 {"messages":["Name is already in use"]}. So if this config is ever created
# by hand first, the birth apply FAILS and the remedy is
# `terraform import doppler_config.git_data_prd soleur.prd_git_data`, NOT a re-dispatch.
# The birth runbook's partial-birth decision tree records this; it is the one failure
# mode the otherwise-additive re-dispatch story does not cover.
#
# NOT in any per-PR `-target` list: this address is an OPERATOR_APPLIED_EXCLUSION like
# every other git-data resource (ADR-103). Giving it a per-PR target would drag
# hcloud_server.git_data into the per-merge plan through upstream closure and trip
# `host_creates > 0`, wedging every merge to main.
resource "doppler_config" "git_data_prd" {
  project     = "soleur"
  environment = "prd"
  name        = "prd_git_data"
}

# Rotate the boot key via `terraform apply -replace=random_password.git_data_luks`.
resource "doppler_secret" "git_data_luks_key" {
  project    = doppler_config.git_data_prd.project
  config     = doppler_config.git_data_prd.name
  name       = "GIT_DATA_LUKS_KEY"
  value      = random_password.git_data_luks.result
  visibility = "masked"
}

# Read-only service token scoped to `prd_git_data` (only GIT_DATA_LUKS_KEY). Handed to
# the git-data host in place of the full-prd `var.doppler_token` so a git-data-host
# compromise reads exactly one secret — restoring the "separate blast radii" property
# git-data.tf already advertises. `.key` is Computed/write-once (same handling as
# doppler_service_token.write / .kb_drift); rotate via
# `terraform apply -replace=doppler_service_token.git_data`.
resource "doppler_service_token" "git_data" {
  project = doppler_config.git_data_prd.project
  config  = doppler_config.git_data_prd.name
  name    = "git-data-luks-boot"
  access  = "read"
}

# --- The fresh (LUKS-target) block volume -----------------------------------
# A PLAIN ext4 hcloud_volume — cryptsetup reformats it luks2 in the guest on first
# boot (cloud-init isLuks-guards so a 2nd run is a no-op). `format = "ext4"` here is
# only the hcloud-side initial FS; the guest's luksFormat overwrites the LUKS header
# region and mkfs.ext4 lays the real FS INSIDE the mapper. Shape mirrors
# hcloud_volume.git_data (git-data.tf, resource "hcloud_volume" "git_data"): separate volume + attachment
# resources, attached to hcloud_server.git_data.
resource "hcloud_volume" "git_data_luks" {
  name     = "soleur-git-data-luks-store"
  size     = var.git_data_luks_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "git_data_luks" {
  volume_id = hcloud_volume.git_data_luks.id
  server_id = hcloud_server.git_data.id
}
