variable "gh_token" {
  description = "Fine-grained PAT for ruleset CRUD. Sourced from Doppler prd_terraform/GH_RULESET_PAT via the tf-var name transformer."
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
