resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  content = hcloud_server.web.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1 # Auto when proxied
}
