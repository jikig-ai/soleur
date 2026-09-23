# #8505 — the CI/eval Anthropic key, distributed by Terraform.
#
# CI and manual evals bill a key minted in the `soleur-ci-eval` Console workspace, which
# carries a monthly spend limit, so an eval grid cannot drain the org balance production
# draws on. Records and the mint procedure:
# knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md.
# Decision: ADR-243.
#
# What Terraform does NOT check: that this key differs from the production key. That is
# proven against LIVE Doppler by apps/web-platform/scripts/anthropic-key-distinctness.sh,
# across every prd* config. Comparing here would need the production key declared as a
# variable in this root, which writes it into the plan file on the runner and makes every
# apply depend on prd_terraform inheriting it (against #8209 and #8614). ADR-243 records
# the ruling. `var.anthropic_api_key_ci` only has its shape validated (variables.tf).
#
# These are the only Terraform writers of the two slots. Neither ignores `value`, so a hand
# edit is drift the next apply reverts. `prevent_destroy` because removing or renaming a
# resource without a `moved {}` / `removed { lifecycle { destroy = false } }` block DELETES
# the CI key, and CI Claude steps then soft-skip quietly rather than fail.

resource "doppler_secret" "ci_anthropic_api_key" {
  project    = "soleur"
  config     = "ci"
  name       = "ANTHROPIC_API_KEY"
  value      = var.anthropic_api_key_ci
  visibility = "masked"

  lifecycle {
    prevent_destroy = true
  }
}

# `value`, not the `plaintext_value` its siblings use: 6.12.1 marks `plaintext_value`
# deprecated in favour of `value`. Both write the same secret.
resource "github_actions_secret" "anthropic_api_key" {
  repository  = "soleur"
  secret_name = "ANTHROPIC_API_KEY"
  value       = var.anthropic_api_key_ci

  lifecycle {
    prevent_destroy = true
  }
}
