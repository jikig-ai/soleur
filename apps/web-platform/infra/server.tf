locals {
  # Rendered hooks.json content, shared between cloud-init user_data (fresh servers)
  # and the deploy_pipeline_fix provisioner (existing server). Single source of truth
  # avoids drift between the two code paths (#2201).
  hooks_json = templatefile("${path.module}/hooks.json.tmpl", {
    webhook_deploy_secret = var.webhook_deploy_secret
  })
}

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
    image_name                            = var.image_name
    ci_deploy_script_b64                  = base64encode(file("${path.module}/ci-deploy.sh"))
    ci_deploy_wrapper_script_b64          = base64encode(file("${path.module}/ci-deploy-wrapper.sh"))
    cat_deploy_state_script_b64           = base64encode(file("${path.module}/cat-deploy-state.sh"))
    canary_bundle_claim_check_script_b64  = base64encode(file("${path.module}/canary-bundle-claim-check.sh"))
    disk_monitor_script_b64               = base64encode(file("${path.module}/disk-monitor.sh"))
    resource_monitor_script_b64           = base64encode(file("${path.module}/resource-monitor.sh"))
    container_restart_monitor_script_b64  = base64encode(file("${path.module}/container-restart-monitor.sh"))
    container_restart_monitor_service_b64 = base64encode(file("${path.module}/container-restart-monitor.service"))
    container_restart_monitor_timer_b64   = base64encode(file("${path.module}/container-restart-monitor.timer"))
    fail2ban_sshd_local_b64               = base64encode(file("${path.module}/fail2ban-sshd.local"))
    journald_soleur_conf_b64              = base64encode(file("${path.module}/journald-soleur.conf"))
    hooks_json_b64                        = base64encode(local.hooks_json)
    infra_config_apply_script_b64         = base64encode(file("${path.module}/infra-config-apply.sh"))
    infra_config_install_script_b64       = base64encode(file("${path.module}/infra-config-install.sh"))
    cat_infra_config_state_script_b64     = base64encode(file("${path.module}/cat-infra-config-state.sh"))
    cron_egress_nftables_script_b64       = base64encode(file("${path.module}/cron-egress-nftables.sh"))
    cron_egress_resolve_script_b64        = base64encode(file("${path.module}/cron-egress-resolve.sh"))
    cron_egress_alarm_script_b64          = base64encode(file("${path.module}/cron-egress-alarm.sh"))
    cron_egress_allowlist_b64             = base64encode(file("${path.module}/cron-egress-allowlist.txt"))
    cron_egress_allowlist_cidr_b64        = base64encode(file("${path.module}/cron-egress-allowlist-cidr.txt"))
    cron_egress_firewall_service_b64      = base64encode(file("${path.module}/cron-egress-firewall.service"))
    cron_egress_resolve_service_b64       = base64encode(file("${path.module}/cron-egress-resolve.service"))
    cron_egress_resolve_timer_b64         = base64encode(file("${path.module}/cron-egress-resolve.timer"))
    cron_egress_alarm_unit_b64            = base64encode(file("${path.module}/cron-egress-alarm@.service"))
    cron_egress_postapply_assert_b64      = base64encode(file("${path.module}/cron-egress-postapply-assert.sh"))
    tunnel_token                          = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
    webhook_deploy_secret                 = var.webhook_deploy_secret
    doppler_token                         = var.doppler_token
    resend_api_key                        = var.resend_api_key
    # Fresh-host parity for the CI SSH keypair generated in
    # ci-ssh-key.tf. local.ci_ssh_pubkey is trimspaced — see locals{}
    # block in ci-ssh-key.tf for the rationale.
    ci_ssh_public_key_openssh = local.ci_ssh_pubkey
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
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
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

