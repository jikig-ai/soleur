# Cloudflare R2 native Lock Rules — 10-year (315360000 second) age-based
# retention floor on the cla-evidence bucket.
#
# Cloudflare R2's S3-compatible API does NOT implement the
# PutObjectLockConfiguration surface — verified empirically during the
# 2026-05-16 post-merge bootstrap of PR #3201. The functional equivalent
# is R2's native Lock Rules endpoint:
#   PUT /accounts/{id}/r2/buckets/{name}/lock
# with body `{"rules":[{...}]}`. Age-based rules pin a `maxAgeSeconds`
# floor; combined with `prefix:""` the rule applies bucket-wide and
# delivers the WORM property the GDPR §3.4 balancing test rests on.
#
# The cloudflare/cloudflare provider v4.52.x ships `cloudflare_r2_bucket_lock`
# only for object-key-level rule-based age/date conditions (a different
# feature surface), so the bucket-default Lock Rules PUT remains the
# `null_resource` + curl shim below. FW1 in the plan tracks swapping the
# shim for a native TF resource when one ships.
#
# Operator preconditions:
#   - curl + jq installed.
#   - var.cf_admin_token sourced from the bootstrap-only one-hour
#     CF admin token (Account → Cloudflare R2 → Edit scope).
#   - the bucket already exists (cloudflare_r2_bucket.cla_evidence).
#
# The rule JSON wraps a single Age rule with `maxAgeSeconds = 315360000`
# (10 years = 365 * 24 * 3600 * 10). The wrapping `rules:` key is
# load-bearing — a bare array body returns HTTP 400 from the CF API.

resource "null_resource" "cla_evidence_object_lock" {
  depends_on = [cloudflare_r2_bucket.cla_evidence]

  triggers = {
    bucket_name = cloudflare_r2_bucket.cla_evidence.name
    config_hash = sha256(jsonencode({
      rules = [{
        id      = "cla-evidence-10yr-retention"
        enabled = true
        prefix  = ""
        condition = {
          type          = "Age"
          maxAgeSeconds = 315360000
        }
      }]
    }))
    token_hash = sha256(var.cf_admin_token)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      lock_rule='{"rules":[{"id":"cla-evidence-10yr-retention","enabled":true,"prefix":"","condition":{"type":"Age","maxAgeSeconds":315360000}}]}'
      response=$(curl --max-time 30 -fsS -X PUT \
        "https://api.cloudflare.com/client/v4/accounts/${var.cf_account_id}/r2/buckets/${cloudflare_r2_bucket.cla_evidence.name}/lock" \
        -H "Authorization: Bearer ${var.cf_admin_token}" \
        -H "Content-Type: application/json" \
        --data "$lock_rule")
      echo "$response" | jq -e '.success == true' >/dev/null \
        || { echo "CF Lock Rules PUT failed: $response" >&2; exit 1; }
    EOT
  }
}

# Tombstones prefix: the GDPR Art. 17 admin-override flow writes
# `tombstones/<sha>.deleted.json` records. R2 Lock Rules apply bucket-wide
# when `prefix:""`, so the same 10-year `maxAgeSeconds` floor covers the
# tombstones/ prefix automatically. Documented here for inspection clarity
# rather than configured separately.
