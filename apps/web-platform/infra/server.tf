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
    image_name                  = var.image_name
    ci_deploy_script_b64        = base64encode(file("${path.module}/ci-deploy.sh"))
    cat_deploy_state_script_b64 = base64encode(file("${path.module}/cat-deploy-state.sh"))
    disk_monitor_script_b64     = base64encode(file("${path.module}/disk-monitor.sh"))
    hooks_json_b64 = base64encode(templatefile("${path.module}/hooks.json.tmpl", {
      webhook_deploy_secret = var.webhook_deploy_secret
    }))
    tunnel_token          = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
    webhook_deploy_secret = var.webhook_deploy_secret
    doppler_token         = var.doppler_token
    resend_api_key        = var.resend_api_key
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
    var.resend_api_key,
    file("${path.module}/disk-monitor.sh"),
  ]))

  connection {
    type  = "ssh"
    host  = hcloud_server.web.ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/disk-monitor.sh",
      "printf 'RESEND_API_KEY=%s\\n' '${var.resend_api_key}' > /etc/default/disk-monitor",
      "chmod 600 /etc/default/disk-monitor",
      "cat > /etc/systemd/system/disk-monitor.service << 'UNITEOF'\n[Unit]\nDescription=Disk space monitor\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/disk-monitor.sh\nUNITEOF",
      "cat > /etc/systemd/system/disk-monitor.timer << 'TIMEREOF'\n[Unit]\nDescription=Run disk monitor every 5 minutes\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now disk-monitor.timer",
      "systemctl list-timers disk-monitor.timer --no-pager",
    ]
  }
}

# Fix deploy pipeline: push current ci-deploy.sh, update webhook.service
# (EnvironmentFile + ReadWritePaths=/var/lock), and delete stale /mnt/data/.env.
# Cloud-init handles new servers; this provisioner fixes the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#1409).
# Source of truth for webhook.service: cloud-init.yml (search "path: /etc/systemd/system/webhook.service").
# The standalone webhook.service file keeps triggers_replace and the file provisioner in sync.
resource "terraform_data" "deploy_pipeline_fix" {
  # AppArmor profile must be loaded before ci-deploy.sh references it (#1570).
  depends_on = [terraform_data.apparmor_bwrap_profile]

  # hcloud_server.web has ignore_changes=[user_data], so cloud-init never re-applies
  # to the existing server. This resource is the sole path for pushing ci-deploy.sh,
  # webhook.service, cat-deploy-state.sh, and hooks.json updates to production (#2185).
  triggers_replace = sha256(join(",", [
    file("${path.module}/ci-deploy.sh"),
    file("${path.module}/webhook.service"),
    file("${path.module}/cat-deploy-state.sh"),
    templatefile("${path.module}/hooks.json.tmpl", {
      webhook_deploy_secret = var.webhook_deploy_secret
    }),
  ]))

  connection {
    type  = "ssh"
    host  = hcloud_server.web.ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "file" {
    source      = "${path.module}/ci-deploy.sh"
    destination = "/usr/local/bin/ci-deploy.sh"
  }

  provisioner "file" {
    source      = "${path.module}/webhook.service"
    destination = "/etc/systemd/system/webhook.service"
  }

  provisioner "file" {
    source      = "${path.module}/cat-deploy-state.sh"
    destination = "/usr/local/bin/cat-deploy-state.sh"
  }

  provisioner "file" {
    content = templatefile("${path.module}/hooks.json.tmpl", {
      webhook_deploy_secret = var.webhook_deploy_secret
    })
    destination = "/etc/webhook/hooks.json"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/ci-deploy.sh",
      "chmod +x /usr/local/bin/cat-deploy-state.sh",
      # hooks.json must be readable by the webhook (deploy group) but not world-readable --
      # it contains the HMAC secret. Provisioner "file" uploads as root:root by default.
      "chown root:deploy /etc/webhook/hooks.json",
      "chmod 640 /etc/webhook/hooks.json",
      # Append DOPPLER_CONFIG_DIR and DOPPLER_ENABLE_VERSION_CHECK to webhook-deploy env file.
      # Redirects Doppler CLI config to /tmp (writable under PrivateTmp) instead of ~/.doppler
      # (blocked by ProtectHome=read-only). grep guard makes this idempotent.
      "grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy || printf 'DOPPLER_CONFIG_DIR=/tmp/.doppler\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n' >> /etc/default/webhook-deploy",
      "systemctl daemon-reload",
      "systemctl restart webhook",
      # One-time cleanup: delete stale .env so deploys fail loudly if Doppler is unavailable.
      # rm -f is idempotent -- safe to re-run if this resource is tainted and re-created.
      "rm -f /mnt/data/.env",
    ]
  }
}