# Deploy resource-monitor.sh and systemd timer to the existing server.
# Cloud-init handles new servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#1052).
# Mirror of disk_monitor_install: same connection, trigger hash shape, and
# file/remote-exec invocation order. Keep both in sync.
resource "terraform_data" "resource_monitor_install" {
  triggers_replace = sha256(join(",", [
    var.resend_api_key,
    file("${path.module}/resource-monitor.sh"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/resource-monitor.sh"
    destination = "/usr/local/bin/resource-monitor.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/resource-monitor.sh",
      "printf 'RESEND_API_KEY=%s\\n' '${var.resend_api_key}' > /etc/default/resource-monitor",
      "chmod 600 /etc/default/resource-monitor",
      "cat > /etc/systemd/system/resource-monitor.service << 'UNITEOF'\n[Unit]\nDescription=Host CPU/RAM/session monitor\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/resource-monitor.sh\nUNITEOF",
      "cat > /etc/systemd/system/resource-monitor.timer << 'TIMEREOF'\n[Unit]\nDescription=Run resource monitor every 5 minutes\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now resource-monitor.timer",
      "systemctl list-timers resource-monitor.timer --no-pager",
    ]
  }
}

# Deploy container-restart-monitor.sh + units to the existing server (#5417).
# Cloud-init handles new servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#5417).
# Mirror of resource_monitor_install: same connection + trigger-hash shape. The
# .service/.timer are SHIPPED AS FILES (not heredoc'd) because the doppler-
# wrapped ExecStart's nested single-quotes do not survive a terraform inline
# heredoc; file() keeps triggers_replace and the delivered content in lockstep.
resource "terraform_data" "container_restart_monitor_install" {
  triggers_replace = sha256(join(",", [
    var.resend_api_key,
    file("${path.module}/container-restart-monitor.sh"),
    file("${path.module}/container-restart-monitor.service"),
    file("${path.module}/container-restart-monitor.timer"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/container-restart-monitor.sh"
    destination = "/usr/local/bin/container-restart-monitor.sh"
  }

  provisioner "file" {
    source      = "${path.module}/container-restart-monitor.service"
    destination = "/etc/systemd/system/container-restart-monitor.service"
  }

  provisioner "file" {
    source      = "${path.module}/container-restart-monitor.timer"
    destination = "/etc/systemd/system/container-restart-monitor.timer"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/container-restart-monitor.sh",
      "printf 'RESEND_API_KEY=%s\\n' '${var.resend_api_key}' > /etc/default/container-restart-monitor",
      "chmod 600 /etc/default/container-restart-monitor",
      "systemctl daemon-reload",
      "systemctl enable --now container-restart-monitor.timer",
      "systemctl list-timers container-restart-monitor.timer --no-pager",
    ]
  }
}

# Deploy fail2ban sshd tuning drop-in to the existing server (issue #2654).
# Caps bantime.increment recidivism at 1h so an operator typo against
# AllowUsers does not snowball into a multi-hour (or multi-day) SSH lockout.
# Cloud-init handles fresh servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Source of truth for jail content: fail2ban-sshd.local (sibling file).
# Shows as "will be created" in CI drift reports -- expected behavior.
# Runbook for acute lockout recovery: knowledge-base/engineering/operations/runbooks/ssh-fail2ban-unban.md
resource "terraform_data" "fail2ban_tuning" {
  triggers_replace = sha256(file("${path.module}/fail2ban-sshd.local"))

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # Ensure fail2ban is installed before dropping the jail.d override. The
  # existing server is an import-era artifact -- cloud-init's `packages:`
  # step never re-ran after import (ignore_changes = [user_data]), and the
  # initial run appears to have failed silently (#2680). `dpkg -s` makes this
  # idempotent: on servers where fail2ban is already installed (fresh
  # cloud-init provisioning) the install branch is skipped.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "dpkg -s fail2ban >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq fail2ban; }",
      # Positive post-install re-verification mirrors the cloud-init audit
      # (see runcmd in cloud-init.yml). Catches the rare case where apt
      # reports success but dpkg leaves the package in a half-configured
      # state; also gives a clear error message if a future edit breaks the
      # install branch above (e.g., a typo'd package name).
      "dpkg -s fail2ban >/dev/null 2>&1 || { echo 'FATAL: fail2ban still not installed after install attempt' >&2; exit 1; }",
    ]
  }

  # The `remote-exec` above ensures the package is installed first. On the
  # existing server (which was imported with ignore_changes = [user_data])
  # cloud-init's packages: step never re-ran, so fail2ban may be missing (#2680).
  provisioner "file" {
    source      = "${path.module}/fail2ban-sshd.local"
    destination = "/etc/fail2ban/jail.d/soleur-sshd.local"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chown root:root /etc/fail2ban/jail.d/soleur-sshd.local",
      "chmod 0644 /etc/fail2ban/jail.d/soleur-sshd.local",
      # Reload picks up jail.d drop-ins without dropping active bans; fall back
      # to restart if the installed fail2ban version does not support reload of
      # bantime.* keys (some 0.10.x builds required restart; 1.0.2 on 24.04 is fine).
      "systemctl reload fail2ban || systemctl restart fail2ban",
      # Diagnostic dump (informational; printed to CI drift logs).
      "fail2ban-client -d | grep -A5 '\\[sshd\\]' | head -20 || true",
      # Positive assertions: if the drop-in did NOT take effect, these values
      # would still report the defaults-debian.conf values. Asserting the
      # literal expected values fails the provisioner when the override is
      # silently ignored (jail.d load-order regression, syntax error swallowed
      # by reload, etc.). 600s = 10m; 3600s = 1h.
      "test \"$(fail2ban-client get sshd bantime)\" = '600'",
      "test \"$(fail2ban-client get sshd maxretry)\" = '5'",
      "test \"$(fail2ban-client get sshd findtime)\" = '600'",
    ]
  }
}

# Make systemd-journald persistent + bounded on the existing server (#4792, #4773).
# PR #4786 moved the soleur-web-platform container to `--log-driver journald`, so
# the host journal must persist across reboots (else Vector's 3 journald sources
# read an empty /var/log/journal post-reboot) and be sized so it can never fill /.
# Cloud-init handles fresh servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes never apply to it — so a
# cloud-init-only edit would land dead config; this SSH path is the sole live-prod
# apply path). Source of truth for the drop-in: journald-soleur.conf (sibling
# file, also rendered into cloud-init via base64encode(file()) — keep both in
# sync). Shows as "will be created" in CI drift reports -- expected behavior, same
# as the 6 sibling SSH provisioners. SSH connection precedent: disk_monitor_install.
# Positive-assertion precedent: fail2ban_tuning (prove persistence took, don't
# just observe it). Apply-path firewall note: SSH:22 is allowlisted to
# var.admin_ips only (firewall.tf; CI-deploy SSH rule removed in #749), so the
# handshake succeeds iff the operator/CI egress IP ∈ admin_ips. A
# `connection reset by peer` here is admin-IP drift (fix: /soleur:admin-ip-refresh,
# runbook admin-ip-drift.md), NOT an sshd/journald fault — per hr-ssh-diagnosis-verify-firewall.
resource "terraform_data" "journald_persistent" {
  triggers_replace = sha256(file("${path.module}/journald-soleur.conf"))

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # The drop-in dir does NOT exist by default on Ubuntu — systemd ships
  # /etc/systemd/journald.conf but not the journald.conf.d/ subdir, and the
  # `file` provisioner (scp) does not create remote parents. On the existing
  # host cloud-init's write_files (which would create the dir) never runs
  # (ignore_changes=[user_data]), so this mkdir is load-bearing: without it the
  # very first apply fails at scp `No such file or directory`. Mirrors the
  # fail2ban_tuning pre-`file` remote-exec that guarantees its target dir exists.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/systemd/journald.conf.d",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/journald-soleur.conf"
    destination = "/etc/systemd/journald.conf.d/00-soleur.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chown root:root /etc/systemd/journald.conf.d/00-soleur.conf",
      "chmod 0644 /etc/systemd/journald.conf.d/00-soleur.conf",
      # Create the persistent journal dir with journald's expected ownership +
      # ACLs. systemd-tmpfiles applies the packaged tmpfiles.d/systemd.conf rule
      # for /var/log/journal (0755 root:systemd-journal + setgid + read ACLs);
      # mkdir -p first so the rule has a dir to adjust. Both idempotent.
      "mkdir -p /var/log/journal",
      "systemd-tmpfiles --create --prefix /var/log/journal",
      # Restart picks up the Storage=persistent + cap drop-in; flush migrates the
      # volatile /run journal into /var/log/journal. Sub-second daemon restart;
      # buffered logs are flushed, not lost. No container/app/Vector restart:
      # Vector's journald sources read by sd_journal cursor (not file path) and
      # are restart/rotation-tolerant, so they resume from their stored cursor
      # with no gap beyond the sub-second window. Resumption is verified
      # out-of-band (no SSH) post-apply via the cat-deploy-state webhook —
      # vector_journal_tail non-empty + journald_storage.persistent=true.
      "systemctl restart systemd-journald",
      "journalctl --flush",
      # Diagnostic dump (informational; printed to CI drift logs).
      "systemd-analyze cat-config systemd/journald.conf | grep -E '^(Storage|SystemMaxUse|SystemKeepFree|RuntimeMaxUse)=' || true",
      # Positive assertions (fail2ban_tuning pattern): if the drop-in did NOT take
      # effect, journald would still be volatile and these would fail the
      # provisioner instead of silently shipping dead config.
      "test -d /var/log/journal",
      # --header lists active journal files with their paths; a persistent journal
      # has files under /var/log/journal. Volatile-only journals list /run paths.
      "journalctl --header | grep -q '/var/log/journal'",
      "test \"$(systemctl is-active systemd-journald)\" = 'active'",
    ]
  }
}

