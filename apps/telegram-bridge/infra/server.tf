resource "hcloud_ssh_key" "default" {
  name       = "soleur-bridge"
  public_key = file(var.ssh_key_path)
}

resource "hcloud_server" "bridge" {
  name        = "soleur-bridge"
  server_type = var.server_type
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  user_data = templatefile("${path.module}/cloud-init.yml", {
    image_name            = var.image_name
    ci_deploy_script_b64  = base64encode(file("${path.module}/../../web-platform/infra/ci-deploy.sh"))
    doppler_token         = var.doppler_token
    tunnel_token          = cloudflare_zero_trust_tunnel_cloudflared.bridge.tunnel_token
    webhook_deploy_secret = var.webhook_deploy_secret
  })

  # cloud-init and ssh_keys are create-time attributes. After import,
  # template interpolation differs from the original user_data, and
  # ssh_keys forces replacement. Both are safe to ignore.
  # TODO: remove ignore_changes after clean reprovisioning (import artifact)
  lifecycle {
    ignore_changes = [user_data, ssh_keys, image]
  }

  labels = {
    app = "soleur-bridge"
  }
}

resource "hcloud_volume" "data" {
  name     = "soleur-bridge-data"
  size     = 10
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-bridge"
  }
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.bridge.id
}
