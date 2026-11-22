# The web-platform runtime reads CF_ZONE_ID from Doppler `prd` (cf-cache-purge.ts,
# cron-gh-pages-cert-reissue.ts). Before #12931 that copy was hand-set and went stale the
# moment the zone moved accounts. Managing it here makes it track var.cf_zone_id.
#
# No ignore_changes: the zone id is not a secret, and a stale copy is the defect this file
# exists to remove. Branch configs (prd_*) hold their own copies and are written by the
# runbook (knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md),
# not here. It is a pure Doppler write, so it sits in the push-triggered stage-1 -target list.
resource "doppler_secret" "cf_zone_id_prd" {
  project = "soleur"
  config  = "prd"
  name    = "CF_ZONE_ID"
  value   = var.cf_zone_id
}