# Handler-bootstrap bridge: deliver infra-config-apply.sh (the /hooks/infra-config
# webhook handler) + cat-infra-config-state.sh + the rendered hooks.json directly
# to the running host over SSH (#4811, Ref #4804).
#
# WHY THIS EXISTS (the chicken-and-egg this closes): the handler reaches the host
# only via (1) cloud-init write_files — dead on the existing host because
# hcloud_server.web carries ignore_changes=[user_data], so cloud-init never
# re-applies — and (2) deploy_pipeline_fix's triggers_replace hash, which re-fires
# push-infra-config.sh. But push-infra-config.sh pushes the OTHER 7 files and does
# NOT send infra-config-apply.sh (the handler is not in its payload nor in the
# handler's own FILE_MAP — it cannot deliver itself by construction). Net: a
# handler/hooks.json drift on the host was UNRECOVERABLE through the webhook path,
# because the recovery itself routes through the stale handler (the #4804 freeze).
# SSH is the only path that can deliver the handler TO a host where the handler is
# broken. PR #4805 made the handler fail loud, but a fix can only take effect on a
# host that receives the new handler — this resource is that delivery path.
#
# WHY SSH IS NOT A #3756 REGRESSION: #3756 replaced ONLY deploy_pipeline_fix's SSH
# provisioner with the webhook, to keep the *routine* deploy-config push HTTPS-only.
# SSH was never removed from the stack — 8 sibling terraform_data resources here
# still use connection{type="ssh"} today (disk_monitor_install, resource_monitor_install,
# fail2ban_tuning, journald_persistent, docker_seccomp_config, apparmor_bwrap_profile,
# orphan_reaper_install). This is a HYBRID of the established siblings: the
# connection block + positive post-write assertions + service restart are
# journald_persistent's shape, while the multi-input `sha256(join(...))`
# triggers_replace and the base64 secret-render are deploy_pipeline_fix's /
# disk_monitor_install's (a secret-bearing local.hooks_json cannot be a single
# `file()`). Do NOT "simplify" the multi-input trigger to journald's single-file()
# form — it legitimately tracks 3 inputs. NOT a reversal of #3756's routine-push
# decision.
#
# RUNNING-HOST-ONLY: unlike deploy_pipeline_fix this resource has NO cloud-init
# mirror — fresh hosts get the handler from cloud-init write_files
# (cloud-init.yml, search "path: /usr/local/bin/infra-config-apply.sh") directly.
# Do NOT add a redundant cloud-init block.
#
# DUAL-FIRE IS INTENTIONAL: infra-config-apply.sh, cat-infra-config-state.sh, and
# local.hooks_json appear in BOTH this triggers_replace AND deploy_pipeline_fix's.
# A handler edit re-fires both — deploy_pipeline_fix re-pushes the other 7 files,
# while THIS resource is the only one that actually delivers the handler. Do not
# "dedupe" them.
#
# SYNCHRONOUS RESTART: the webhook restart below is direct (systemctl restart),
# unlike the handler's own deferred self-restart (systemd-run --on-active=3s). The
# handler must defer because it IS exec'd by the webhook binary (killing webhook
# kills the in-flight response). This SSH path is independent of the webhook
# process (SSH = root over :22; webhook = deploy user on 127.0.0.1:9000), so it
# can restart + assert active immediately. Do NOT copy the deferred-restart dance.
#
# Shows as "will be created" in CI drift reports -- expected behavior, same as the
# 8 sibling SSH provisioners. Apply-path firewall note: SSH:22 is allowlisted to
# var.admin_ips only (firewall.tf) for DIRECT-IP dials. The OPERATOR-LOCAL apply
# dials the direct IP, so its handshake succeeds iff the operator egress IP ∈
# admin_ips. A `connection reset by peer` on the operator path is admin-IP drift
# (fix: /soleur:admin-ip-refresh, runbook admin-ip-drift.md), NOT an sshd/handler
# fault — per hr-ssh-diagnosis-verify-firewall.
#
# #4829 — CI ACCESS IS VIA THE CLOUDFLARE TUNNEL, NOT admin_ips. The GitHub-hosted
# runner egress IP is non-static and NOT in admin_ips, so `apply-deploy-pipeline-fix.yml`
# reaches this bridge over the existing CF Tunnel SSH route (tunnel.tf: ssh://localhost:22
# ingress + CF Access ci_ssh service token) instead of the firewall-gated direct IP.
# The runner opens a `cloudflared access tcp` localhost forward and an
# `iptables -t nat OUTPUT REDIRECT` rule rewrites SERVER_IP:22 → 127.0.0.1:2222,
# so the inbound SSH arrives at sshd via the host-side cloudflared daemon and never
# traverses the :22 admin_ips ingress rule (firewall byte-unchanged). This bridge IS
# now in apply-deploy-pipeline-fix.yml's -target= set; a CI handshake failure here is
# either a missing/stale CI key in root's authorized_keys (terraform_data.root_authorized_keys,
# operator-local-apply only) or an expired ci_ssh CF Access token — NOT admin-IP drift.
#
# #4827 ADDITION: this bridge also delivers infra-config-install.sh (the pinned
# root-run escalation helper) + the updated deploy-inngest-bootstrap.sudoers (with
# the INFRA_CONFIG_INSTALL grant) over root SSH. This is load-bearing for the
# chicken-and-egg: the webhook handler's prod-mode escalation needs BOTH the helper
# binary AND the sudoers alias present on-host before `sudo infra-config-install`
# is permitted — but the handler cannot deliver either (the helper is deliberately
# OUT of the webhook FILE_MAP, and writing the sudoers itself requires the alias).
# Root SSH is the only non-circular bootstrap path. #4829 — deploy_pipeline_fix does
# NOT depends_on this resource; both are listed as explicit -target=s in
# apply-deploy-pipeline-fix.yml and apply on the same CI run. Ordering between the SSH
# helper/sudoers delivery and the webhook push is handled by the handler's per-file
# install_rejected self-heal (see the deploy_pipeline_fix depends_on rationale below).
resource "terraform_data" "infra_config_handler_bootstrap" {
  triggers_replace = sha256(join(",", [
    file("${path.module}/infra-config-apply.sh"),
    file("${path.module}/infra-config-install.sh"),
    file("${path.module}/deploy-inngest-bootstrap.sudoers"),
    file("${path.module}/cat-infra-config-state.sh"),
    local.hooks_json,
  ]))

  # #4829 — DUAL-CONTEXT connection. Two apply paths reach this bridge:
  #   (1) operator-local full `terraform apply` — var.ci_ssh_private_key is unset
  #       (null), so agent = true uses the operator's ssh-agent (their key is
  #       already in root's authorized_keys). Byte-equivalent to the pre-#4829
  #       behavior.
  #   (2) CI `apply-deploy-pipeline-fix.yml` over the Cloudflare Tunnel —
  #       TF_VAR_ci_ssh_private_key carries Doppler DEPLOY_SSH_PRIVATE_KEY, so
  #       agent = false and the Go SSH client authenticates with that explicit
  #       key. The runner has no ssh-agent; the host trusts the matching pubkey
  #       via terraform_data.root_authorized_keys (ci-ssh-key.tf).
  # connection.host stays the literal ipv4_address in BOTH paths — the CI runner
  # transparently redirects SERVER_IP:22 → 127.0.0.1:2222 (the cloudflared TCP
  # forward) via an `iptables -t nat OUTPUT REDIRECT` rule, invisible to the Go
  # SSH client (which does NOT read ~/.ssh/config / ProxyCommand — see learning
  # 2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md).
  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # The two scripts are on-disk files → straight scp. hooks.json is NOT: it is a
  # templatefile() render with var.webhook_deploy_secret interpolated (the on-disk
  # file is the .tmpl, not the rendered output — same trap push-infra-config.sh
  # documents), so it cannot be a provisioner "file" source. It is written via the
  # remote-exec base64 heredoc below, exactly as push-infra-config.sh passes
  # HOOKS_JSON_B64.
  provisioner "file" {
    source      = "${path.module}/infra-config-apply.sh"
    destination = "/usr/local/bin/infra-config-apply.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cat-infra-config-state.sh"
    destination = "/usr/local/bin/cat-infra-config-state.sh"
  }

  # #4827 — the escalation helper. Delivered here (root SSH) because the webhook
  # handler that depends on it cannot deliver it (it is OUT of the FILE_MAP).
  provisioner "file" {
    source      = "${path.module}/infra-config-install.sh"
    destination = "/usr/local/bin/infra-config-install"
  }

  # #4827 — the sudoers grant (with the new INFRA_CONFIG_INSTALL alias). Staged to
  # a temp path then visudo-validated + installed below; writing it directly would
  # risk a half-written file in /etc/sudoers.d. The handler ALSO carries this file
  # in its FILE_MAP, but the webhook self-heal of the sudoers is circular on the
  # first apply (escalating its write needs the alias this file adds), so root SSH
  # bootstraps it.
  provisioner "file" {
    source      = "${path.module}/deploy-inngest-bootstrap.sudoers"
    destination = "/tmp/deploy-inngest-bootstrap.sudoers.staged"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      # Render hooks.json from the secret-bearing local value (base64 so the
      # interpolated content survives the inline string; sensitive interpolation
      # in remote-exec is the same mechanism disk_monitor_install uses for
      # var.resend_api_key — Terraform only refuses it in local-exec's command).
      "printf '%s' '${base64encode(local.hooks_json)}' | base64 -d > /etc/webhook/hooks.json",
      # Ownership/permissions: scripts root:root 0755, hooks.json root:deploy 0640
      # (match cloud-init.yml write_files for these paths).
      "chown root:root /usr/local/bin/infra-config-apply.sh /usr/local/bin/cat-infra-config-state.sh /usr/local/bin/infra-config-install",
      "chmod 0755 /usr/local/bin/infra-config-apply.sh /usr/local/bin/cat-infra-config-state.sh /usr/local/bin/infra-config-install",
      "chown root:deploy /etc/webhook/hooks.json",
      "chmod 0640 /etc/webhook/hooks.json",
      # #4827 — validate then atomically install the sudoers grant. visudo -cf
      # gates a malformed file from disabling sudo entirely; install does an
      # owner/mode-correct atomic placement. Fail the provisioner on a bad file
      # rather than ship a broken /etc/sudoers.d.
      "visudo -cf /tmp/deploy-inngest-bootstrap.sudoers.staged",
      "install -o root -g root -m 0440 /tmp/deploy-inngest-bootstrap.sudoers.staged /etc/sudoers.d/deploy-inngest-bootstrap",
      "rm -f /tmp/deploy-inngest-bootstrap.sudoers.staged",
      # Synchronous restart (safe — this SSH path is not the webhook process).
      "systemctl restart webhook",
      # Positive post-write assertions (journald_persistent / fail2ban_tuning
      # pattern): prove the bootstrap took, don't just observe it. A failed
      # assertion fails the provisioner instead of silently shipping dead config.
      "test -x /usr/local/bin/infra-config-apply.sh",
      "test -x /usr/local/bin/cat-infra-config-state.sh",
      "test -x /usr/local/bin/infra-config-install",
      # The sudoers grant landed and parses (the INFRA_CONFIG_INSTALL alias is
      # what makes the webhook handler's prod-mode escalation work).
      "grep -q INFRA_CONFIG_INSTALL /etc/sudoers.d/deploy-inngest-bootstrap",
      # hooks.json re-registers the status hook + maps the state-reporter key (the
      # exact host drift that caused the #4804 freeze: stale hooks.json had neither).
      "grep -q infra-config-status /etc/webhook/hooks.json",
      "grep -q cat_infra_config_state_sh_b64 /etc/webhook/hooks.json",
      # The webhook listener restarted cleanly and is serving.
      "test \"$(systemctl is-active webhook)\" = 'active'",
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
#
# NOTE (#2205): ci-deploy.sh, cat-deploy-state.sh, canary-bundle-claim-check.sh,
# and hooks.json are ALSO provisioned via cloud-init write_files for fresh
# servers. See cloud-init.yml (search "path: /usr/local/bin/ci-deploy.sh",
# "/usr/local/bin/cat-deploy-state.sh", "/usr/local/bin/canary-bundle-claim-check.sh").
# Both paths must stay in sync — a change here without updating cloud-init.yml
# means new servers provisioned from scratch will miss the change.
resource "terraform_data" "deploy_pipeline_fix" {
  # AppArmor profile must be loaded before ci-deploy.sh references it (#1570).
  #
  # #4827/#4829 — deliberately NO depends_on the infra_config_handler_bootstrap
  # bridge, even though both are now applied by `apply-deploy-pipeline-fix.yml`.
  # The workflow lists BOTH resources EXPLICITLY in its `-target=` set (#4829), so
  # a depends_on is unnecessary for ordering AND would over-couple the resource
  # graph: a depends_on would force EVERY apply of deploy_pipeline_fix (including
  # the operator-local full apply) to also recreate the bridge. Keeping them as
  # independent explicit targets lets the workflow apply each on its own merits.
  # Ordering between the SSH delivery of helper+sudoers (the bridge) and the
  # webhook push (this resource) is handled by the handler's per-file self-heal: a
  # push that predates the helper/sudoers records install_rejected for that file
  # and the next push lands it. Both targets apply on the same CI run, so the
  # window is a single apply.
  depends_on = [terraform_data.apparmor_bwrap_profile]

  # hcloud_server.web has ignore_changes=[user_data], so cloud-init never re-applies
  # to the existing server. This resource is the sole path for pushing ci-deploy.sh,
  # webhook.service, cat-deploy-state.sh, canary-bundle-claim-check.sh, and
  # hooks.json updates to production (#2185, #3033).
  # Sentinel string at the end forces re-recreation when the inline
  # remote-exec list itself changes (terraform_data doesn't auto-detect
  # provisioner-block content drift; only triggers_replace is consulted).
  # Bump the sentinel suffix in lockstep with any inline edit so the
  # remote host re-receives + re-runs the updated commands.
  triggers_replace = sha256(join(",", [
    file("${path.module}/ci-deploy.sh"),
    file("${path.module}/ci-deploy-wrapper.sh"),
    file("${path.module}/webhook.service"),
    file("${path.module}/cat-deploy-state.sh"),
    file("${path.module}/canary-bundle-claim-check.sh"),
    # NOTE (#4827): the sudoers is no longer webhook-delivered (removed from
    # push-infra-config.sh + FILE_MAP; it is root-managed via the
    # infra_config_handler_bootstrap SSH bridge). It is kept in THIS hash so a
    # sudoers change still re-fires deploy_pipeline_fix (harmless — re-pushes the
    # unchanged 7 webhook files) AND keeps the deploy-pipeline-fix drift guard
    # (plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts TRIGGER_FILES +
    # the ship-skill DEPLOY_PIPELINE_FIX_TRIGGERS) in sync without a 3-way edit.
    file("${path.module}/deploy-inngest-bootstrap.sudoers"),
    file("${path.module}/infra-config-apply.sh"),
    # NOTE (#4829): infra-config-install.sh is delivered by the
    # infra_config_handler_bootstrap SSH bridge (root-managed escalation helper),
    # NOT this webhook path. It is kept in THIS hash for the same reason as the
    # sudoers above: so a helper-only change re-fires deploy_pipeline_fix (harmless
    # — re-pushes the unchanged 7 webhook files) AND keeps the deploy-pipeline-fix
    # drift guard (plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts
    # TRIGGER_FILES + the ship-skill DEPLOY_PIPELINE_FIX_TRIGGERS array) in sync,
    # so the ship gate fires + notifies the operator on a helper-only change.
    file("${path.module}/infra-config-install.sh"),
    file("${path.module}/push-infra-config.sh"),
    file("${path.module}/cat-infra-config-state.sh"),
    local.hooks_json,
  ]))

  # #3756 — replaced SSH provisioners (connection + file + remote-exec) with
  # an HTTPS POST through the existing CF Tunnel. push-infra-config.sh sends
  # base64-encoded file payloads to /hooks/infra-config; the webhook handler
  # (infra-config-apply.sh) writes them atomically on the host.
  #
  # Sensitive values are passed via the environment {} block (Terraform >=1.0
  # accepts sensitive values here but refuses to interpolate them into the
  # command string).
  provisioner "local-exec" {
    command = "${path.module}/push-infra-config.sh"

    environment = {
      WEBHOOK_SECRET   = var.webhook_deploy_secret
      CF_ACCESS_ID     = var.cf_access_client_id
      CF_ACCESS_SECRET = var.cf_access_client_secret
      APP_DOMAIN_BASE  = var.app_domain_base
      INFRA_DIR        = path.module
      HOOKS_JSON_B64   = base64encode(local.hooks_json)
    }
  }
}

# Deploy custom seccomp profile for per-container use (#1557, #1569).
# Enables bubblewrap sandbox inside containers by allowing CLONE_NEWUSER.
# ci-deploy.sh applies the profile via --security-opt seccomp=<path>;
# this resource only provisions the profile file and kernel sysctl.
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "docker_seccomp_config" {
  # Keyed on BOTH the seccomp-profile hash AND the host id. The hash alone is
  # identical on a replaced VM, so a bare `sha256(file(...))` trigger is the
  # classic terraform_data fresh-host trap (hr-fresh-host-provisioning-
  # reachable-from-terraform-apply): a new host keeps the old hash, the
  # provisioner is skipped, and the userns sysctl is never asserted on it —
  # the root cause of the 2026-06-04 cron silent-producer incident
  # (#4927/#4928), where bwrap could not mount /proc and EVERY Bash tool call
  # in a cron spawn failed. Folding the server id in re-runs the provisioner
  # whenever the host is replaced.
  triggers_replace = {
    seccomp_profile = sha256(file("${path.module}/seccomp-bwrap.json"))
    server_id       = hcloud_server.web.id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/docker/seccomp-profiles",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/seccomp-bwrap.json"
    destination = "/etc/docker/seccomp-profiles/soleur-bwrap.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      # Ubuntu 24.04 kernel restricts uid_map writes inside unprivileged user
      # namespaces even with apparmor=unconfined. Without this sysctl, bwrap
      # (the Claude Code Bash sandbox) cannot mount /proc and EVERY Bash tool
      # call in a cron spawn fails (#1557).
      #
      # A one-time `sysctl -w` is NOT drift-proof — it is lost on reboot, and a
      # bare /etc/sysctl.d drop-in can be re-restricted by an apparmor package
      # update or fail to apply on a degraded (full-disk) boot. Install a
      # boot-persistent oneshot unit that re-asserts the sysctl on EVERY boot,
      # and keep the sysctl.d drop-in as belt-and-braces. This closes the
      # reboot-drift half of the 2026-06-04 incident (#4927/#4928); the
      # fresh-host half is closed by the server_id trigger above.
      "echo 'kernel.apparmor_restrict_unprivileged_userns=0' > /etc/sysctl.d/99-bwrap-userns.conf",
      "cat > /etc/systemd/system/bwrap-userns-sysctl.service << 'UNITEOF'\n[Unit]\nDescription=Assert bwrap unprivileged-userns sysctl for the Claude Code Bash sandbox\nAfter=multi-user.target\n\n[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart=/usr/sbin/sysctl -w kernel.apparmor_restrict_unprivileged_userns=0\n\n[Install]\nWantedBy=multi-user.target\nUNITEOF",
      "systemctl daemon-reload",
      "systemctl enable --now bwrap-userns-sysctl.service",
      "echo 'Seccomp profile provisioned; bwrap userns sysctl asserted via boot-persistent unit'",
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
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/apparmor-soleur-bwrap.profile"
    destination = "/etc/apparmor.d/soleur-bwrap"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
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
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/orphan-reaper.sh"
    destination = "/usr/local/bin/orphan-reaper.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/orphan-reaper.sh",
      "cat > /etc/systemd/system/orphan-reaper.service << 'UNITEOF'\n[Unit]\nDescription=Orphaned workspace directory reaper\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/orphan-reaper.sh\nUNITEOF",
      "cat > /etc/systemd/system/orphan-reaper.timer << 'TIMEREOF'\n[Unit]\nDescription=Run orphan reaper every 6 hours\n\n[Timer]\nOnBootSec=10min\nOnUnitActiveSec=6h\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now orphan-reaper.timer",
      "systemctl list-timers orphan-reaper.timer --no-pager",
    ]
  }
}

# Container egress firewall for the web-platform container (#5046 PR-2).
# Default-drop DOCKER-USER allowlist: contains the 4 live spawn("bash") crons
# that bypass the #5018 PreToolUse hook (ADR-033 I7) and makes the hook's
# Task/Skill relax-minimal safe. Applied via SSH because cloud-init is dead on
# the running host (ignore_changes=[user_data]); cloud-init.yml mirrors the
# artifacts for fresh hosts. Post-apply asserts include a LIVE positive +
# negative container probe — `nft -f` exits 0 on an inert ruleset, so only a
# real probe proves enforcement (the silent-green guard, AC-P2.8).
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "cron_egress_firewall" {
  # Keyed on every delivered artifact AND the host id (hr-fresh-host-
  # provisioning: a replaced VM keeps identical hashes — folding the server id
  # re-runs the provisioner so the firewall is never silently absent).
  triggers_replace = {
    config_hash = sha256(join(",", [
      file("${path.module}/cron-egress-nftables.sh"),
      file("${path.module}/cron-egress-resolve.sh"),
      file("${path.module}/cron-egress-alarm.sh"),
      file("${path.module}/cron-egress-allowlist.txt"),
      file("${path.module}/cron-egress-allowlist-cidr.txt"),
      file("${path.module}/cron-egress-firewall.service"),
      file("${path.module}/cron-egress-resolve.service"),
      file("${path.module}/cron-egress-resolve.timer"),
      file("${path.module}/cron-egress-alarm@.service"),
      # #5289: fold the post-apply assertion block (now a delivered script) into
      # the hash so an edit to it re-provisions — inline-block edits were silent
      # no-ops (the block lived in the 2nd remote-exec, outside this hash).
      file("${path.module}/cron-egress-postapply-assert.sh"),
    ]))
    server_id = hcloud_server.web.id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # `file` (scp) does NOT create remote parents and /etc/soleur is not shipped
  # by any base package (2026-06-02 cloned-provisioner learning). nftables is
  # in the base Ubuntu 24.04 image but assert anyway (idempotent).
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/soleur",
      "command -v nft >/dev/null || (apt-get update && apt-get install -y nftables)",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-nftables.sh"
    destination = "/usr/local/bin/cron-egress-nftables.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-resolve.sh"
    destination = "/usr/local/bin/cron-egress-resolve.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-alarm.sh"
    destination = "/usr/local/bin/cron-egress-alarm.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-allowlist.txt"
    destination = "/etc/soleur/cron-egress-allowlist.txt"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-allowlist-cidr.txt"
    destination = "/etc/soleur/cron-egress-allowlist-cidr.txt"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-firewall.service"
    destination = "/etc/systemd/system/cron-egress-firewall.service"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-resolve.service"
    destination = "/etc/systemd/system/cron-egress-resolve.service"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-resolve.timer"
    destination = "/etc/systemd/system/cron-egress-resolve.timer"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-alarm@.service"
    destination = "/etc/systemd/system/cron-egress-alarm@.service"
  }

  # #5289: the post-apply assertion block was extracted from the inline
  # remote-exec below into this delivered script so an edit to it changes
  # config_hash and re-provisions (inline-block edits were silent no-ops). The
  # script body owns `set -e` and the ASSERT-FAILED sentinels; the runner below
  # just chmods + executes it. Same loader/resolver/orphan-reaper delivery shape.
  provisioner "file" {
    source      = "${path.module}/cron-egress-postapply-assert.sh"
    destination = "/usr/local/bin/cron-egress-postapply-assert.sh"
  }

  provisioner "remote-exec" {
    # `set -e` FIRST: terraform joins `inline` into ONE script with NO implicit
    # errexit, and the provisioner fails only on the LAST command's exit — so
    # without it the `bash …` failure could be masked by a trailing command.
    # The assertion logic itself lives in cron-egress-postapply-assert.sh (also
    # `set -e`-first, folded into config_hash above); this runner only delivers
    # errexit + chmod + execute.
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/cron-egress-postapply-assert.sh",
      "bash /usr/local/bin/cron-egress-postapply-assert.sh",
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
