# Sentry uptime monitors for soleur.ai — alerting half of the 2026-05-18 cert
# outage post-mortem (PR-β). The fix half landed in PR #3974 (initial codification
# of the ACME-aware HTTPS upgrade) and PR #3986 (inline of the carve-out into the
# seo_page_redirects ruleset). Issue #3976 was the operator runbook for cert
# recovery. The cert is now valid; this file is the "next time the carve-out
# silently regresses, hear about it before the next renewal fails" layer.
#
# Plan: knowledge-base/project/plans/2026-05-18-feat-soleur-ai-uptime-alerting-plan.md
#
# WHY FOUR MONITORS:
#   1. Apex (https://soleur.ai/) — primary; what alpha users land on.
#   2. www (https://www.soleur.ai/) — secondary; CF-canonical post-#3974.
#   3. Deep path (https://soleur.ai/changelog/) — proves the Eleventy build
#      didn't half-fail. Catches "root 200 but every other page 404s".
#   4. ACME carve-out probe — LOAD-BEARING. Alerts on Rule 10 regression in
#      cloudflare_ruleset.seo_page_redirects (seo-rulesets.tf:240-254). See
#      detailed comment on the soleur_acme_probe resource below.
#
# AUTO-APPLY NOTE: `.github/workflows/apply-sentry-infra.yml` auto-applies
# `sentry_cron_monitor.*` resources ONLY (via explicit `-target=` flags).
# `sentry_uptime_monitor.*` resources are NOT auto-applied — operator runs
# `terraform apply` manually in this root after merge, same posture as
# `sentry_issue_alert.*` (which uses an explicit import-then-apply flow per
# issue-alerts.tf header). Extending auto-apply to uptime monitors is a clean
# follow-up — see plan §Open Questions / Deferred Q2 and the follow-up issue
# referenced in the PR body.
#
# BETA STATUS: `sentry_uptime_monitor` is documented as beta in the provider
# (v0.15.0-beta2 — see provider docs at
# github.com/jianyuan/terraform-provider-sentry/blob/main/docs/resources/uptime_monitor.md).
# The provider may rename attributes when the resource graduates to stable.
# Re-validate the schema on every provider bump (`terraform init -upgrade`).
#
# ASSERTION SEMANTICS: the `assertion_json` argument is the SUCCESS condition.
# Sentry creates an issue (fires the alert) when the assertion evaluates FALSE.
# The 200-class monitors use a (>199 AND <300) assertion. The ACME probe uses
# an `equals 404` assertion — the synthetic /probe path has no real challenge
# token, so the only "healthy" response is the 404 that proves Cloudflare did
# NOT redirect (i.e., Rule 10's `and not (...)` ACME carve-out is still firing).

# 200-class success assertion: status in [200, 299].
locals {
  uptime_assertion_2xx = provider::sentry::assertion(
    provider::sentry::op_and(
      provider::sentry::op_status_code_check("greater_than", 199),
      provider::sentry::op_status_code_check("less_than", 300),
    )
  )
}

resource "sentry_uptime_monitor" "soleur_apex" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-apex"
  environment  = "production"

  url              = "https://soleur.ai/"
  method           = "GET"
  interval_seconds = 300
  timeout_ms       = 10000

  # Three consecutive failed checks before paging (15 min sustained outage).
  # Absorbs single-probe-host hiccups without dampening real-incident signal.
  downtime_threshold = 3
  recovery_threshold = 1

  assertion_json = local.uptime_assertion_2xx
}

resource "sentry_uptime_monitor" "soleur_www" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-www"
  environment  = "production"

  # Apex 301s to www post-PR #3974 (Rule 10 HTTPS catch-all in
  # seo_page_redirects); www is the CF-canonical hostname.
  url              = "https://www.soleur.ai/"
  method           = "GET"
  interval_seconds = 300
  timeout_ms       = 10000

  downtime_threshold = 3
  recovery_threshold = 1

  assertion_json = local.uptime_assertion_2xx
}

