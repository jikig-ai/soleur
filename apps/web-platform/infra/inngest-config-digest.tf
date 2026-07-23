# Promoted digest pointer for the ADR-135 pull-based signed config-refresh channel (#6780).
#
# INNGEST_CONFIG_DIGEST is the IMMUTABLE @sha256 digest of the currently-promoted,
# keyless-signed config bundle. The dedicated Inngest host's config-refresh timer resolves
# this pointer, pulls the bundle @sha256 GHCR-direct, cosign-verify-blobs it OFFLINE against
# the baked trusted root, checks the per-file sha256 manifest + a monotonic VERSION read only
# from the signed bytes, and applies atomically via infra-config-install.sh (ADR-135).
#
# This mirrors inngest-betterstack-token.tf (Approach B): a `doppler_secret` whose value comes
# from a sensitive, no-default var sourced from Doppler soleur/prd_terraform — only the one
# digest string enters terraform.tfstate, NOT a data.doppler_secrets mirror of the whole map.
# The provider already manages the soleur-inngest project (inngest-host.tf: doppler_project.inngest),
# so it has write access.
#
# ────────────────────────────────────────────────────────────────────────────────────────────
# ⚠️  APPLY ORDERING — DO NOT APPLY THIS RESOURCE ALONE (exact-set isolation self-check).
# ────────────────────────────────────────────────────────────────────────────────────────────
# The boot isolation self-check on soleur-inngest/prd is EXACT-SET (`n_total -ne n_inngest`,
# cloud-init-inngest.yml): every secret in the isolated project MUST be named in the self-check
# regex or the host FATALs on boot. This pointer's admission to the regex + the floor bump live
# in the cloud-init consumer bake, which RIDES the #6178 cutover provision (PR #6348). Applying
# THIS secret before that regex edit lands would brick the dedicated scheduler at its next
# boot/replace. Therefore:
#   • This file is COMMITTED now (ADR-135 producer/pointer foundation, this PR) but the resource
#     is APPLIED at the #6178 cutover, ATOMICALLY with the cloud-init regex+floor edit that admits
#     it (DEC-FLOOR: dark-present so the timer is armed from first boot).
#   • Provisioning ORDER at cutover (do NOT skip): set the first-promoted digest in
#     TF_VAR_inngest_config_digest (soleur/prd_terraform, --name-transformer tf-var) → verify
#     read-only via `doppler secrets get` → land the cloud-init regex+floor admission →
#     THEN apply this resource in the same window (HARD-9: pointer.version > baked-floor.version).
#
# PROMOTION (post-cutover, HARD-6): the value is a PROMOTION OUTPUT, not a rotate-at-source
# secret — each promotion updates TF_VAR_inngest_config_digest and re-applies. So, unlike the
# sibling isolated secrets, this resource does NOT lifecycle{ignore_changes=[value]}: Terraform
# is the deliberate writer, which keeps a standing CI write-token OUT of the isolated project.
# dev is intentionally NOT provisioned: the dark arm64 host reads --config prd exclusively.

resource "doppler_secret" "inngest_config_digest" {
  # Reference the TF-managed project + env (NOT string literals) so Terraform builds the
  # dependency edge — mirrors inngest-betterstack-token.tf so a cold apply / `-target` of the
  # project pulls this secret in and it never schedules before doppler_environment.inngest_prd.
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_CONFIG_DIGEST"
  value      = var.inngest_config_digest
  visibility = "masked"
}
