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
    deploy_ssh_public_key = var.deploy_ssh_public_key
    # Single source of truth: apps/web-platform/infra/ci-deploy.sh (tested by ci-deploy.test.sh)
    ci_deploy_script_b64  = base64encode(file("${path.module}/../../web-platform/infra/ci-deploy.sh"))
  })

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
