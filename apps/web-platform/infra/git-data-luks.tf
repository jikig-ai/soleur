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
# (git-data.tf:74-80).
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

resource "doppler_secret" "git_data_luks_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_DATA_LUKS_KEY"
  value      = random_password.git_data_luks.result
  visibility = "masked"
}

# --- The fresh (LUKS-target) block volume -----------------------------------
# A PLAIN ext4 hcloud_volume — cryptsetup reformats it luks2 in the guest on first
# boot (cloud-init isLuks-guards so a 2nd run is a no-op). `format = "ext4"` here is
# only the hcloud-side initial FS; the guest's luksFormat overwrites the LUKS header
# region and mkfs.ext4 lays the real FS INSIDE the mapper. Shape mirrors
# hcloud_volume.git_data (git-data.tf:155-169): separate volume + attachment
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
