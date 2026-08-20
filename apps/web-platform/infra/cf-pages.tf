# Cloudflare Pages project for the marketing/docs site (ADR-194, #7640).
#
# WHY THIS EXISTS
#
# soleur.ai is served by GitHub Pages behind Cloudflare's proxy, and two platform
# requirements conflict irreconcilably: domains.md MANDATES proxied = true (the HSTS
# preload commitment), while GitHub Pages refuses to issue or renew a certificate for a
# proxied host (pages/health reports is_https_eligible: false). Renewal needs the same
# eligibility as issuance, so the origin certificate expires every 90 days BY
# CONSTRUCTION and cannot self-heal. That caused an ~8h15m apex outage on 2026-08-16.
#
# Cloudflare Pages is served BY Cloudflare, so there is no origin certificate at all.
# The failure class stops existing rather than being managed. See ADR-194 for the
# measured evidence that retired the alternative (a 2026-08-19 renewal window ran under
# conditions verified correct in advance and produced no state change in 62 minutes).
#
# DIRECT UPLOAD, NOT THE GIT INTEGRATION
#
# There is deliberately no `source` block below. `source` is what binds a Pages project
# to the git integration, which would build the site on Cloudflare's runners and bypass
# deploy-docs.yml entirely — taking all six gates (SEO, CSP, canonical-host, build
# verification, critical-CSS, Playwright screenshot/FOUC) out of the deploy path. Direct
# upload keeps the existing gate chain authoritative: Eleventy still builds in Actions,
# every gate still runs, and only the terminal publish step changes.

resource "cloudflare_pages_project" "docs" {
  provider   = cloudflare.pages
  account_id = var.cf_account_id
  name       = "soleur-docs"

  # Required by the v4 schema even for a direct-upload project, and it is the SOLE
  # determinant of whether a given deploy reaches the custom domain or is filed as a
  # preview alias. It must equal the --branch that deploy-docs.yml passes to
  # `wrangler pages deploy`; www-apex-canonicalizer.test.sh mutation row M7 asserts the
  # two agree, because a silent divergence here publishes every deploy to a preview URL
  # while the custom domain keeps serving the last matching build.
  production_branch = "main"
}

# ‼️ THE CUSTOM DOMAINS ARE NOT IN THIS PR — they land in PR3.
#
# Attaching soleur.ai to a Pages project with ZERO deployments would, if
# Hypothesis Z holds ("the apex begins serving from Pages at the moment of
# attachment"), move the apex origin to an empty project and serve Cloudflare's
# error page on an HSTS-preloaded hostname. `apply-web-platform-infra.yml` runs
# ON MERGE, so no gate can catch that first — the measurement would be a
# post-hoc observation of a production mutation, not a gate.
#
# The sequence is therefore substrate (here) -> deploy path -> attach -> record
# swap, which is correct under BOTH branches of Z rather than only the preferred
# one: whichever of attachment or the DNS record actually selects the origin,
# reverting the PR that introduced it removes it. See "## Delivery Sequencing".
#
# Z itself is measured in PR2 against a scratch hostname whose topology is
# identical to the apex (proxied A record at a GitHub Pages IP + a Pages custom
# domain on the same account and zone), so no production name is touched.

# ---------------------------------------------------------------------------
# Publication to GitHub Actions
# ---------------------------------------------------------------------------
#
# ROTATION POLICY. These two secrets republish values Terraform already holds; they are
# not an independent source of truth. To rotate the token: mint the replacement in the
# Cloudflare dashboard, write it to Doppler prd_terraform as CF_API_TOKEN_PAGES, then
# re-apply this root — the Actions secret follows. Never edit the Actions secret directly
# in the GitHub UI: the next apply would silently revert it to the Doppler value, and the
# two would disagree for however long it took someone to notice.
#
# The honest note ADR-130 requires: the cited kb-drift.tf precedent publishes a DOPPLER
# SERVICE TOKEN — a scoped, independently revocable credential. This publishes the
# terminal Cloudflare credential itself, so after this change the token exists in three
# places (Doppler prd_terraform, terraform.tfstate on R2, GitHub Actions secrets) against
# one rotation. That fan-out is recorded in var.cf_api_token_pages's scope ledger and in
# the plan's Encryption Posture section; a Doppler-service-token indirection is the
# tighter shape and is recorded on the deferred-cleanup issue.
resource "github_actions_secret" "cloudflare_api_token_pages" {
  repository      = "soleur"
  secret_name     = "CLOUDFLARE_API_TOKEN_PAGES"
  plaintext_value = var.cf_api_token_pages
}

# Published alongside the token because deploy-docs.yml runs in the Playwright container,
# and the alternative — reading the account id from Doppler at deploy time — would add a
# Doppler CLI install to that image for a single non-secret value.
resource "github_actions_secret" "cloudflare_account_id_pages" {
  repository      = "soleur"
  secret_name     = "CLOUDFLARE_ACCOUNT_ID_PAGES"
  plaintext_value = var.cf_account_id
}
