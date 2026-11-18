# soleur-bastion — the dedicated SSH bastion (#12866, ADR-327 step 2a; CTO rulings F4, F5, F8).
#
# Step 2 builds the host and nothing dials it: sshd is masked, the Hetzner firewall has zero inbound
# rules, and the host's own nftables drops inbound and allowlists egress (bastion-cloud-init.yml,
# bastion-egress.sh). Step 3 (#12867) unmasks sshd with its first dialer.
#
# BIRTH ONLY THROUGH apply_target=bastion-host-create. Every address in this file is listed in
# tests/scripts/lib/bastion-resources.txt (the birth gate's allow-set and the job's -target lines)
# and in OPERATOR_APPLIED_EXCLUSIONS, so the per-merge apply never reaches the bastion. Changing
# anything here is a replace (bastion-host-replace, #12879).

# (F5) Terraform-minted host key, copied from git-data's tls_private_key + ssh_keys pattern. It does
# NOT rotate on a replace: the replacement boots with the same key, so step 3's pin stays valid.
#
# EXPOSURE (the git-data residual, ADR-327): the private half sits in this root's state (here; the
# locked hcloud provider stores hcloud_server.bastion.user_data as a hash, userDataHashSum), in the
# runner-local plan file of a birth run, and the Hetzner metadata endpoint serves user_data to root
# on the host. A leaked copy stays valid until a deliberate rotation (runbook bastion-host.md).
resource "tls_private_key" "bastion_host_ssh" {
  algorithm = "ED25519"
}

locals {
  # The host's own file owns its private IP, as git-data owns local.git_data_private_ip. Distinct
  # from every var.web_hosts private_ip and the fixed hosts (.20 git-data, .30 registry, .40 inngest,
  # .50 reserved); the precondition below and bastion.test.sh SHAPE both check it.
  bastion_private_ip = "10.0.1.70"
  bastion_host_name  = "soleur-bastion"
}

data "hcloud_server_type" "bastion" {
  name = "cx23"
}

resource "hcloud_server" "bastion" {
  name = local.bastion_host_name
  # A literal, not a variable (F4): a type change is the owner's money decision, and a variable
  # invites a silent -var. If cx23 is out of stock the stock gate refuses; do not switch type here.
  server_type = "cx23"
  location    = var.location
  image       = "ubuntu-24.04"
  # git-data's shape: the default key, so Hetzner never mints a root password. Create-time only.
  ssh_keys = [hcloud_ssh_key.default.id]

  # (F8) A public IPv4 for egress only (no NAT gateway exists in this account). No IPv6, so no path
  # bypasses the IPv4 allowlist.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  user_data = templatefile("${path.module}/bastion-cloud-init.yml", {
    host_name  = local.bastion_host_name
    sentry_dsn = var.sentry_dsn
    # The egress allowlist's Sentry row. server.tf's one DSN parser; "" for an empty DSN, which the
    # job's DSN assertion refuses before any create.
    sentry_ingest_host           = local.sentry_dsn_parts.host
    private_ip                   = local.bastion_private_ip
    host_ssh_ed25519_private_key = tls_private_key.bastion_host_ssh.private_key_openssh
    host_ssh_ed25519_public_key  = trimspace(tls_private_key.bastion_host_ssh.public_key_openssh)
    bastion_egress_b64           = base64encode(file("${path.module}/bastion-egress.sh"))
  })

  lifecycle {
    # Also the referencing edge that keeps data.hcloud_server_type.bastion alive under -target.
    precondition {
      condition     = data.hcloud_server_type.bastion.architecture == "x86"
      error_message = "cx23 must be x86 (Hetzner reports architecture=${data.hcloud_server_type.bastion.architecture}); the bastion's cloud-init assumes amd64 packages."
    }
    # Same shape check as inngest-host.tf: the DSN is interpolated raw into the cloud-config, so a
    # trailing newline makes the whole document unparseable. Empty stays legal here so bare
    # validate/test plans resolve; the bastion-host-create job asserts it non-empty before it plans.
    precondition {
      condition     = nonsensitive(var.sentry_dsn == "" || can(regex("^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+$", var.sentry_dsn)))
      error_message = "var.sentry_dsn (TF_VAR_sentry_dsn from Doppler prd_terraform SENTRY_DSN) is not a well-formed Sentry DSN (https://<key>@<host>/<project>, no whitespace or trailing newline). The bastion's readiness event would never be sent."
    }
    precondition {
      condition = (
        cidrhost(hcloud_network_subnet.private.ip_range, 70) == local.bastion_private_ip &&
        !contains([for h in values(var.web_hosts) : h.private_ip], local.bastion_private_ip) &&
        !contains([local.git_data_private_ip, local.registry_private_ip, local.inngest_private_ip, var.grok_dogfood_private_ip], local.bastion_private_ip)
      )
      error_message = "local.bastion_private_ip=${local.bastion_private_ip} must be inside ${hcloud_network_subnet.private.ip_range} and distinct from every web host and fixed host private IP."
    }
    ignore_changes = [ssh_keys]
  }

  labels = {
    app  = "soleur-web-platform"
    role = "bastion"
  }
}

resource "hcloud_server_network" "bastion" {
  server_id = hcloud_server.bastion.id
  subnet_id = hcloud_network_subnet.private.id
  ip        = local.bastion_private_ip
}

# (F8) Zero inbound rules = deny-all on the public interface. Bound by the separate attachment
# below (git-data's form), never inline firewall_ids: the birth gate reads that binding.
resource "hcloud_firewall" "bastion" {
  name = "soleur-bastion"

  labels = {
    app  = "soleur-web-platform"
    role = "bastion"
  }
}

resource "hcloud_firewall_attachment" "bastion" {
  firewall_id = hcloud_firewall.bastion.id
  server_ids  = [hcloud_server.bastion.id]
}

output "bastion_ssh_host_key_fingerprint" {
  description = "SHA256 fingerprint of the bastion SSH host key (tls_private_key.bastion_host_ssh); step 3 pins it."
  value       = tls_private_key.bastion_host_ssh.public_key_fingerprint_sha256
}

output "bastion_private_ip" {
  description = "The bastion's private-network address, as the NIC attachment holds it."
  # From the attachment, not the local: under -target a root output is written only when it depends
  # on a targeted resource, so a local-only output is never in state and `terraform output` fails.
  value = hcloud_server_network.bastion.ip
}
