# (#8189, ADR-220) Custody of the private half and the one read credential.
#
# A SEPARATE Doppler project, not a `prd` branch config: a branch-config token resolves the whole
# `prd` root (workspaces-luks.tf, "THE MECHANISM IS INHERITANCE DIRECTIONALITY"). A TF-created
# project is bare, so the environment below also creates the `prd` root config the secret and the
# token address (precedent: doppler_environment.registry_prd, doppler_environment.inngest_prd).

resource "doppler_project" "git_data_root" {
  name        = "soleur-git-data-root"
  description = "Isolated custody of the git-data root SSH private key (#8189, ADR-220). Its prd root config holds only GIT_DATA_ROOT_SSH_PRIVATE_KEY; cross-project isolation from soleur/prd."

  lifecycle {
    prevent_destroy = true
  }
}

resource "doppler_environment" "git_data_root_prd" {
  project = doppler_project.git_data_root.name
  slug    = "prd"
  name    = "Production"

  lifecycle {
    prevent_destroy = true
  }
}

resource "doppler_secret" "git_data_root_ssh_private_key" {
  project    = doppler_project.git_data_root.name
  config     = doppler_environment.git_data_root_prd.slug
  name       = "GIT_DATA_ROOT_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_data_root.private_key_openssh
  visibility = "masked"

  lifecycle {
    prevent_destroy = true
  }
}

# Read-only on the isolated config. The provider has no expiry attribute; revocation is a reviewed
# `-replace` (the apply workflow's typed rotate_read_token input) or a removal PR (ADR-220 D3).
resource "doppler_service_token" "git_data_root_read" {
  project = doppler_project.git_data_root.name
  config  = doppler_environment.git_data_root_prd.slug
  name    = "git-data-root-read"
  access  = "read"
}

# Repo secret (environment secrets are not writable by the Terraform App). NO ignore_changes: a
# token rotation must reach the secret in the same apply.
resource "github_actions_secret" "doppler_token_git_data_root" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_GIT_DATA_ROOT"
  plaintext_value = doppler_service_token.git_data_root_read.key
}
