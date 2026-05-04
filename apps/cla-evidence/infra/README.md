# cla-evidence — Terraform root

Provisions the off-site evidence archive for the CLA signature flow:
`soleur-cla-evidence` R2 bucket (EU region, Governance object-lock, 10-year
retention) plus the two scoped Cloudflare API tokens used by the sidecar
workflow and by Terraform itself.

**Owner:** deruelle / ops@jikigai.com
**Issue:** #3209
**Plan:** `knowledge-base/project/plans/2026-05-04-feat-cla-legal-rigor-evidence-layer-plan.md`
**Runbook:** `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md`
**Retention:** 10 years (3650 days) from object creation, Governance mode.
**Region:** `weur` (Western Europe, best-effort per Cloudflare R2 placement).

## Change-control gate

Edits to this root must:

1. Be reviewed by both CTO and COO equivalents (or the agent-domain leaders for
   `soleur:engineering` and `soleur:operations`).
2. Carry an explicit per-command ack at apply time
   (`hr-menu-option-ack-not-prod-write-auth`) — the operator runs
   `terraform plan`, the assistant shows the diff, the operator types go-ahead,
   then the assistant runs `terraform apply -auto-approve`.
3. Never relax `prevent_destroy`, `Governance`/`COMPLIANCE`, or the 3650-day
   retention without paired updates to `gdpr-policy.md` (off-site-archive
   balancing test) and the inspection runbook.

## Single-writer apply

The R2 backend has no lock (per institutional learning
`2026-03-21-terraform-state-r2-migration.md` — R2 lacks S3 conditional writes
needed for `use_lockfile = true`). Two operators applying simultaneously will
overwrite each other's state. Coordinate via the standard `#ops` Slack channel
before running `terraform apply` here.

## Object Lock provisioning

The Cloudflare Terraform provider (v4.x and v5.x) does not expose Governance/
Compliance bucket-default retention modes — `cloudflare_r2_bucket_lock` is for
rule-based age/date conditions, a different feature. The bucket-default Object
Lock configuration is set via a `null_resource` calling the S3-compatible API
(`aws s3api put-object-lock-configuration`) — see `object_lock.tf`. The R2 admin
credentials for this provisioner are passed in via `r2_admin_access_key_id` /
`r2_admin_secret_access_key` and never enter Terraform state (only their hash
trigger does).

If the bucket pre-exists without Object Lock enabled, the provisioner will fail.
Resolution: contact Cloudflare R2 support to enable Object Lock on the existing
bucket, or recreate the bucket via `aws s3api create-bucket
--object-lock-enabled-for-bucket`.

## Token rotation

- **Object-write token (`R2_CLA_EVIDENCE_*`):** synced to Doppler `prd_cla`
  config, surfaced to workflows via `DOPPLER_TOKEN_CLA` repo secret. Rotation
  cadence: yearly, or on any leak signal. See sibling section in
  `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`.
- **State-write token:** consumed by Terraform only. Rotation cadence: yearly.

## NOT in this root

- IP-allowlist on tokens — rejected at plan-review (DHH F1 + Code-Simplicity F2).
  The bucket holds already-public GitHub identities; the recurring CIDR refresh
  chore is not earned at this scope.
- A `refresh-gh-actions-cidrs.sh` helper. Same reason.
- Read-only standing tokens. Read access is generated ad-hoc via the Cloudflare
  dashboard at retrieval time (see Phase 7 runbook).
