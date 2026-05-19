output "server_ip" {
  description = "Public IPv4 address of the web platform server"
  value       = hcloud_server.web.ipv4_address
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.web.ipv4_address}"
}

output "app_url" {
  description = "App URL via Cloudflare proxy"
  value       = "https://${var.app_domain}"
}

output "app_url_direct" {
  description = "Direct app URL (bypasses Cloudflare)"
  value       = "http://${hcloud_server.web.ipv4_address}:3000"
}

output "server_status" {
  description = "Current server status"
  value       = hcloud_server.web.status
}

output "inngest_heartbeat_url" {
  description = "Better Stack heartbeat URL — sourced from Doppler prd at runtime by the inngest-heartbeat.timer systemd unit. Sensitive because URL is the secret."
  value       = betteruptime_heartbeat.inngest_prd.url
  sensitive   = true
}
