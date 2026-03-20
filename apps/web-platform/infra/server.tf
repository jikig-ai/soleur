resource "hcloud_ssh_key" "default" {
  name       = "soleur-web-platform"
  public_key = file(var.ssh_key_path)
}

resource "hcloud_server" "web" {
  name        = "soleur-web-platform"
  server_type = var.server_type
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  user_data = templatefile("${path.module}/cloud-init.yml", {
    image_name            = var.image_name
    ci_deploy_script_b64  = base64encode(file("${path.module}/ci-deploy.sh"))
    tunnel_token          = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
    webhook_deploy_secret = var.webhook_deploy_secret
  })

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume" "workspaces" {
  name     = "soleur-web-platform-data"
  size     = var.volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "workspaces" {
  volume_id = hcloud_volume.workspaces.id
  server_id = hcloud_server.web.id
}
