variable "cf_api_token_rundevoo" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token scoped to the rundevoo.run zone: Zone:Read + DNS Write + Zone Settings Write. Minted by infra/rundevoo-run/bootstrap.sh into Doppler prd_terraform (CF_API_TOKEN_RUNDEVOO -> TF_VAR_cf_api_token_rundevoo under --name-transformer tf-var). Zone:DNS:Edit alone CANNOT read the zone (GET /zones/{id} 403s) — Zone Read is load-bearing. DNSSEC is covered by DNS Write (PATCH /zones/{id}/dnssec's accepted permission per the API reference); Zone Settings Write covers cloudflare_zone attribute PATCHes on drift. THIS DESCRIPTION IS THE SCOPE LEDGER — a new resource type in this root needs a matching permission here AND on the live token, or the apply 403s. Verify any re-scope by live probe, never by the permission label (ADR-130). No default: fail closed rather than mint a placeholder credential (hr-tf-variable-no-operator-mint-default)."

  # No default — see description. A credential-less `terraform plan` aborts on
  # this variable; that is intentional: this root must NEVER plan under the
  # broad cf_api_token (the apply workflow maps CLOUDFLARE_API_TOKEN explicitly
  # from CF_API_TOKEN_RUNDEVOO with no fallback).
}
