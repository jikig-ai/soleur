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
# colliding with it. The declared reviewer set is byte-identical to the live one
# (verified 2026-07-26: `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply`
# returns exactly [{id: 54279, login: deruelle}]), so the adoption is zero-drift — it
# changes no live protection, it only puts the existing one under version control.
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
}
