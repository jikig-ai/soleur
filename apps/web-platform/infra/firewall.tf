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

  # CI deploy SSH rule removed -- deploys now use webhook via Cloudflare Tunnel (#749).

  # HTTP (app traffic via Cloudflare proxy -- restricted to CF edge IPs only, #1836)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      # Cloudflare IPv4 — https://www.cloudflare.com/ips-v4/
      "173.245.48.0/20",
      "103.21.244.0/22",
      "103.22.200.0/22",
      "103.31.4.0/22",
      "141.101.64.0/18",
      "108.162.192.0/18",
      "190.93.240.0/20",
      "188.114.96.0/20",
      "197.234.240.0/22",
      "198.41.128.0/17",
      "162.158.0.0/15",
      "104.16.0.0/13",
      "104.24.0.0/14",
      "172.64.0.0/13",
      "131.0.72.0/22",
      # Cloudflare IPv6 — https://www.cloudflare.com/ips-v6/
      "2400:cb00::/32",
      "2606:4700::/32",
      "2803:f800::/32",
      "2405:b500::/32",
      "2405:8100::/32",
      "2a06:98c0::/29",
      "2c0f:f248::/32",
    ]
  }

  # HTTPS (restricted to CF edge IPs only, #1836)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      # Cloudflare IPv4 — https://www.cloudflare.com/ips-v4/
      "173.245.48.0/20",
      "103.21.244.0/22",
      "103.22.200.0/22",
      "103.31.4.0/22",
      "141.101.64.0/18",
      "108.162.192.0/18",
      "190.93.240.0/20",
      "188.114.96.0/20",
      "197.234.240.0/22",
      "198.41.128.0/17",
      "162.158.0.0/15",
      "104.16.0.0/13",
      "104.24.0.0/14",
      "172.64.0.0/13",
      "131.0.72.0/22",
      # Cloudflare IPv6 — https://www.cloudflare.com/ips-v6/
      "2400:cb00::/32",
      "2606:4700::/32",
      "2803:f800::/32",
      "2405:b500::/32",
      "2405:8100::/32",
      "2a06:98c0::/29",
      "2c0f:f248::/32",
    ]
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
