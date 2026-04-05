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
    image_name              = var.image_name
    ci_deploy_script_b64    = base64encode(file("${path.module}/ci-deploy.sh"))
    disk_monitor_script_b64 = base64encode(file("${path.module}/disk-monitor.sh"))
    tunnel_token            = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
    webhook_deploy_secret   = var.webhook_deploy_secret
    doppler_token           = var.doppler_token
    discord_ops_webhook_url = var.discord_ops_webhook_url
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

# Deploy disk-monitor.sh and systemd timer to the existing server.
# Cloud-init handles new servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#1409).
resource "terraform_data" "disk_monitor_install" {
  triggers_replace = sha256(join(",", [
    var.discord_ops_webhook_url,
    file("${path.module}/disk-monitor.sh"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/disk-monitor.sh",
      "printf 'DISCORD_OPS_WEBHOOK_URL=%s\\n' '${var.discord_ops_webhook_url}' > /etc/default/disk-monitor",
      "chmod 600 /etc/default/disk-monitor",
      "cat > /etc/systemd/system/disk-monitor.service << 'UNITEOF'\n[Unit]\nDescription=Disk space monitor\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/disk-monitor.sh\nUNITEOF",
      "cat > /etc/systemd/system/disk-monitor.timer << 'TIMEREOF'\n[Unit]\nDescription=Run disk monitor every 5 minutes\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now disk-monitor.timer",
      "systemctl list-timers disk-monitor.timer --no-pager",
    ]
  }
}

# Deploy custom seccomp profile and update Docker daemon config (#1557).
# Enables bubblewrap sandbox inside containers by allowing CLONE_NEWUSER.
# Also updates ci-deploy.sh on the existing server (cloud-init ignore_changes
# means the original ci-deploy.sh from provisioning time is never updated).
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "docker_seccomp_config" {
  triggers_replace = sha256(join(",", [
    file("${path.module}/seccomp-bwrap.json"),
    file("${path.module}/ci-deploy.sh"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/docker/seccomp-profiles",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/seccomp-bwrap.json"
    destination = "/etc/docker/seccomp-profiles/soleur-bwrap.json"
  }

  provisioner "file" {
    source      = "${path.module}/ci-deploy.sh"
    destination = "/usr/local/bin/ci-deploy.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/ci-deploy.sh",
      "python3 -c \"import json; f='/etc/docker/daemon.json'; d=json.load(open(f)); d['seccomp-profile']='/etc/docker/seccomp-profiles/soleur-bwrap.json'; json.dump(d,open(f,'w'),indent=2); print('daemon.json updated')\"",
      "systemctl restart docker",
      "echo 'Docker restarted with custom seccomp profile'",
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
