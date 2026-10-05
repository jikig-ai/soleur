# (#8189) Inputs, resolved from Doppler prd_terraform via `--name-transformer tf-var` under the
# SAME names the parent root uses. No new variable, no default, no human mint
# (hr-tf-variable-no-operator-mint-default).

variable "hcloud_token" {
  description = "Hetzner Cloud API token (same project credential as the parent root)."
  type        = string
  sensitive   = true
}

variable "doppler_token_tf" {
  description = "Doppler workplace-scope token for the doppler provider (creates the isolated project, its prd environment, the secret and the read token)."
  type        = string
  sensitive   = true
}

variable "github_app_id" {
  description = "GitHub App ID for the App-auth github provider (mirrored into prd_terraform)."
  type        = string
  sensitive   = true
  # LEGACY MODE ONLY since #8209 -- see main.tf. `default = ""` so a merge
  # before the Tier-B identity exists does not fail the whole apply (ADR-065).
  default = ""
}

variable "github_app_private_key" {
  description = "PEM private key for the GitHub App (mirrored into prd_terraform)."
  type        = string
  sensitive   = true
  # LEGACY MODE ONLY since #8209 -- see main.tf. `default = ""` so a merge
  # before the Tier-B identity exists does not fail the whole apply (ADR-065).
  default = ""
}

# --- #8209 / ADR-241: the Tier-A and Tier-B GitHub identities -----------------
#
# All four default to "" so this root can merge BEFORE the operator has provisioned
# anything (ADR-065). main.tf reads the empty string as "not supplied", which is what
# selects the LEGACY mode and keeps the before state working. Full rationale lives in
# apps/web-platform/infra/variables.tf, which owns the same four variables.
#
# These are DOPPLER names. GitHub reserves the GITHUB_* prefix for Actions secrets and
# secret names are case-insensitive, so GITHUB_INFRA_APP_* can never be an Actions
# secret.

variable "github_plan_actions_credential" {
  description = "The PR plan job's own Actions credential (github.token), used in TOKEN mode for a read-only `terraform plan -refresh=false`. Tier A and bounded: job-scoped, expires with the run, cannot write."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_infra_app_id" {
  description = "App ID of the dedicated soleur-infra App (Tier B, operator-created at operator step O1)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_infra_app_installation_id" {
  description = "Installation ID of soleur-infra on the jikig-ai org (Tier B). A variable rather than a literal because this installation does not exist until the operator creates it."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_infra_app_private_key" {
  description = "PEM-encoded private key for the soleur-infra App (Tier B, delivered only as an environment secret on a main-only environment). Its non-emptiness selects INFRA mode in main.tf."
  type        = string
  sensitive   = true
  default     = ""
}
