# Cloudflare R2 Object Lock — Governance mode, 10-year (3650 day) default retention.
#
# As of cloudflare/cloudflare provider v4.x, neither cloudflare_r2_bucket nor
# cloudflare_r2_bucket_lock exposes the bucket-default retention mode (Governance/
# Compliance) — cloudflare_r2_bucket_lock only configures rule-based age/date
# expirations, which is a different feature.
#
# R2's Governance/Compliance bucket-default retention is configured via the
# S3-compatible Object Lock API: PUT /<bucket>?object-lock with
# <ObjectLockConfiguration><ObjectLockEnabled>Enabled</ObjectLockEnabled>
# <Rule><DefaultRetention><Mode>GOVERNANCE</Mode><Days>3650</Days></DefaultRetention></Rule>
# </ObjectLockConfiguration>.
#
# The plan's Risk #3 anticipated this gap; this null_resource is the documented
# fallback. It runs the AWS CLI against the R2 endpoint to set Object Lock once,
# triggered on a content hash so re-applies only re-fire when the desired config
# changes. R2 admin credentials are supplied via Doppler at apply time and never
# enter Terraform state.
#
# Operator preconditions:
#   - aws CLI installed
#   - var.r2_admin_access_key_id and var.r2_admin_secret_access_key sourced from
#     Doppler `prd_cla` (operator-managed, separate from the workflow tokens).
#
# Caveat: R2 Object Lock requires the bucket to have been created with the
# `cf-create-bucket-if-missing` flow and Object Lock enabled at create-time; if
# the bucket pre-exists without Object Lock, the API call below will return an
# error. In that case, contact Cloudflare R2 support to enable Object Lock on
# the existing bucket, or recreate via aws s3api create-bucket
# --object-lock-enabled-for-bucket.

resource "null_resource" "cla_evidence_object_lock" {
  depends_on = [cloudflare_r2_bucket.cla_evidence]

  triggers = {
    bucket_name = cloudflare_r2_bucket.cla_evidence.name
    config_hash = sha256("governance-3650")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      AWS_ACCESS_KEY_ID="${var.r2_admin_access_key_id}" \
      AWS_SECRET_ACCESS_KEY="${var.r2_admin_secret_access_key}" \
      AWS_REGION=auto \
      aws s3api put-object-lock-configuration \
        --bucket ${cloudflare_r2_bucket.cla_evidence.name} \
        --endpoint-url ${var.r2_s3_endpoint} \
        --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","Days":3650}}}'
    EOT
  }
}

# Tombstones prefix: separately object-locked sub-prefix used by the GDPR Art. 17
# admin-override flow (see Phase 7 runbook). The tombstone is itself retained
# under Governance for the same 10yr period so the chain shows "object H replaced
# by tombstone T at month M+1" in the next monthly RFC 3161 manifest.
#
# In R2 Object Lock there is no per-prefix retention configuration distinct from
# the bucket default; the bucket-default Governance + 3650 days already covers
# the tombstones/ prefix. This is documented here for inspection clarity rather
# than configured separately.
