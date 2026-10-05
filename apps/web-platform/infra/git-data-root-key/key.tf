# (#8189, ADR-220) The git-data root key and its Hetzner public-key object.
#
# The Hetzner object is what the web-platform root's `data "hcloud_ssh_keys" "git_data_root"`
# selects by label; both host-creating gates additionally require its SHA256 fingerprint to equal
# the committed apps/web-platform/infra/git-data-root-key.fingerprint (a label and a name can be
# forged by any HCLOUD_TOKEN holder; the committed fingerprint cannot be, on a dispatch from main).
#
# THAT HOLDS ONLY FOR DISPATCHES FROM `main`. The gates read the fingerprint from the dispatched
# ref's checkout. git_data_host_create is environment-gated to main, so its anchor is the reviewed
# one. git_data_host_replace has no environment:, so a branch dispatch supplies its own anchor and a
# repo-write actor is not held off there (tracked on #8093).

resource "tls_private_key" "git_data_root" {
  algorithm = "ED25519"

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_ssh_key" "git_data_root" {
  name       = "soleur-git-data-root"
  public_key = tls_private_key.git_data_root.public_key_openssh

  labels = {
    "soleur-role" = "git-data-root"
  }

  lifecycle {
    prevent_destroy = true
  }
}
