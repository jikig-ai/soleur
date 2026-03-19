resource "hcloud_firewall" "web" {
  name = "soleur-web-platform"

  # SSH -- admin IPs
  dynamic "rule" {
    for_each = var.admin_ips
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = [rule.value]
    }
  }

  # SSH -- CI deploy (GitHub Actions runners use dynamic IPs)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP (redirect to HTTPS or direct app access)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # App port (3000) for direct access during development
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "3000"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ICMP (ping) from anywhere
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall_attachment" "web" {
  firewall_id = hcloud_firewall.web.id
  server_ids  = [hcloud_server.web.id]
}
