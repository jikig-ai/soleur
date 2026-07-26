# GitHub Environment with a required-reviewer protection rule for the web-host BIRTH
# dispatch (#6730, ADR-145). The `web_host_create` job in
# .github/workflows/apply-web-platform-infra.yml declares
# `environment: web-platform-infra-apply`, which holds each dispatch in "Waiting" for
# reviewer approval BEFORE any step runs. Mirrors
# github_repository_environment.inngest_config_signing (inngest-config-signing.tf).
#
# WHY THIS RESOURCE EXISTS RATHER THAN JUST THE LIVE ENVIRONMENT. The environment
# `web-platform-infra-apply` already existed in the repo with reviewer 54279 — but
# untracked, created outside terraform. An untracked environment's reviewer set is
# governed by nothing: emptying it in the GitHub UI leaves a zero-reviewer environment,
# which AUTO-APPROVES, and no test in this repo goes red. That would silently convert
# the sole human authorization for birthing a production host into no authorization at
# all. Declaring it here brings it under the DP-11 F8 guard in
# plugins/soleur/test/terraform-target-parity.test.ts, which fails the build on an empty
# reviewers.users.
#
# ADOPTION, NOT CREATION. The GitHub environments API is an idempotent PUT on the
# environment NAME, so the provider's create adopts the existing environment instead of
# colliding with it.
#
# ADOPTION IS ONLY ZERO-DRIFT IF IT DECLARES EVERY PROTECTION THE LIVE ENVIRONMENT HAS —
# and an earlier revision of this file did not. It declared `reviewers` alone and claimed
# "zero-drift, changes no live protection" on the strength of a reviewers-only check. The
# live environment carries TWO protection rules, measured 2026-07-26:
#
#   gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply
#     protection_rules: [required_reviewers, branch_policy]
#     deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
#   gh api .../deployment-branch-policies  ->  1 policy, name "main"
#
# The provider serializes an omitted `deployment_branch_policy` as null, and the API reads
# null as "allow all branches". So the reviewers-only declaration would have DELETED the
# main-only pin on the next apply — and that pin is what makes this gate meaningful at all:
# `workflow_dispatch` runs the SELECTED REF's workflow and its scripts, and the birth job
# sources its only check from `${GITHUB_WORKSPACE}`. Without the branch policy, anyone who
# can dispatch can point the run at a branch carrying a neutered gate, and the reviewer
# prompt shows a branch name, not a diff. The PR would have removed a live security control
# on the environment it exists to harden.
#
# This is why the three siblings this file "mirrors" are the wrong template for the branch
# policy specifically: `workspaces-luks-cutover`, `inngest-config-signing` and
# `inngest-cutover` all carry `deployment_branch_policy: null` (measured, same date). Mirror
# a precedent's SHAPE, never its guarantees — the sibling's guarantee is not this one's.
#
# reviewers.users takes numeric GitHub user IDs — 54279 = @deruelle (the operator/founder).
#
# apply-web-platform-infra.yml uses a `-target=`-scoped allow-list (NOT a full-root
# apply), so this resource is wired in there as
# `-target=github_repository_environment.web_platform_infra_apply` alongside its three
# siblings — a bare *.tf file is pruned by the target filter and never applied.

resource "github_repository_environment" "web_platform_infra_apply" {
  repository  = "soleur"
  environment = "web-platform-infra-apply"

  reviewers {
    users = [54279]
  }

  # LOAD-BEARING, not cosmetic — see the ADOPTION note above. Omitting this block deletes
  # the live main-only pin and makes the birth gate branch-supplied.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# The custom policy the block above enables. `custom_branch_policies = true` only declares
# that the environment uses a named list; without this resource the list is EMPTY, which
# GitHub treats as "no branch may deploy" — the opposite failure from omitting the block
# entirely, and just as wrong. Both halves are required to reproduce live state.
resource "github_repository_environment_deployment_policy" "web_platform_infra_apply_main" {
  repository     = "soleur"
  environment    = github_repository_environment.web_platform_infra_apply.environment
  branch_pattern = "main"
}
