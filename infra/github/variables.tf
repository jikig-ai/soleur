variable "github_app_id" {
  description = "GitHub App ID for soleur-ai (id 3261325). Mirrored from `prd` to `prd_terraform` so the App-auth `provider \"github\"` block can resolve it (see main.tf). Migrated from `gh_token` PAT auth in #4384 per AGENTS.rules.md hr-github-app-auth-not-pat."
  type        = string
  sensitive   = true
  # LEGACY MODE ONLY since #8209 -- see main.tf. `default = ""` so a merge
  # before the Tier-B identity exists does not fail the whole apply (ADR-065).
  default = ""
}

variable "github_app_private_key" {
  description = "PEM-encoded RSA private key for the soleur-ai GitHub App. Mirrored from `prd` to `prd_terraform` for the App-auth provider. One-shot download at App creation; cannot be re-downloaded. Migrated from `gh_token` PAT auth in #4384."
  type        = string
  sensitive   = true
  # LEGACY MODE ONLY since #8209 -- see main.tf. `default = ""` so a merge
  # before the Tier-B identity exists does not fail the whole apply (ADR-065).
  default = ""
}

variable "gh_owner" {
  description = "GitHub org owning the repo."
  type        = string
  default     = "jikig-ai"
}

variable "gh_repo" {
  description = "Repository slug under the org."
  type        = string
  default     = "soleur"
}

variable "actions_integration_id" {
  description = "GitHub Actions integration_id. Verified 15368 via `gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.rules[0].parameters.required_status_checks[].integration_id' | sort -u`."
  type        = number
  default     = 15368
}

variable "codeql_integration_id" {
  description = "CodeQL integration_id. Verified 57789 via the same API capture; appears only on the CodeQL rollup check."
  type        = number
  default     = 57789
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