# Deploy custom seccomp profile for per-container use (#1557, #1569).
# Enables bubblewrap sandbox inside containers by allowing CLONE_NEWUSER.
# ci-deploy.sh applies the profile via --security-opt seccomp=<path>;
# this resource only provisions the profile file and kernel sysctl.
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "docker_seccomp_config" {
  triggers_replace = sha256(file("${path.module}/seccomp-bwrap.json"))

  connection {
    type  = "ssh"
    host  = hcloud_server.web.ipv4_address
    user  = "root"
    agent = true
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

  provisioner "remote-exec" {
    inline = [
      # Ubuntu 24.04 kernel restricts uid_map writes inside unprivileged user namespaces
      # even with apparmor=unconfined. Disable this kernel-level restriction for bwrap (#1557).
      "sysctl -w kernel.apparmor_restrict_unprivileged_userns=0",
      "echo 'kernel.apparmor_restrict_unprivileged_userns=0' > /etc/sysctl.d/99-bwrap-userns.conf",
      "echo 'Seccomp profile provisioned and userns sysctl applied'",
    ]
  }
}

# Deploy custom AppArmor profile for bwrap sandbox (#1570).
# Replaces apparmor=unconfined with a scoped profile that allows
# mount/umount/pivot_root while maintaining Docker's other restrictions.
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "apparmor_bwrap_profile" {
  triggers_replace = sha256(file("${path.module}/apparmor-soleur-bwrap.profile"))

  connection {
    type  = "ssh"
    host  = hcloud_server.web.ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "file" {
    source      = "${path.module}/apparmor-soleur-bwrap.profile"
    destination = "/etc/apparmor.d/soleur-bwrap"
  }

  provisioner "remote-exec" {
    inline = [
      "apparmor_parser -r /etc/apparmor.d/soleur-bwrap",
      "echo 'AppArmor profile soleur-bwrap loaded'",
    ]
  }
}

# Deploy orphan-reaper.sh and systemd timer to clean up stale .orphaned-*
# workspace directories under /mnt/data/workspaces/. workspace.ts moves
# root-owned dirs aside but nothing cleans them up (#1640).
# Shows as "will be created" in CI drift reports -- expected behavior (#1409).
resource "terraform_data" "orphan_reaper_install" {
  triggers_replace = sha256(file("${path.module}/orphan-reaper.sh"))

  connection {
    type  = "ssh"
    host  = hcloud_server.web.ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "file" {
    source      = "${path.module}/orphan-reaper.sh"
    destination = "/usr/local/bin/orphan-reaper.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/orphan-reaper.sh",
      "cat > /etc/systemd/system/orphan-reaper.service << 'UNITEOF'\n[Unit]\nDescription=Orphaned workspace directory reaper\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/orphan-reaper.sh\nUNITEOF",
      "cat > /etc/systemd/system/orphan-reaper.timer << 'TIMEREOF'\n[Unit]\nDescription=Run orphan reaper every 6 hours\n\n[Timer]\nOnBootSec=10min\nOnUnitActiveSec=6h\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now orphan-reaper.timer",
      "systemctl list-timers orphan-reaper.timer --no-pager",
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
