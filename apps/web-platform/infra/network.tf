# Epic #5274 Phase 2 PR B / ADR-068 — the FIRST hcloud_network in this root.
#
# Until Phase 2 the web host had only a public interface. The multi-host
# /workspaces split needs a private L2 between the web host and the new git-data
# host so git transport (push/ls-remote) and the liveness probe never touch the
# public internet (git-data's public interface is deny-all; see git-data.tf).
#
# Gap 3 (plan §Infrastructure): no hcloud_network existed before. These three
# resources are pure +create. The hcloud_server_network attachments are ADDITIVE
# online attaches — they do NOT replace hcloud_server.web (server.tf) or
# hcloud_server.git_data (git-data.tf): an inline `network {}` block on the
# server resource WOULD force-replace the host, so a SEPARATE
# hcloud_server_network resource is used instead.

resource "hcloud_network" "private" {
  name     = "soleur-private"
  ip_range = "10.0.0.0/16"

  labels = {
    app = "soleur-web-platform"
  }
}

# network_zone (NOT location) — Hetzner private networks are zonal. "eu-central"
# spans hel1/fsn1/nbg1. var.location defaults to "hel1", which IS in eu-central,
# so the web + git-data hosts (both in var.location) are reachable on this subnet.
# If var.location is ever moved out of hel1/fsn1/nbg1, this network_zone must move
# with it (e.g. us-east for ash, us-west for hil).
resource "hcloud_network_subnet" "private" {
  network_id   = hcloud_network.private.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# Attach the EXISTING web host at a stable private IP. ADDITIVE online attach —
# does NOT replace hcloud_server.web (that would drop production). subnet_id (not
# network_id) so Terraform orders this AFTER the subnet exists.
resource "hcloud_server_network" "web" {
  for_each  = var.web_hosts
  server_id = hcloud_server.web[each.key].id
  subnet_id = hcloud_network_subnet.private.id
  ip        = each.value.private_ip
}

# Attach the git-data host at a stable private IP. git-auth.ts (web host, runtime)
# targets this address for git transport over the private net.
resource "hcloud_server_network" "git_data" {
  server_id = hcloud_server.git_data.id
  subnet_id = hcloud_network_subnet.private.id
  ip        = "10.0.1.20"
}

# #6122 (ADR-093) — attach the zot registry host at a stable private IP. Web hosts + CI
# `docker pull` our platform images from ${this ip}:5000 over the private net (zot-registry.tf
# local.registry_private_ip). Same ADDITIVE online-attach shape as git_data above.
resource "hcloud_server_network" "registry" {
  server_id = hcloud_server.registry.id
  subnet_id = hcloud_network_subnet.private.id
  ip        = "10.0.1.30"
}
