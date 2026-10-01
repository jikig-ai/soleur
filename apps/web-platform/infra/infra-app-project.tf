# #9321 / ADR-241 D11 - the isolated home of the two soleur-infra GitHub App values the
# inngest-bootstrap release jobs need (GITHUB_INFRA_APP_ID, GITHUB_INFRA_APP_PRIVATE_KEY).
#
# WHY A PROJECT. The two release jobs are handed, today, a read token for the WHOLE
# soleur-infra-privileged/prd project; a follow-up change switches them to this project's token. A branch config does not isolate (it inherits its
# root's values); only a separate project does. A token scoped to this project's `prd` root
# config reads nothing else.
#
# WHY THIS FILE HOLDS NO SECRET, NO TOKEN AND NO DATA SOURCE. This root's state is readable by
# the Tier-A backend keys (ADR-241 D3/D4), so a `doppler_secret`, a `doppler_service_token` or a
# `data "doppler_secret(s)"` on this project would put the App key, or a token that reads it,
# straight back where this project removes it from. The operator-run bootstrap script copies
# the two values in and mints the read token. Census Guard 7
# (tests/scripts/test-infra-privileged-tier-census.sh) enforces all of this. Same carrier
# shape as github-app-runtime-project.tf.
#
# Every resource here is in the push apply's `-target=` list (apply-web-platform-infra.yml). Nothing reads the
# project until the operator-run bootstrap script has populated it and the switch change has merged.

resource "doppler_project" "infra_app" {
  name = "soleur-infra-app"
  # Doppler caps `description` at 255 (scripts/lint-doppler-description-length.py).
  description = "#9321 ADR-241 D11: the two soleur-infra GitHub App values (id, private key) to be read by the inngest-bootstrap release jobs, isolated from the rest of Tier B. Operator-supplied; never in tfstate."

  lifecycle {
    # Holds a live copy of the infra App private key; the release jobs read it.
    prevent_destroy = true
  }
}

# A TF-created project is born bare (no configs); the environment creates the `prd` root
# config the release jobs' read token is scoped to.
resource "doppler_environment" "infra_app_prd" {
  project = doppler_project.infra_app.name
  slug    = "prd"
  name    = "Production"

  lifecycle {
    prevent_destroy = true
  }
}
