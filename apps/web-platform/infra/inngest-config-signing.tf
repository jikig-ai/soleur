# GitHub Environment with a required-reviewer protection rule for the ADR-135 config-bundle
# signing workflow (#6780, HARD-7). The build-sign-publish job in
# .github/workflows/build-inngest-config-bundle.yml declares `environment: inngest-config-signing`,
# which holds each dispatch in "Waiting" for reviewer approval BEFORE any step runs — the human
# gate on the named top residual RCE path: whoever can run the signing workflow can sign + (via a
# separate promotion) ship a FRESH bundle, and the monotonic version gate does nothing against a
# fresh forgery. Mirrors github_repository_environment.inngest_cutover (inngest-arm-write-token.tf).
#
# No environment SECRET is attached (the TF GitHub App cannot write environment secrets — see the
# inngest-cutover note): the workflow authenticates with the built-in GITHUB_TOKEN (GHCR push),
# the OIDC id-token (keyless cosign), and the repo-level DOPPLER_TOKEN_PRD secret (zot bridge).
# The required-reviewer HUMAN-ACK is enforced purely by the JOB declaring this environment.
#
# reviewers.users takes numeric GitHub user IDs — 54279 = @deruelle (the operator/founder).
#
# #8780 / ADR-241 D2: the reviewer rule gates WHO approves; it never gated WHICH REF runs. A
# `workflow_dispatch` executes the SELECTED REF's workflow bytes, so a dispatch from a non-main
# branch ran that branch's build-sign-publish and asked the reviewer to approve what reads as a
# routine bundle publish — the same defect web-host-birth-environment.tf and
# inngest-arm-write-token.tf (#7695) already record. The deployment_branch_policy below is
# evaluated by GitHub BEFORE the job starts and never runs checked-out bytes; it is ADDITIVE to the
# reviewers (REVIEWERS_RATCHET in terraform-target-parity.test.ts requires the human gate to stay),
# not a replacement for it.
#
# APPLIES NOW (host-independent GitHub resource; does NOT touch the isolated soleur-inngest/prd
# self-check and does not ride the #6178 cutover). The producer workflow lands in this same PR, so
# this gate MUST exist before any dispatch — otherwise GitHub auto-creates the referenced
# `environment: inngest-config-signing` WITHOUT protection on first use and the HARD-7 human-ack is
# silently absent. apply-web-platform-infra.yml uses a `-target=`-scoped allow-list (NOT a full-root
# apply), so this resource is wired in there as `-target=github_repository_environment.inngest_config_signing`
# alongside inngest_cutover — a bare *.tf file is pruned by the target filter and never created.

resource "github_repository_environment" "inngest_config_signing" {
  repository  = "soleur"
  environment = "inngest-config-signing"

  reviewers {
    users = [54279]
  }

  # LOAD-BEARING, not cosmetic (same note as web-host-birth-environment.tf): omitting this block
  # leaves the environment with NO branch policy, which means any branch may deploy to it — the
  # reviewer is then shown a branch NAME, not a diff, and a non-main dispatch signs a bundle built
  # from branch bytes (#8780).
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# The named list the block above declares. `custom_branch_policies = true` says "this environment
# uses a named list" and nothing more; without this resource the list is EMPTY, which GitHub reads
# as "no branch may deploy" — the opposite failure from omitting the block, and equally wrong.
# Both halves are required.
resource "github_repository_environment_deployment_policy" "inngest_config_signing_main" {
  repository     = "soleur"
  environment    = github_repository_environment.inngest_config_signing.environment
  branch_pattern = "main"
}
