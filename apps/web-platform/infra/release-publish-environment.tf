# #8780 / ADR-241 D2 — the publish-admission environment: a reviewer-less, secrets-free,
# main-only admission gate for the unattended publish jobs.
#
# WHY THIS FILE HOLDS NO SECRET.
#
# `release-publish` is an ADMISSION gate, not a credential carrier. The jobs that declare it —
# `reusable-release.yml::release` (which covers both callers, `web-platform-release.yml` and
# `version-bump-and-release.yml`) and `build-inngest-bootstrap-image.yml::build` — mint no Tier-B
# secret: they authenticate with the built-in GITHUB_TOKEN (release/tag writes, GHCR push) and the
# OIDC id-token (keyless cosign). Binding them to `infra-privileged` instead was considered and
# cut: that environment hands every declaring job the broad Tier-B
# `DOPPLER_TOKEN_INFRA_PRIVILEGED`, which would widen the secret boundary to buy an admission
# property this secrets-free environment buys for free. Do NOT attach a
# `github_actions_environment_secret` or any secret to this environment — an `environment:`
# declaration grants the env's secrets to the job, so one added secret re-widens the boundary the
# design keeps narrow.
#
# WHY NO REVIEWER.
#
# The publish jobs are unattended (the auto-mint dispatches, the push-arm releases). A required
# reviewer deadlocks them by design — the same reasoning `infra-privileged` carries in
# infra-privileged-environment.tf (ADR-241 D2). The protection that matters is the branch policy
# below: GitHub evaluates it BEFORE the job starts, against the run's ref, so a `workflow_dispatch`
# of any publish workflow from a non-`main` ref is refused before a step runs — a property the
# dispatched ref's own workflow bytes cannot weaken, because the check never executes them. A
# YAML-side dispatch-ref guard was considered and cut for exactly that reason: a hostile dispatch
# runs the branch's YAML, so a check inside it is self-disarming.
#
# WHY IT MUST EXIST BEFORE ANY JOB REFERENCES IT.
#
# An environment a job references but that does not yet exist is auto-created by GitHub with NO
# protection at all (the same hazard inngest-config-signing.tf and infra-privileged-environment.tf
# record). The targeted apply in apply-web-platform-infra.yml wires this resource in as
# `-target=github_repository_environment.release_publish`; a bare *.tf file is pruned by that
# filter and would never apply. The apply runs on merge to main, before any legitimate dispatch —
# and if a dispatch wins the race anyway, the apply still attaches the policy (environments are
# create-or-update), so the auto-created unprotected state self-heals at apply.

resource "github_repository_environment" "release_publish" {
  repository  = "soleur"
  environment = "release-publish"

  # NO `reviewers` block — see the header: an environment with zero reviewers auto-approves, which
  # is what the unattended publish jobs need. The protection that matters is below.
  #
  # LOAD-BEARING, not cosmetic (same note as infra-privileged-environment.tf): omitting this block
  # leaves the environment with NO branch policy, which means any branch may deploy to it — and
  # that is precisely the non-main-dispatch reach #8780 exists to remove.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# The named list the block above declares. `custom_branch_policies = true` says "this environment
# uses a named list" and nothing more; without this resource the list is EMPTY, which GitHub reads
# as "no branch may deploy" — the opposite failure from omitting the block, and equally wrong.
# Both halves are required.
resource "github_repository_environment_deployment_policy" "release_publish_main" {
  repository     = "soleur"
  environment    = github_repository_environment.release_publish.environment
  branch_pattern = "main"
}
