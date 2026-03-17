variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "admin_ips" {
  description = "IP addresses allowed to SSH into the server (CIDR notation)"
  type        = list(string)
}

variable "ssh_key_path" {
  description = "Path to the public SSH key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "server_type" {
  description = "Hetzner server type (cx33 = 4 vCPU, 8GB RAM)"
  type        = string
  default     = "cx33"
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "hel1"
}

variable "image_name" {
  description = "Docker image to deploy"
  type        = string
  default     = "ghcr.io/jikig-ai/soleur-web-platform:latest"
}

variable "volume_size" {
  description = "Size of the persistent volume in GB (for /workspaces)"
  type        = number
  default     = 20
}
