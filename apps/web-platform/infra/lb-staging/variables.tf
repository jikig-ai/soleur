# Fed by `doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var`
# inside cf-lb-overlay.yml — the widened CF_API_TOKEN (zone Load Balancers:Edit +
# account Load Balancing: Monitors and Pools:Edit, landed 2026-10-30 per #11181 F2).

variable "cf_api_token" {
  type      = string
  sensitive = true
}

variable "cf_zone_id" {
  type = string
}

variable "cf_account_id" {
  type = string
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}