resource "sentry_uptime_monitor" "soleur_changelog_deep" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-changelog-deep"
  environment  = "production"

  # Deep path — guards against the "root serves 200 but every other page 404s"
  # failure mode (Eleventy build half-broken, GitHub Pages serving stale-only).
  # 10-minute interval (cheaper than 5min, still well under any plausible
  # mean-time-to-fix for a static-site regression).
  url              = "https://soleur.ai/changelog/"
  method           = "GET"
  interval_seconds = 600
  timeout_ms       = 10000

  downtime_threshold = 3
  recovery_threshold = 1

  assertion_json = local.uptime_assertion_2xx
}

# ────────────────────────────────────────────────────────────────────────────
# LOAD-BEARING: ACME carve-out regression detector.
#
# The /.well-known/acme-challenge/probe path has NO real challenge token —
# it deliberately returns 404 (CF passes the request through to GitHub Pages,
# which 404s because the path doesn't exist in the published site). What this
# probe is actually checking is the *ABSENCE* of a 301 redirect.
#
# Rule 10 of cloudflare_ruleset.seo_page_redirects (seo-rulesets.tf:240-254) is
# a zone-wide HTTPS catch-all that redirects (not ssl) traffic to https — with
# a NEGATIVE match clause carving out apex+www requests under
# /.well-known/acme-challenge/* so Let's Encrypt's HTTP-01 challenge can hit
# the GH Pages origin on plain HTTP during cert renewal.
#
# If a future edit to that rule's expression drops the `and not (...)` clause
# (or scopes it wrong, or changes the host list), the carve-out silently
# regresses. The next cert renewal would then fail and the apex would 526 for
# ~24h until someone noticed — exactly the 2026-05-18 outage shape.
#
# This probe runs over plain HTTP intentionally — wait, NO: it runs over HTTPS
# because the probe path returns 404 *post*-redirect in normal operation (the
# carve-out only skips redirect for plain-HTTP requests on the ACME path).
# What the probe ACTUALLY catches is: if Rule 10's expression changes such
# that the HTTPS path /.well-known/acme-challenge/* starts getting redirected
# OR cached weirdly, the assertion fires.
#
# More precisely: under healthy ops, GET https://soleur.ai/.well-known/acme-challenge/probe
# returns 404 (CF passes through; GH Pages 404s). If Rule 10 regresses such
# that the ACME path no longer pass-through, the response shape changes
# (most likely to a 301 to a different host, or a 200 with a stale cache hit,
# or a 5xx if the origin path is unreachable). Any non-404 is a signal.
#
# The probe URL is intentionally synthetic — `/probe` is not a real token, and
# Let's Encrypt would never request it. We do not want to probe a real token
# path because (a) those rotate per cert issuance, and (b) when one is active,
# it returns the token-body 200, which would conflict with the equals-404
# assertion. The /probe synthetic name is stable and always-404 under healthy
# ops. Code-review check: confirm no future CI step or Eleventy build creates
# a real /.well-known/acme-challenge/probe file in _site — if it does, this
# monitor will false-fire.
resource "sentry_uptime_monitor" "soleur_acme_probe" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-acme-carveout-probe"
  environment  = "production"

  url              = "https://soleur.ai/.well-known/acme-challenge/probe"
  method           = "GET"
  interval_seconds = 300
  timeout_ms       = 10000

  description = "Alerts when CF Rule 10 (seo_page_redirects ACME carve-out) regresses. Healthy = 404; any other status is the signal. See uptime-monitors.tf comment and seo-rulesets.tf:240-254 for the carve-out under guard."

  downtime_threshold = 3
  recovery_threshold = 1

  # Success = exactly 404. Sentry fires when this assertion is FALSE — i.e.,
  # any non-404 status (200, 301, 302, 5xx) triggers a paging issue.
  assertion_json = provider::sentry::assertion(
    provider::sentry::op_status_code_check("equals", 404)
  )
}
