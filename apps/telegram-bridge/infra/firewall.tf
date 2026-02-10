resource "hcloud_firewall" "bridge" {
  name = "soleur-bridge"

  # SSH -- restricted to admin IPs only
  dynamic "rule" {
    for_each = var.admin_ips
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = [rule.value]
    }
  }

  # ICMP (ping) from anywhere
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # No HTTP/HTTPS rules needed -- Telegram uses outbound long polling
}

resource "hcloud_firewall_attachment" "bridge" {
  firewall_id = hcloud_firewall.bridge.id
  server_ids  = [hcloud_server.bridge.id]
}
