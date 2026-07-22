# GitHub Environment with a required-reviewer protection rule for the ADR-133 config-bundle
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
# Applies via the normal apply-web-platform-infra.yml path (a GitHub resource, host-independent —
# it does NOT touch the isolated soleur-inngest/prd self-check and does not ride the #6178 cutover).

resource "github_repository_environment" "inngest_config_signing" {
  repository  = "soleur"
  environment = "inngest-config-signing"

  reviewers {
    users = [54279]
  }
}
