output "server_ip" {
  description = "Public IPv4 address of the bridge server"
  value       = hcloud_server.bridge.ipv4_address
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.bridge.ipv4_address}"
}

output "server_status" {
  description = "Current server status"
  value       = hcloud_server.bridge.status
}
