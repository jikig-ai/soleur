# #9294 / ADR-241 — the deploy-channel carrier: an unattended main-only `deploy-channel`
# GitHub environment plus the narrow `soleur-deploy-channel` Doppler project holding only
# the deploy-channel credential family the non-Terraform consumers read.
#
# WHY THIS FILE HOLDS NO SECRET, NO TOKEN AND NO DATA SOURCE.
#
# Everything this root creates lands in `web-platform/terraform.tfstate`, and the
# `prd_terraform` backend keys READ that object (ADR-241 D3/D4 — the same measurement
# infra-app-project.tf cites literally and infra-privileged-environment.tf reaches as
# "measured, M7"). A `doppler_secret`, a
# `doppler_service_token` or a `data "doppler_secret(s)"` on this project would put the
# values, or a token that reads them, straight back into the tier this move exists to
# evict them from. The project and the environment are the CARRIERS; the operator-run
# seed copies the values in hash-equal and mints the read token (the owner-named step
# between PR-A and PR-B). That asymmetry is the whole design:
#
#   Terraform creates the container -> the container is in Tier-A-readable state, and
#   that is harmless, because a container's existence is not a secret.
#   The operator fills the container -> the values never touch state at all.
#
# Same carrier shape as infra-app-project.tf (ADR-241 D11); Census Guard 7
# (tests/scripts/test-infra-privileged-tier-census.sh) enforces it for this project too.
#
# Every resource here is in the `-target=` allow-list of apply-web-platform-infra.yml.
# A bare *.tf file is pruned by that filter and would never apply.

# --- The unattended deploy-channel environment ---------------------------------
#
# Distinct from `web-platform-infra-apply` (web-host-birth-environment.tf), which has a
# REVIEWER and therefore blocks an unattended run. This one has no reviewer and exists
# only to carry the branch policy: the boundary #9294 buys is "only `main` can reach
# this secret", not "a human clicked". The jobs that will bind it (PR-B: release deploy,
# the inngest redeploys, the scheduled probe, the sweeper arm) are unattended by design.
resource "github_repository_environment" "deploy_channel" {
  repository  = "soleur"
  environment = "deploy-channel"

  # NO `reviewers` block. An environment with zero reviewers auto-approves, which is
  # what the unattended consumers need. The protection that matters is below.
  #
  # LOAD-BEARING, not cosmetic (same note as infra-privileged-environment.tf): omitting
  # this block leaves the environment with NO branch policy, which means any branch may
  # deploy to it -- and that is precisely the reach this change exists to remove. An
  # environment a job references but that does not yet exist is auto-created by GitHub
  # with no protection at all, which is why the two-PR sequence creates the policy
  # BEFORE any workflow names the environment, and why the owner-named seed step gates
  # on reading the LIVE policy back before any secret is set.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }

  # Deliberately no `prevent_destroy` here or on the policy below: environment secrets die with the environment.
}

# The named list the block above declares. `custom_branch_policies = true` says "this
# environment uses a named list" and nothing more; without this resource the list is
# EMPTY, which GitHub reads as "no branch may deploy" -- the opposite failure from
# omitting the block, and equally wrong. Both halves are required.
resource "github_repository_environment_deployment_policy" "deploy_channel_main" {
  repository     = "soleur"
  environment    = github_repository_environment.deploy_channel.environment
  branch_pattern = "main"
}

# --- The narrow deploy-channel Doppler project ---------------------------------
#
# A PROJECT, not a `prd_*` branch config of `soleur` — the #8209 lesson again: a branch
# config inherits from its root, so `soleur/prd_terraform` is how the deploy-channel
# credentials became branch-reachable in the first place. The project is NARROW by
# design (the D11 precedent): the Tier-B loader exports the whole selected project into
# every job bound to it, so holding the family inside soleur-infra-privileged would
# hand every consumer HCLOUD_TOKEN read/write to deliver a deploy-trigger credential.
# This project holds only the deploy-channel family, so a leaked read token reaches
# nothing else.
#
# CI reads it through DOPPLER_TOKEN_DEPLOY_CHANNEL, a GitHub ENVIRONMENT secret on the
# main-only `deploy-channel` environment above (and on `inngest-cutover`, the reviewer-
# gated ops environment that keeps its human gate). The token is operator-minted; a
# TF-minted token would land in Tier-A-readable state.
resource "doppler_project" "deploy_channel" {
  name = "soleur-deploy-channel"
  # Doppler's API caps `description` at 255, unchecked by the provider and by plan;
  # scripts/lint-doppler-description-length.py enforces it at PR time.
  description = "#9294 ADR-241: the narrow Tier-B project holding only the deploy-channel credential family for the non-Terraform consumers, isolated from whole-project soleur-infra-privileged. Operator-supplied; never in tfstate."

  lifecycle {
    # The project holds a live copy of the deploy-channel credentials after the
    # owner-named seed runs. A destroy here is a credential loss plus a deploy-channel
    # outage, and the only way to reach one is an edit to this file -- which is the
    # review surface this pin creates.
    prevent_destroy = true
  }
}

# A TF-created doppler_project is created BARE — no default dev/stg/prd configs — so
# without this the operator's first `doppler secrets set -c prd` fails with "Could not
# find requested config 'prd'". Creating the environment also creates its same-named
# ROOT config, which is the isolation boundary the deploy-channel read token resolves
# against. Mirrors doppler_environment.infra_app_prd (infra-app-project.tf).
resource "doppler_environment" "deploy_channel_prd" {
  project = doppler_project.deploy_channel.name
  slug    = "prd"
  name    = "Production"

  lifecycle {
    prevent_destroy = true
  }
}
