# #8285 (PR A of the plaintext-backstop retirement) -- the throwaway wipe host. WHOLE FILE DELETED by
# PR B once the destroy phase has shown the volume gone (point-in-time apparatus; the procedure as run
# stays in git history at the PR A merge SHA).
#
# WHY A SEPARATE HOST. The dedicated Inngest host has no SSH and its only inbound channel is a
# Doppler-flag-polled FSM baked into the bootstrap image; a wipe there would need an image release, a
# pin bump and an approved host replace (a cron outage on the sole scheduler), and would run beside the
# LIVE encrypted volume. This host is created in the same hel1 location, gets ONLY the retired
# plaintext volume attached (never the live LUKS volume, so a mis-resolved device cannot reach the live
# store), zeroes it with `blkdiscard -z`, reads it back O_DIRECT, ships one evidence row to Better
# Stack, and is destroyed by step B of the same dispatch.
#
# NOTHING HERE RUNS ON MERGE. Both resources are count = 0 unless var.inngest_backstop_wipe_enabled is
# true, and the per-merge `-target` apply never names them. Only the reviewer-gated
# `apply_target=inngest-backstop-retire` dispatch (phase=wipe) sets the flag; its plan gate demands
# exactly these two creates and asserts the attachment's volume_id against the dispatch's id-pin.
#
# CREDENTIALS. user_data carries ONE secret: the write-only Better Stack ingest token (the existing
# var.betterstack_logs_token; no new secret variable). The Redis LUKS key and every Doppler token stay
# out of this host. The server is deny-all inbound through the existing hcloud_firewall.inngest
# (Hetzner firewalls filter public INBOUND only, so egress to the ingest endpoint is unaffected).

locals {
  # The retired volume is 10 GB (var.inngest_redis_volume_size at creation). Hetzner volume sizes are
  # GiB-based, so the guest sees 10 * 2^30 bytes. Pinned as a historical fact here (not derived from
  # var.inngest_redis_volume_size, which sizes the LIVE volume and may change independently). The
  # on-host script refuses on any other size and names the observed size in its refusal row, so a wrong
  # constant fails safe and diagnosably, never as a write.
  inngest_backstop_wipe_expected_size_bytes = 10 * 1073741824

  inngest_backstop_wipe_user_data = templatefile("${path.module}/cloud-init-inngest-backstop-wipe.yml", {
    volume_id              = var.inngest_backstop_volume_id
    expected_size_bytes    = local.inngest_backstop_wipe_expected_size_bytes
    nonce                  = var.inngest_backstop_wipe_nonce
    betterstack_logs_token = var.betterstack_logs_token
  })
}

resource "hcloud_server" "inngest_backstop_wipe" {
  count = var.inngest_backstop_wipe_enabled ? 1 : 0

  name        = "soleur-inngest-backstop-wipe"
  server_type = var.inngest_backstop_wipe_server_type
  location    = var.location
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Egress only (the Better Stack evidence POST). Ingress is denied by the firewall below; no inbound
  # path to this host is needed or provided.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  firewall_ids = [hcloud_firewall.inngest.id]

  user_data = local.inngest_backstop_wipe_user_data

  labels = {
    role      = "inngest-backstop-wipe"
    ephemeral = "true"
  }

  lifecycle {
    # ssh_keys is a create-time attribute (mirrors hcloud_server.inngest / server.tf): without this a
    # rotated operator key would plan a replace of a host that exists for minutes.
    ignore_changes = [ssh_keys]

    precondition {
      condition     = can(regex("^[0-9]{1,20}$", var.inngest_backstop_wipe_nonce))
      error_message = "inngest_backstop_wipe_enabled is true but inngest_backstop_wipe_nonce is empty or non-numeric. The wipe dispatch must set TF_VAR_inngest_backstop_wipe_nonce to its GitHub run id: the destroy phase binds to the evidence row carrying that nonce."
    }
  }
}

resource "hcloud_volume_attachment" "inngest_backstop_wipe" {
  count = var.inngest_backstop_wipe_enabled ? 1 : 0

  volume_id = var.inngest_backstop_volume_id
  server_id = hcloud_server.inngest_backstop_wipe[0].id
  # The guest must never mount it: the script zeroes the raw device. automount would mount the ext4
  # filesystem read-write and the script's unmounted guard would (rightly) refuse.
  automount = false
}
