# placement-group.tf — HA spread + the singleton→for_each migration (#5274 Phase 3,
# ADR-068). Placement groups are free (Hetzner: max 10 servers/group; 2 used).
#
# `type = "spread"` guarantees the web hosts land on DIFFERENT physical servers
# within the EU location, so a single hardware failure cannot take both down.

resource "hcloud_placement_group" "web_spread" {
  name = "soleur-web-spread"
  type = "spread"

  labels = {
    app = "soleur-web-platform"
  }
}

# --- Singleton → for_each migration (0-destroy) ------------------------------
# The web host + its /workspaces volume + attachment + private-net attach were
# singletons (pre-Phase-3). These `moved` blocks re-address the EXISTING state to
# the `web-1` for_each key WITHOUT destroy/recreate — provided web-1's attributes
# in var.web_hosts match current state (name/location/server_type/private_ip).
# `terraform plan` MUST show `0 to destroy` before apply. Keys are IMMUTABLE
# post-migration (Kieran sharp edge: never rename for_each keys).
moved {
  from = hcloud_server.web
  to   = hcloud_server.web["web-1"]
}

moved {
  from = hcloud_volume.workspaces
  to   = hcloud_volume.workspaces["web-1"]
}

moved {
  from = hcloud_volume_attachment.workspaces
  to   = hcloud_volume_attachment.workspaces["web-1"]
}

moved {
  from = hcloud_server_network.web
  to   = hcloud_server_network.web["web-1"]
}
