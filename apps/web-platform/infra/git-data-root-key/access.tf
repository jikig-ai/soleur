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

# --- #8209 / ADR-241: FORGET the repo-secret custody path --------------------
#
# ADR-220 D4 already recorded this pair as a residual: `DOPPLER_TOKEN_GIT_DATA_ROOT` is
# a REPO secret, so every workflow on every branch of this public repository can name
# it, and it reads the isolated `soleur-git-data-root` project that holds the SSH
# private key that is root on the host storing every connected user's repositories. The
# isolation bought by a separate Doppler project and a separate Terraform root was
# undone by the carrier.
#
# The replacement is the SAME token on a main-only environment
# (`web-platform-infra-apply`, which `git-data-cutover.yml` already declares), seeded by
# the operator at step O7. An environment secret overrides a repo secret of the same
# name, so the cutover job needs no edit at all — which matters, because that file
# belongs to the parallel #8211 session.
#
# FORGET, NOT DESTROY. The token and the repo secret both stay live until the operator
# has seeded the environment copy (O7) and deleted the repo secret (O11). A destroy here
# would break the cutover path the moment this PR merges.
#
# WHY THIS ROOT'S FORGET NEEDS A TYPED ARM. apply-git-data-root-key.yml refuses any
# non-additive plan (ADR-220 D3, additive-only with no exceptions), and a forget is not
# additive. The one-shot `8209_custody_forget` arm in that workflow admits exactly these
# two addresses and nothing else — not a third address, and not a DELETE of either. The
# R6 follow-up removes the arm once the O8 dispatch has applied.
removed {
  from = doppler_service_token.git_data_root_read

  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_secret.doppler_token_git_data_root

  lifecycle {
    destroy = false
  }
}
