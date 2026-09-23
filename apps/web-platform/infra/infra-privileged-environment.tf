# #8209 / ADR-239 — the Tier-B carrier: an unattended main-only environment, an empty
# Doppler project, and a second state bucket.
#
# WHY THIS FILE HOLDS NO SECRET AND NO TOKEN.
#
# Everything this root creates lands in `web-platform/terraform.tfstate`, and the
# `prd_terraform` backend keys READ that object (measured, M7: listing the bucket with
# those keys returns all seven state objects). So any value Terraform mints here is
# readable by exactly the tier this change exists to evict it from. The project and the
# environment are the CARRIERS; the operator puts the values in, by hand, out of band,
# and the runbook records how. That asymmetry is the whole design:
#
#   Terraform creates the container -> the container is in Tier-A-readable state, and
#   that is harmless, because a container's existence is not a secret.
#   The operator fills the container -> the values never touch state at all.
#
# A `doppler_secret` or a `doppler_service_token` resource in this file would silently
# undo #8209. Do not add one. ADR-130 covers the same rule for the R2 token: no
# credential we hold can mint a bucket-scoped R2 token programmatically, so that one is
# operator-minted too (operator step O8).
#
# Every resource here is in the `-target=` allow-list of apply-web-platform-infra.yml.
# A bare *.tf file is pruned by that filter and would never apply.

# --- The unattended Tier-B environment ---------------------------------------
#
# Distinct from `web-platform-infra-apply` (web-host-birth-environment.tf), which has a
# REVIEWER and therefore blocks an unattended run. This one has no reviewer and exists
# only to carry the branch policy: the boundary #8209 buys is "only `main` can reach
# this secret", not "a human clicked". Jobs that already declare a reviewer-gated
# environment keep it and carry the same secret there.
resource "github_repository_environment" "infra_privileged" {
  repository  = "soleur"
  environment = "infra-privileged"

  # NO `reviewers` block. An environment with zero reviewers auto-approves, which is
  # what an apply-on-merge and the scheduled drift check need. The protection that
  # matters is below.
  #
  # LOAD-BEARING, not cosmetic (same note as web-host-birth-environment.tf): omitting
  # this block leaves the environment with NO branch policy, which means any branch may
  # deploy to it -- and that is precisely the reach this change exists to remove. An
  # environment a job references but that does not yet exist is auto-created by GitHub
  # with no protection at all, which is why operator step O0 gates on reading the LIVE
  # policy back before any secret is seeded.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# The named list the block above declares. `custom_branch_policies = true` says "this
# environment uses a named list" and nothing more; without this resource the list is
# EMPTY, which GitHub reads as "no branch may deploy" -- the opposite failure from
# omitting the block, and equally wrong. Both halves are required.
resource "github_repository_environment_deployment_policy" "infra_privileged_main" {
  repository     = "soleur"
  environment    = github_repository_environment.infra_privileged.environment
  branch_pattern = "main"
}

# --- The Tier-B Doppler project ----------------------------------------------
#
# A PROJECT, not a `prd_*` branch config of `soleur`. That is the whole lesson of
# learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md:
# a branch config inherits from its root, and a token that reads the root reads the
# branch. `prd_terraform` IS a branch config of `prd` (measured, M1), which is how the
# four credentials became branch-reachable in the first place.
resource "doppler_project" "infra_privileged" {
  name = "soleur-infra-privileged"
  # Doppler caps description at 255 chars (see doppler_project.inngest) — the full
  # rationale is in the header comment above, not here.
  description = "Tier B (#8209, ADR-239): credentials that write infra, read another tier's secrets, or reach third-party installations. Read only via DOPPLER_TOKEN_INFRA_PRIVILEGED, an environment secret on main-only environments. Values are operator-supplied; none passes through tfstate."

  lifecycle {
    # The project holds every privileged credential after the operator sequence runs.
    # A destroy here is a production outage plus a credential loss, and the only way to
    # reach one is an edit to this file -- which is the review surface this pin creates.
    prevent_destroy = true
  }
}

# A TF-created doppler_project is created BARE — no default dev/stg/prd configs — so
# without this the operator's first `doppler secrets set -c prd` fails with "Could not
# find requested config 'prd'". Creating the environment also creates its same-named
# ROOT config, which is the isolation boundary the Tier-B read token resolves against.
# Mirrors doppler_environment.inngest_prd (inngest-host.tf) including its `name`.
resource "doppler_environment" "infra_privileged_prd" {
  project = doppler_project.infra_privileged.name
  slug    = "prd"
  name    = "Production"

  lifecycle {
    prevent_destroy = true
  }
}

# --- The privileged state bucket ---------------------------------------------
#
# The git-data root-key state object moves here (operator step O8). Today it sits in
# `soleur-terraform-state`, which the Tier-A `prd_terraform` AWS_* keys read -- so the
# root key that is root on the host storing every connected user's repositories is
# reachable from any branch workflow. The Tier-A keys are BUCKET-SCOPED (M7:
# ListBuckets returns AccessDenied), so a bucket they are not scoped to is genuinely
# out of reach rather than merely un-referenced.
#
# The bucket NAME is in code because a bucket name is not a secret; the bucket-scoped
# TOKEN is operator-minted and Tier-B only (ADR-130).
resource "cloudflare_r2_bucket" "terraform_state_privileged" {
  account_id = var.cf_account_id
  name       = "soleur-terraform-state-privileged"
  location   = "WEUR"
  provider   = cloudflare.r2

  lifecycle {
    # Destroying this bucket destroys the only copy of the git-data root-key state.
    prevent_destroy = true
  }
}
