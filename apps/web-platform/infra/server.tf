resource "hcloud_ssh_key" "default" {
  name       = "soleur-web-platform"
  public_key = file(var.ssh_key_path)

  # public_key is a create-time attribute that never changes via Terraform.
  # CI drift checks use a dummy key, so ignore to prevent false positives.
  lifecycle {
    ignore_changes = [public_key]
  }
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
    doppler_token         = var.doppler_token
  })

  # cloud-init and ssh_keys are create-time attributes. After import,
  # template interpolation differs from the original user_data, and
  # ssh_keys forces replacement. Both are safe to ignore (#967).
  # TODO: remove ignore_changes after clean reprovisioning (import artifact)
  lifecycle {
    ignore_changes = [user_data, ssh_keys, image]
  }

  labels = {
    app = "soleur-web-platform"
  }
}

# One-time bootstrap: install Doppler CLI on the existing server and configure
# the service token for the webhook systemd unit. Cloud-init handles this for
# newly provisioned servers, but ignore_changes on user_data means the existing
# server never received the Doppler install.
#
# CI drift checks run plan-only, so the SSH connection is never evaluated in CI.
# This resource will show as "will be created" in drift reports — that is expected.
resource "terraform_data" "doppler_install" {
  triggers_replace = sha256(var.doppler_token)

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "curl -Ls --tlsv1.2 --proto '=https' --retry 3 https://cli.doppler.com/install.sh | sh",
      "printf 'DOPPLER_TOKEN=%s\\n' '${var.doppler_token}' > /etc/default/webhook-deploy",
      "chmod 600 /etc/default/webhook-deploy",
      "chown deploy:deploy /etc/default/webhook-deploy",
      "doppler --version",
      # Source token from the 600-permission file to avoid exposing it in /proc/<pid>/cmdline
      "set -a; . /etc/default/webhook-deploy; set +a; doppler secrets --only-names --project soleur --config prd | head -5",
      "systemctl restart webhook || true",
    ]
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
