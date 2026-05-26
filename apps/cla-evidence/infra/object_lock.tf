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
# (The empty-prefix form is documented as "rules without a prefix apply
# to all objects in the bucket"; the post-apply `--live` check asserts
# `rule_count >= 1 && maxAgeSeconds >= 315360000` so a misshaped PUT
# cannot silently void the WORM guarantee.)
#
# The cloudflare/cloudflare provider v4.52.x ships `cloudflare_r2_bucket_lock`
# only for object-key-level rule-based age/date conditions (a different
# feature surface), so the bucket-default Lock Rules PUT remains the
# `null_resource` + `curl` shim below. FW1 in the plan tracks swapping
# when CF ships a native TF resource for this endpoint.
#
# Operator preconditions:
#   - curl + jq installed.
#   - var.cf_admin_token sourced from the bootstrap-only one-hour
#     CF admin token (Account → Cloudflare R2 → Edit scope).
#   - the bucket already exists (cloudflare_r2_bucket.cla_evidence).
#
# Single source of truth: `local.lock_rule_json` is the only place the
# rule body is constructed. Both the `triggers.config_hash` (which decides
# re-fire) and the `--data` payload (what hits the wire) consume it, so a
# future maintainer editing one cannot silently desync from the other.

locals {
  lock_rule = {
    rules = [{
      id      = "cla-evidence-10yr-retention"
      enabled = true
      prefix  = ""
      condition = {
        type          = "Age"
        maxAgeSeconds = 315360000
      }
    }]
  }
  lock_rule_json = jsonencode(local.lock_rule)
}

resource "null_resource" "cla_evidence_object_lock" {
  depends_on = [cloudflare_r2_bucket.cla_evidence]

  triggers = {
    bucket_name = cloudflare_r2_bucket.cla_evidence.name
    account_id  = var.cf_account_id
    config_hash = sha256(local.lock_rule_json)
    # Admin tokens are ephemeral one-hour creds (see bootstrap.sh header);
    # this trigger guarantees a re-fire on every bootstrap rather than
    # detecting drift. The CF Lock Rules PUT is idempotent so re-fires
    # are no-ops state-wise.
    token_hash = sha256(var.cf_admin_token)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    # Pass the admin token via environment (NOT string-interpolated into
    # argv) so it does not appear in `/proc/<pid>/cmdline` or in any
    # debug log capture of the rendered provisioner command.
    environment = {
      CF_ACCOUNT_ID    = var.cf_account_id
      CF_BUCKET        = cloudflare_r2_bucket.cla_evidence.name
      CF_ADMIN_TOKEN   = var.cf_admin_token
      CF_LOCK_RULE     = local.lock_rule_json
      CF_MAX_AGE_FLOOR = "315360000"
    }
    command = <<-EOT
      set -euo pipefail
      response=$(curl --max-time 30 -fsS -X PUT \
        "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets/$CF_BUCKET/lock" \
        -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$CF_LOCK_RULE")
      # Stricter than `success == true`: assert the rule list landed with
      # at least one Age rule satisfying the 10-year floor. CF can return
      # success:true with a malformed body that no-ops the PUT; this
      # closes that gap at apply-time rather than deferring to the
      # post-apply --live check (which is also load-bearing, see
      # main.test.sh --live).
      echo "$response" | jq -e --argjson floor "$CF_MAX_AGE_FLOOR" '
        .success == true
        and (.result.rules | length >= 1)
        and ([.result.rules[]? | select(.condition.type == "Age") | .condition.maxAgeSeconds] | max // 0) >= $floor
      ' >/dev/null || { echo "CF Lock Rules PUT failed or rule shape regressed: $response" >&2; exit 1; }
    EOT
  }
}

# Tombstones prefix: the GDPR Art. 17 admin-override flow writes
# `tombstones/<sha>.deleted.json` records. R2 Lock Rules apply bucket-wide
# when `prefix:""`, so the same 10-year `maxAgeSeconds` floor covers the
# tombstones/ prefix automatically. Documented here for inspection clarity
# rather than configured separately.
