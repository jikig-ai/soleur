resource "cloudflare_r2_bucket" "cla_evidence" {
  account_id = var.cf_account_id
  name       = "soleur-cla-evidence"
  # Plan referenced `location_hint`; cloudflare/cloudflare v4.52.x renamed it
  # to `location`. Allowed values: apac, eeur, enam, weur, wnam, oc.
  location = "WEUR"

  lifecycle {
    prevent_destroy = true
  }
}
