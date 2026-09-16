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
}

variable "github_app_private_key" {
  description = "PEM private key for the GitHub App (mirrored into prd_terraform)."
  type        = string
  sensitive   = true
}
