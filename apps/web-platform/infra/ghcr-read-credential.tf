# GHCR read:packages credential (#6005). The app + inngest-bootstrap GHCR packages
# flipped PRIVATE, breaking the anonymous host `docker pull` AND the deploy-time cosign
# signature fetch. This publishes a scoped, read-only, machine-account credential to
# Doppler `soleur/prd` — the config the running host + fresh-boot cloud-init read
# (`--config prd` everywhere: ci-deploy.sh, cloud-init.yml). Mirrors the github-app.tf
# doppler_secret precedent (config = "prd", ignore_changes = [value]).
#
# Ownership / auth-model decision (ADR-086 D1, ADR-082 amendment): a scoped fine-grained
# PAT on a MACHINE account over the two jikig-ai packages, recorded as a DELIBERATE,
# narrow, read-only exception to hr-github-app-auth-not-pat. security-sentinel affirmed
# this as the security-SUPERIOR choice for a SINGLE OPERATOR: the on-host App-installation
# path would force the org-wide-WRITE App private key onto the host at token-mint time (a
# ~2-order-of-magnitude larger blast radius than a single-package READ token).
#
# INTERIM (ADR-087): this PAT is the single-operator BOOTSTRAP. GitHub has no API to create
# a PAT (browser + 2FA only), so it does not scale to zero-touch multi-tenant (Concierge)
# provisioning. ADR-087 supersedes D1 with a control-plane Inngest minter that issues 1h
# `packages:read` App-installation tokens into this same Doppler key (consumers unchanged;
# `ignore_changes = [value]` lets the minter own value churn). The migration follow-up is
# gated to land BEFORE any tenant host pulls a private package. See ADR-087 + AP-016.
#
# Provisioning ORDER (L1 — do NOT skip): mint the credential → write the value into
# Doppler `prd_terraform` (the TF runner's TF_VAR source) → verify present → THEN merge
# this file (the auto-apply resolves every root var before -target pruning; a missing
# TF_VAR fails the whole apply). TF_VAR_ghcr_read_token has NO default
# (hr-tf-variable-no-operator-mint-default). dev is intentionally NOT provisioned: the
# host reads `--config prd` exclusively, so a dev copy would only double the at-rest
# surface of a read-only token with no reader (hr-dev-prd-distinct). Add dev only if/
# when a dev host actually pulls a private package.

resource "doppler_secret" "ghcr_read_user" {
  project = "soleur"
  config  = "prd"
  name    = "GHCR_READ_USER"
  value   = var.ghcr_read_user

  lifecycle {
    # dev/prd isolation: this doppler_secret pins config = "prd" explicitly and cannot
    # land in dev without an edit here. Value churn (rotation) is managed at the source
    # of truth (Doppler), not this file — mirrors github-app.tf.
    ignore_changes = [value]
  }
}

resource "doppler_secret" "ghcr_read_token" {
  project = "soleur"
  config  = "prd"
  name    = "GHCR_READ_TOKEN"
  value   = var.ghcr_read_token

  lifecycle {
    ignore_changes = [value]
  }
}
