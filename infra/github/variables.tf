variable "github_app_id" {
  description = "GitHub App ID for soleur-ai (id 3261325). Mirrored from `prd` to `prd_terraform` so the App-auth `provider \"github\"` block can resolve it (see main.tf). Migrated from `gh_token` PAT auth in #4384 per AGENTS.core.md hr-github-app-auth-not-pat."
  type        = string
  sensitive   = true
}

variable "github_app_private_key" {
  description = "PEM-encoded RSA private key for the soleur-ai GitHub App. Mirrored from `prd` to `prd_terraform` for the App-auth provider. One-shot download at App creation; cannot be re-downloaded. Migrated from `gh_token` PAT auth in #4384."
  type        = string
  sensitive   = true
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
