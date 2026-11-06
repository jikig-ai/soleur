# GitHub Environment with a required-reviewer protection rule for the KEY ROTATION
# route (#11923). The `approve` jobs in .github/workflows/key-rotate.yml and
# .github/workflows/inngest-key-rotate.yml declare `environment: key-rotate-approval`,
# which holds each rotate/converge dispatch in "Waiting" for reviewer approval BEFORE
# any step runs — the human authorization the typed `ROTATE-<KEY>-<DATE>` confirm never
# was (it is derivable from public inputs: a fat-finger guard, not an authorization).
# Mirrors github_repository_environment.web_platform_infra_apply
# (web-host-birth-environment.tf).
#
# WHY A DEDICATED APPROVE JOB RATHER THAN REBINDING apply's environment:. The apply job
# runs on `environment: infra-privileged`, which carries the Tier-B env-scoped secret
# DOPPLER_TOKEN_INFRA_PRIVILEGED. Seeding that secret onto a second environment is a
# write the Terraform GitHub App cannot perform (403, ADR-100 fix-forward) and Tier-B
# keeps outside Terraform state entirely (ADR-241). A credential-free approve job buys
# the same gate with zero secret material. `infra-privileged` itself keeps ZERO
# reviewers deliberately — the unattended apply-on-merge and scheduled drift need it
# (infra-privileged-environment.tf); putting the reviewer on IT would block the route
# that environment exists to serve.
#
# THE #6780 VACUOUS-GATE LEARNING: a GitHub environment REFERENCED by a workflow but
# ABSENT from the apply path auto-creates UNPROTECTED on first use — zero reviewers,
# any branch, and no diff anywhere reports the downgrade. Three defenses land together
# here: (1) this file declares the environment in Terraform so reviewers.users is
# pinned, (2) it joins the `-target=` allow-list of apply-web-platform-infra.yml in the
# same PR so the protected environment exists before any dispatch can reference it —
# a bare *.tf in this root is pruned by the target filter and never applied — and
# (3) kk_chk_approval in scripts/key-rotate.sh reads the LIVE protection_rules at
# guard time and refuses `approval_environment_unprotected` if required_reviewers or
# the branch policy is absent, covering the window between merge and apply. The
# reviewers property is additionally ratcheted by REVIEWERS_RATCHET in
# plugins/soleur/test/terraform-target-parity.test.ts, which fails the build on an
# empty reviewers.users.
#
# reviewers.users takes numeric GitHub user IDs — 54279 = @deruelle (the
# operator/founder), the same convention as every reviewer-gated environment in this
# root.
#
# The branch policy is LOAD-BEARING, not cosmetic (the web-host-birth-environment.tf
# adoption note is the full writeup): `workflow_dispatch` runs the SELECTED ref's
# workflow and scripts, so without a main-only pin a dispatch can point the run at a
# branch carrying a neutered gate, and the reviewer prompt shows a branch name, not a
# diff. `custom_branch_policies = true` only declares that the environment consults a
# named list; the deployment-policy resource below is the list — both halves are
# required, and an empty custom list means "no branch may deploy".
#
# CREATION, NOT ADOPTION. No `key-rotate-approval` environment exists in the repo today
# (measured 2026-11-05 via `gh api repos/jikig-ai/soleur/environments`), so there is no
# import block and no `removed` forget — the provider's idempotent PUT still
# adopts-by-name if the environment is ever auto-created first.
resource "github_repository_environment" "key_rotate_approval" {
  repository  = "soleur"
  environment = "key-rotate-approval"

  reviewers {
    users = [54279]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# The custom policy the block above enables. `prevent_destroy` makes a replace or
# destroy of the main-only pin a hard plan error — a merge that carries a count-based
# `[ack-destroy]` cannot wave it through (the web_platform_infra_apply_main_adopted
# precedent).
resource "github_repository_environment_deployment_policy" "key_rotate_approval_main" {
  repository     = "soleur"
  environment    = github_repository_environment.key_rotate_approval.environment
  branch_pattern = "main"

  lifecycle {
    prevent_destroy = true
  }
}
