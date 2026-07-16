# #6545 — Operator dogfood host for headless Grok Build (Grok 4.5 via xAI API).
# Gated by var.enable_grok_dogfood (default false): per-PR apply must never birth
# this host (#6416 host_creates tripwire). Provision via operator-local -target
# after free server slot is confirmed.
#
# Phase 1: PUBLIC IP only (no private-net join). Private L2 is trusted for
# zot/git-data/web; a YOLO-capable agent host must not sit on that trust plane.

locals {
  grok_dogfood_enabled = var.enable_grok_dogfood
}

resource "hcloud_server" "grok_dogfood" {
  count = local.grok_dogfood_enabled ? 1 : 0

  name        = "soleur-grok-dogfood"
  server_type = var.grok_dogfood_server_type
  location    = var.grok_dogfood_location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  labels = {
    app  = "soleur-grok-dogfood"
    role = "operator-dogfood"
    epic = "6545"
  }

  # Small cloud-config; gzip to stay under Hetzner 32 KiB user_data cap.
  user_data = base64gzip(templatefile("${path.module}/cloud-init-grok-dogfood.yml", {}))
}

# SSH-only public ingress (admin IPs). No HTTP/HTTPS app ports — dogfood is not a product surface.
resource "hcloud_firewall" "grok_dogfood" {
  count = local.grok_dogfood_enabled ? 1 : 0

  name = "soleur-grok-dogfood"

  dynamic "rule" {
    for_each = var.admin_ips
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = [rule.value]
    }
  }

  labels = {
    app = "soleur-grok-dogfood"
  }
}

resource "hcloud_firewall_attachment" "grok_dogfood" {
  count = local.grok_dogfood_enabled ? 1 : 0

  firewall_id = hcloud_firewall.grok_dogfood[0].id
  server_ids  = [hcloud_server.grok_dogfood[0].id]
}
