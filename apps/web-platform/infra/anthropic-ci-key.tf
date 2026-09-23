# #8505 — the CI/eval Anthropic key, distributed by Terraform.
#
# CI and manual evals bill a key minted in the `soleur-ci-eval` Console workspace
# (wrkspc_01GCfbuC9cVBXiWkkEfnyi4D, org d8d6285b…), which carries a $100/month spend
# limit, so an eval grid can never drain the org balance production draws on. The
# key is minted in the Console (the Admin API cannot set a workspace spend limit and
# there is no Anthropic Terraform provider); the procedure and its records live in
# knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md.
# ADR-242 records the partition decision.
#
# Both writers below are the ONLY Terraform writers of these two slots. Neither
# carries `ignore_changes`, so a hand edit of Doppler `ci` or of the repo secret is
# drift that the next apply reverts.

resource "doppler_secret" "ci_anthropic_api_key" {
  project    = "soleur"
  config     = "ci"
  name       = "ANTHROPIC_API_KEY"
  value      = var.anthropic_api_key_ci
  visibility = "masked"

  lifecycle {
    # The one property this file exists for: CI never holds the production key.
    # The production value is read ONLY here — a precondition is not persisted to
    # state. The message is static on purpose: an error_message that references a
    # sensitive variable makes `terraform plan` hard-error instead of reporting.
    precondition {
      condition     = var.anthropic_api_key_ci != var.anthropic_api_key && startswith(var.anthropic_api_key_ci, "sk-ant-")
      error_message = "anthropic_api_key_ci must be an sk-ant- key distinct from the production anthropic_api_key (#8505)."
    }
  }
}

resource "github_actions_secret" "anthropic_api_key" {
  repository  = "soleur"
  secret_name = "ANTHROPIC_API_KEY"
  value       = var.anthropic_api_key_ci

  lifecycle {
    precondition {
      condition     = var.anthropic_api_key_ci != var.anthropic_api_key && startswith(var.anthropic_api_key_ci, "sk-ant-")
      error_message = "anthropic_api_key_ci must be an sk-ant- key distinct from the production anthropic_api_key (#8505)."
    }
  }
}
